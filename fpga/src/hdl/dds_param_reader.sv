`timescale 1ns/1ps
`default_nettype none

`include "params.vh"
`include "dds_param_protocol.vh"

// ============================================================================
// 模块名称：dds_param_reader
//
// 主要功能：
//   从参数双口 BRAM 的 PL 只读端口轮询 Mode0 频率快照，检查协议头、发布状态
//   和 generation 一致性，并向 dds_freq_ctrl 提交一次新的 unsigned Hz 频率。
//   本模块不解析 UART、不计算 DDS 相位增量，也不写参数 BRAM。
//
// 使用方法：
//   1. 将 BRAM 读端口连接到 ps_bram_subsystem_wrapper 的 param_pl_* 端口。
//   2. 将 dds_freq_hz/dds_freq_we 连接到 dds_freq_ctrl。
//   3. PS 必须按照“先 BUSY、最后 VALID”的顺序发布完整快照。
//
// 连接说明：
//   clk/rst_n               <- 30 MHz DDS 数据通路时钟及其同步低有效复位
//   bram_en/addr/rdata      <-> 参数 BRAM Port B，同步读、字节地址
//   dds_freq_hz/dds_freq_we -> dds_freq_ctrl
//   active_generation       -> 可选 ILA 状态观察
//   protocol_error          -> 可选 ILA/状态模块，表示稳定快照格式非法
//
// 时钟与复位：
//   所有业务端口属于 clk 域；rst_n 同步低有效。参数 BRAM Port A 可由 PS 100 MHz
//   异步写入，Port B 使用本 clk。前后两次 generation 和最终 STATUS 复核用于拒绝
//   PS 正在改写时读到的撕裂快照。
//
// 输入/输出格式：
//   bram_addr 是窗口内 32 位 byte offset，必须四字节对齐；bram_rdata 为同步读出的
//   little-endian 32 位 word。dds_freq_hz 为 unsigned Hz。
//
// 握手时序：
//   每个读地址保持一个请求周期，下一周期采样 bram_rdata。合法且 generation 新增
//   时，dds_freq_hz 与 dds_freq_we 同拍更新，dds_freq_we 仅持续一个 clk 周期。
//
// 参数说明：
//   POLL_CYCLES 为两轮检查间的最少 clk 周期数，必须大于等于 1。
//
// 错误行为：
//   BUSY 和读取中途更新只会丢弃本轮；ERROR 状态、错误头、错误格式或越界频率
//   置 protocol_error，并保持最近一次有效频率。后续合法快照会清除错误。
//
// 使用限制：
//   BRAM 读延迟按一个时钟周期设计。若以后启用额外输出寄存器，必须增加等待拍。
// ============================================================================
module dds_param_reader #(
    parameter int unsigned POLL_CYCLES = 256 // 参数快照轮询间隔，单位 clk 周期
) (
    input  wire  logic        clk,               // 参数读取及 DDS 控制时钟
    input  wire  logic        rst_n,             // clk域同步低有效复位

    output       logic        bram_en,           // 参数 BRAM 同步读使能
    output       logic [31:0] bram_addr,         // 参数 BRAM 窗口内 byte offset
    input  wire  logic [31:0] bram_rdata,        // 参数 BRAM 同步读数据

    output       logic [31:0] dds_freq_hz,       // 已接受的目标频率，unsigned Hz
    output       logic        dds_freq_we,       // 新频率提交脉冲，持续一个 clk 周期
    output       logic [31:0] active_generation, // 最近接受的 generation
    output       logic        protocol_error     // 稳定快照协议错误，合法快照清除
);

    localparam int unsigned POLL_W = (POLL_CYCLES <= 1) ? 1 : $clog2(POLL_CYCLES);

    typedef enum logic [4:0] {
        ST_POLL,
        ST_REQ_STATUS_A, ST_CAP_STATUS_A,
        ST_REQ_GEN_A,    ST_CAP_GEN_A,
        ST_REQ_MAGIC,    ST_CAP_MAGIC,
        ST_REQ_VERSION,  ST_CAP_VERSION,
        ST_REQ_COUNT,    ST_CAP_COUNT,
        ST_REQ_FORMAT,   ST_CAP_FORMAT,
        ST_REQ_FREQ,     ST_CAP_FREQ,
        ST_REQ_GEN_B,    ST_CAP_GEN_B,
        ST_REQ_STATUS_B, ST_CAP_STATUS_B
    } state_t;

    state_t state;
    logic [POLL_W-1:0] poll_count;
    logic              active_valid;
    logic [31:0]       gen_a;
    logic [31:0]       gen_b;
    logic [31:0]       magic_value;
    logic [31:0]       version_value;
    logic [31:0]       count_value;
    logic [31:0]       format_value;
    logic [31:0]       freq_value;

    initial begin
        assert (POLL_CYCLES >= 1)
            else $fatal(1, "POLL_CYCLES 必须大于等于 1");
    end

    // 仅在请求状态驱动读使能和地址；所有地址均为 BRAM 窗口内 byte offset。
    always_comb begin
        bram_en   = 1'b0;
        bram_addr = 32'd0;
        case (state)
            ST_REQ_STATUS_A, ST_REQ_STATUS_B: begin
                bram_en   = 1'b1;
                bram_addr = `DDS_PARAM_ADDR_STATUS;
            end
            ST_REQ_GEN_A, ST_REQ_GEN_B: begin
                bram_en   = 1'b1;
                bram_addr = `DDS_PARAM_ADDR_GENERATION;
            end
            ST_REQ_MAGIC: begin
                bram_en   = 1'b1;
                bram_addr = `DDS_PARAM_ADDR_MAGIC;
            end
            ST_REQ_VERSION: begin
                bram_en   = 1'b1;
                bram_addr = `DDS_PARAM_ADDR_VERSION;
            end
            ST_REQ_COUNT: begin
                bram_en   = 1'b1;
                bram_addr = `DDS_PARAM_ADDR_WORD_COUNT;
            end
            ST_REQ_FORMAT: begin
                bram_en   = 1'b1;
                bram_addr = `DDS_PARAM_ADDR_FORMAT;
            end
            ST_REQ_FREQ: begin
                bram_en   = 1'b1;
                bram_addr = `DDS_PARAM_ADDR_FREQ_HZ;
            end
            default: begin
                bram_en   = 1'b0;
                bram_addr = 32'd0;
            end
        endcase
    end

    // 使用同步复位，避免异步复位状态寄存器直接驱动RAMB地址而触发REQP-1839。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state             <= ST_POLL;
            poll_count        <= '0;
            active_valid      <= 1'b0;
            gen_a             <= 32'd0;
            gen_b             <= 32'd0;
            magic_value       <= 32'd0;
            version_value     <= 32'd0;
            count_value       <= 32'd0;
            format_value      <= 32'd0;
            freq_value        <= 32'd0;
            dds_freq_hz       <= `DDS_FREQ_DFLT_HZ;
            dds_freq_we       <= 1'b0;
            active_generation <= 32'd0;
            protocol_error    <= 1'b0;
        end else begin
            dds_freq_we <= 1'b0;

            case (state)
                ST_POLL: begin
                    if ((POLL_CYCLES <= 1) || (poll_count == POLL_CYCLES-1)) begin
                        poll_count <= '0;
                        state      <= ST_REQ_STATUS_A;
                    end else begin
                        poll_count <= poll_count + 1'b1;
                    end
                end

                ST_REQ_STATUS_A: state <= ST_CAP_STATUS_A;
                ST_CAP_STATUS_A: begin
                    if (bram_rdata[1:0] == `DDS_PARAM_STATUS_VALID) begin
                        state <= ST_REQ_GEN_A;
                    end else begin
                        if (bram_rdata[1:0] == `DDS_PARAM_STATUS_ERROR)
                            protocol_error <= 1'b1;
                        state <= ST_POLL;
                    end
                end

                ST_REQ_GEN_A: state <= ST_CAP_GEN_A;
                ST_CAP_GEN_A: begin gen_a <= bram_rdata; state <= ST_REQ_MAGIC; end
                ST_REQ_MAGIC: state <= ST_CAP_MAGIC;
                ST_CAP_MAGIC: begin magic_value <= bram_rdata; state <= ST_REQ_VERSION; end
                ST_REQ_VERSION: state <= ST_CAP_VERSION;
                ST_CAP_VERSION: begin version_value <= bram_rdata; state <= ST_REQ_COUNT; end
                ST_REQ_COUNT: state <= ST_CAP_COUNT;
                ST_CAP_COUNT: begin count_value <= bram_rdata; state <= ST_REQ_FORMAT; end
                ST_REQ_FORMAT: state <= ST_CAP_FORMAT;
                ST_CAP_FORMAT: begin format_value <= bram_rdata; state <= ST_REQ_FREQ; end
                ST_REQ_FREQ: state <= ST_CAP_FREQ;
                ST_CAP_FREQ: begin freq_value <= bram_rdata; state <= ST_REQ_GEN_B; end
                ST_REQ_GEN_B: state <= ST_CAP_GEN_B;
                ST_CAP_GEN_B: begin gen_b <= bram_rdata; state <= ST_REQ_STATUS_B; end
                ST_REQ_STATUS_B: state <= ST_CAP_STATUS_B;

                ST_CAP_STATUS_B: begin
                    // generation 或最终状态变化表示 PS 正在发布，只重试而不报协议错误。
                    if ((bram_rdata[1:0] == `DDS_PARAM_STATUS_VALID) && (gen_a == gen_b)) begin
                        if ((magic_value   == `DDS_PARAM_MAGIC) &&
                            (version_value == `DDS_PARAM_VERSION) &&
                            (count_value   == `DDS_PARAM_WORD_COUNT) &&
                            (format_value  == `DDS_PARAM_FORMAT_FREQ_HZ) &&
                            (freq_value    >= `DDS_FREQ_MIN_HZ) &&
                            (freq_value    <= `DDS_FREQ_MAX_HZ)) begin
                            protocol_error <= 1'b0;
                            if (!active_valid || (gen_b != active_generation)) begin
                                dds_freq_hz       <= freq_value;
                                dds_freq_we       <= 1'b1;
                                active_generation <= gen_b;
                                active_valid      <= 1'b1;
                            end
                        end else begin
                            protocol_error <= 1'b1;
                        end
                    end
                    state <= ST_POLL;
                end

                default: begin
                    state      <= ST_POLL;
                    poll_count <= '0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire

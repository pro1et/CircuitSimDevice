`timescale 1ns / 1ps

`include "params.vh"

// ============================================================================
// 模块名称：sweep_ctrl
//
// 主要功能：
//   负责扫频任务控制、DDS 频率步进、调用 sweep_iq_demod 完成单点 I/Q 测量，
//   并按 PS 端共享 BRAM 协议发布测量快照。本模块不做 I/Q 乘法累加，I/Q
//   算法由 sweep_iq_demod 独立完成。
//
// 使用方法：
//   1. PS/控制寄存器在本 clk 域内给 step_we/start_we/clear_we 单周期脉冲。
//   2. start_we 被接受后，本模块先写测量 BRAM STATUS=BUSY 和 header。
//   3. 每个频点下发 DDS 频率，然后拉高 iq_start 启动 sweep_iq_demod。
//   4. iq_done 到来后，把 direct/filtered 两个 word 写入 payload。
//   5. 全部 payload 写完后，先写 WORD_COUNT，再写 GENERATION，最后写 STATUS。
//
// 连接说明：
//   dds_freq_hz/dds_freq_we -> 顶层 DDS 频率 mux，再到 dds_freq_ctrl。
//   iq_start               -> sweep_iq_demod.start。
//   iq_done/direct/filtered<- sweep_iq_demod 输出。
//   bram_*                 -> 测量 BRAM Port B；Port A 由 PS 的 AXI BRAM 控制器访问。
//
// 时钟与复位：
//   所有端口除 rst_n 外均同步到 clk。rst_n 为异步低有效复位。来自 AXI/PS
//   时钟域的控制脉冲必须在进入本模块前完成 CDC。
//
// 输入格式：
//   step_wdata_hz 为 unsigned Hz，内部钳位到 STEP_MIN_HZ..STEP_MAX_HZ。
//   iq_* 四个结果为 signed int16，来自 sweep_iq_demod。
//
// 输出格式：
//   测量 BRAM header 使用统一协议：
//   0x00 MAGIC='MEAS'，0x04 VERSION=0x00010000，0x08 GENERATION，
//   0x0C STATUS，0x10 WORD_COUNT，0x14 FORMAT=1，0x18 ERROR_CODE。
//   payload 从 0x40 开始，每个频点两个 32 bit word：
//   word[2*n+0]={I_direct,Q_direct}，word[2*n+1]={I_filtered,Q_filtered}。
//
// 握手时序：
//   start_we 只在 busy=0 时接受。dds_freq_we、iq_start 和 BRAM 写使能均为单周期
//   脉冲。done/error 为保持型状态，通过 clear_we 清除。
//
// 参数说明：
//   FREQ_START_HZ/FREQ_STOP_HZ/STEP_* 决定扫频范围。当前 PS 协议文档默认
//   frequency(n)=200Hz+n*20Hz；若实际 step_cfg_hz 不是 20Hz，PS 侧频率轴也必须
//   同步调整。
//
// 错误行为：
//   若 IQ 模块报告错误，或结果点数超过 MAX_POINTS，则发布 STATUS=ERROR，
//   ERROR_CODE 写入非零值，并同样递增 GENERATION。
//
// 使用限制：
//   测量 BRAM 遵循单写者规则：PL 写，PS 只读。STATUS 必须最后写，本模块已经
//   固化该顺序，外部逻辑不要并行驱动同一 BRAM Port B。
// ============================================================================
module sweep_ctrl #(
    parameter integer DATA_W        = `BOARD_DATA_W, // 保留参数，用于与顶层数据位宽保持一致。
    parameter integer MAX_POINTS    = 2991           // 最大扫频点数，当前 200Hz..60kHz、20Hz 步进为 2991。
) (
    // 本模块工作时钟，必须与 DDS、IQ 测量和 BRAM Port B 同域。
    input  wire                  clk,
    // 异步低有效复位，清零扫频状态、BRAM 控制和发布 generation。
    input  wire                  rst_n,

    // 单周期脉冲：锁存并钳位 step_wdata_hz。
    input  wire                  step_we,
    // 请求的扫频步进，单位 Hz。
    input  wire [31:0]           step_wdata_hz,
    // 单周期脉冲：启动一轮新扫频，仅 busy=0 时接受。
    input  wire                  start_we,
    // 单周期脉冲：清除保持型 done/error 状态。
    input  wire                  clear_we,

    // IQ 模块启动脉冲；连接 sweep_iq_demod.start。
    output reg                   iq_start,
    // IQ 模块忙标志；为高时本模块等待单点测量完成。
    input  wire                  iq_busy,
    // IQ 模块完成脉冲；为高时四个 IQ 输入同周期有效。
    input  wire                  iq_done,
    // IQ 模块错误标志；为高时本模块发布测量 ERROR。
    input  wire                  iq_error,
    // 直通/参考通道 I，signed int16，写入 payload word0[31:16]。
    input  wire signed [15:0]    direct_i,
    // 直通/参考通道 Q，signed int16，写入 payload word0[15:0]。
    input  wire signed [15:0]    direct_q,
    // 滤波/被测通道 I，signed int16，写入 payload word1[31:16]。
    input  wire signed [15:0]    filtered_i,
    // 滤波/被测通道 Q，signed int16，写入 payload word1[15:0]。
    input  wire signed [15:0]    filtered_q,

    // 当前扫频频点对应的 DDS 目标频率，单位 Hz。
    output reg  [31:0]           dds_freq_hz,
    // 单周期脉冲：通知 dds_freq_ctrl 加载 dds_freq_hz。
    output reg                   dds_freq_we,
    // 扫频占用 DDS 频率控制通路时为高；顶层 mux 用它选择扫频频率。
    output reg                   active,
    // 扫频任务运行中为高。
    output reg                   busy,
    // 扫频成功完成后保持为高；clear_we 清除。
    output reg                   done,
    // 扫频失败后保持为高；clear_we 清除。
    output reg                   error,
    // 已写入 payload 的扫频点数，不是 BRAM WORD_COUNT。
    output reg  [31:0]           result_count,
    // 实际生效的扫频步进，单位 Hz，已钳位。
    output reg  [31:0]           step_cfg_hz,

    // 测量 BRAM Port B 时钟；直接连接 clk。
    output wire                  bram_clkb,
    // 测量 BRAM Port B 高有效复位；由 ~rst_n 生成。
    output wire                  bram_rstb,
    // 测量 BRAM Port B 使能；写 header/payload/status 时拉高。
    output reg                   bram_enb,
    // 测量 BRAM Port B 字节写使能；32 bit 写为 4'hF，空闲为 0。
    output reg  [3:0]            bram_web,
    // 测量 BRAM Port B 字节地址，必须按 word_index<<2 驱动。
    output reg  [31:0]           bram_addrb,
    // 测量 BRAM Port B 32 bit 写数据。
    output reg  [31:0]           bram_dinb,
    // 测量 BRAM Port B 读数据；本模块作为写入者不使用该信号。
    input  wire [31:0]           bram_doutb
);
    localparam [31:0] FREQ_START_HZ = 32'd200;
    localparam [31:0] FREQ_STOP_HZ  = 32'd60000;
    localparam [31:0] STEP_MIN_HZ   = 32'd20;
    localparam [31:0] STEP_MAX_HZ   = 32'd200;

    localparam [31:0] OFF_MAGIC      = 32'h00;
    localparam [31:0] OFF_VERSION    = 32'h04;
    localparam [31:0] OFF_GENERATION = 32'h08;
    localparam [31:0] OFF_STATUS     = 32'h0C;
    localparam [31:0] OFF_WORD_COUNT = 32'h10;
    localparam [31:0] OFF_FORMAT     = 32'h14;
    localparam [31:0] OFF_ERROR_CODE = 32'h18;
    localparam [31:0] OFF_RESERVED0  = 32'h1C;
    localparam [31:0] OFF_PAYLOAD    = 32'h40;

    localparam [31:0] MEAS_MAGIC     = 32'h4D45_4153; // ASCII "MEAS"。
    localparam [31:0] VERSION        = 32'h0001_0000;
    localparam [31:0] FORMAT_IQ_X4   = 32'd1;
    localparam [31:0] STATUS_BUSY    = 32'd0;
    localparam [31:0] STATUS_DONE    = 32'd1;
    localparam [31:0] STATUS_ERROR   = 32'd2;
    localparam [31:0] ERROR_NONE     = 32'd0;
    localparam [31:0] ERROR_IQ       = 32'd1;
    localparam [31:0] ERROR_OVERFLOW = 32'd2;

    localparam [4:0] ST_IDLE         = 5'd0;
    localparam [4:0] ST_BUSY_STATUS  = 5'd1;
    localparam [4:0] ST_HDR_MAGIC    = 5'd2;
    localparam [4:0] ST_HDR_VERSION  = 5'd3;
    localparam [4:0] ST_HDR_COUNT    = 5'd4;
    localparam [4:0] ST_HDR_FORMAT   = 5'd5;
    localparam [4:0] ST_HDR_ERROR    = 5'd6;
    localparam [4:0] ST_HDR_RSVD     = 5'd7;
    localparam [4:0] ST_SET_FREQ     = 5'd8;
    localparam [4:0] ST_START_IQ     = 5'd9;
    localparam [4:0] ST_WAIT_IQ      = 5'd10;
    localparam [4:0] ST_WRITE_DIRECT = 5'd11;
    localparam [4:0] ST_WRITE_FILTER = 5'd12;
    localparam [4:0] ST_NEXT         = 5'd13;
    localparam [4:0] ST_PUB_COUNT    = 5'd14;
    localparam [4:0] ST_PUB_ERROR    = 5'd15;
    localparam [4:0] ST_PUB_GEN      = 5'd16;
    localparam [4:0] ST_PUB_STATUS   = 5'd17;
    localparam [4:0] ST_FINISH       = 5'd18;

    reg [4:0] state;
    reg [31:0] current_freq_hz;
    reg [31:0] generation;
    reg [31:0] next_generation;
    reg [31:0] error_code;
    reg [3:0] reserved_index;
    reg last_point_pending;

    assign bram_clkb = clk;
    assign bram_rstb = ~rst_n;
    wire unused_bram_dout = |bram_doutb;
    wire unused_iq_busy = iq_busy;

    function [31:0] clamp_step;
        input [31:0] value;
        begin
            if (value < STEP_MIN_HZ)
                clamp_step = STEP_MIN_HZ;
            else if (value > STEP_MAX_HZ)
                clamp_step = STEP_MAX_HZ;
            else
                clamp_step = value;
        end
    endfunction

    task bram_write_word;
        input [31:0] byte_addr;
        input [31:0] data;
        begin
            bram_enb   <= 1'b1;
            bram_web   <= 4'hF;
            bram_addrb <= byte_addr;
            bram_dinb  <= data;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            current_freq_hz    <= FREQ_START_HZ;
            generation         <= 32'd0;
            next_generation    <= 32'd0;
            error_code         <= ERROR_NONE;
            reserved_index     <= 4'd0;
            last_point_pending <= 1'b0;
            dds_freq_hz        <= FREQ_START_HZ;
            dds_freq_we        <= 1'b0;
            iq_start           <= 1'b0;
            active             <= 1'b0;
            busy               <= 1'b0;
            done               <= 1'b0;
            error              <= 1'b0;
            result_count       <= 32'd0;
            step_cfg_hz        <= STEP_MIN_HZ;
            bram_enb           <= 1'b0;
            bram_web           <= 4'h0;
            bram_addrb         <= 32'd0;
            bram_dinb          <= 32'd0;
        end else begin
            dds_freq_we <= 1'b0;
            iq_start    <= 1'b0;
            bram_enb    <= 1'b0;
            bram_web    <= 4'h0;

            if (!busy && step_we)
                step_cfg_hz <= clamp_step(step_wdata_hz);

            if (clear_we) begin
                done  <= 1'b0;
                error <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    active <= 1'b0;
                    if (start_we && !busy) begin
                        busy               <= 1'b1;
                        done               <= 1'b0;
                        error              <= 1'b0;
                        active             <= 1'b1;
                        current_freq_hz    <= FREQ_START_HZ;
                        result_count       <= 32'd0;
                        error_code         <= ERROR_NONE;
                        reserved_index     <= 4'd0;
                        last_point_pending <= 1'b0;
                        next_generation    <= generation + 1'b1;
                        state              <= ST_BUSY_STATUS;
                    end
                end

                ST_BUSY_STATUS: begin
                    bram_write_word(OFF_STATUS, STATUS_BUSY);
                    state <= ST_HDR_MAGIC;
                end

                ST_HDR_MAGIC: begin
                    bram_write_word(OFF_MAGIC, MEAS_MAGIC);
                    state <= ST_HDR_VERSION;
                end

                ST_HDR_VERSION: begin
                    bram_write_word(OFF_VERSION, VERSION);
                    state <= ST_HDR_COUNT;
                end

                ST_HDR_COUNT: begin
                    bram_write_word(OFF_WORD_COUNT, 32'd0);
                    state <= ST_HDR_FORMAT;
                end

                ST_HDR_FORMAT: begin
                    bram_write_word(OFF_FORMAT, FORMAT_IQ_X4);
                    state <= ST_HDR_ERROR;
                end

                ST_HDR_ERROR: begin
                    bram_write_word(OFF_ERROR_CODE, ERROR_NONE);
                    reserved_index <= 4'd0;
                    state <= ST_HDR_RSVD;
                end

                ST_HDR_RSVD: begin
                    bram_write_word(OFF_RESERVED0 + {reserved_index, 2'b00}, 32'd0);
                    if (reserved_index == 4'd8)
                        state <= ST_SET_FREQ;
                    else
                        reserved_index <= reserved_index + 1'b1;
                end

                ST_SET_FREQ: begin
                    dds_freq_hz <= current_freq_hz;
                    dds_freq_we <= 1'b1;
                    state <= ST_START_IQ;
                end

                ST_START_IQ: begin
                    iq_start <= 1'b1;
                    state <= ST_WAIT_IQ;
                end

                ST_WAIT_IQ: begin
                    if (iq_error) begin
                        error      <= 1'b1;
                        error_code <= ERROR_IQ;
                        state      <= ST_PUB_COUNT;
                    end else if (iq_done) begin
                        if (result_count >= MAX_POINTS) begin
                            error      <= 1'b1;
                            error_code <= ERROR_OVERFLOW;
                            state      <= ST_PUB_COUNT;
                        end else begin
                            state <= ST_WRITE_DIRECT;
                        end
                    end
                end

                ST_WRITE_DIRECT: begin
                    bram_write_word(OFF_PAYLOAD + (result_count << 3),
                                    {direct_i[15:0], direct_q[15:0]});
                    state <= ST_WRITE_FILTER;
                end

                ST_WRITE_FILTER: begin
                    bram_write_word(OFF_PAYLOAD + (result_count << 3) + 32'd4,
                                    {filtered_i[15:0], filtered_q[15:0]});
                    result_count <= result_count + 1'b1;
                    state <= ST_NEXT;
                end

                ST_NEXT: begin
                    if (last_point_pending) begin
                        state <= ST_PUB_COUNT;
                    end else if ((current_freq_hz + step_cfg_hz) >= FREQ_STOP_HZ) begin
                        current_freq_hz    <= FREQ_STOP_HZ;
                        last_point_pending <= 1'b1;
                        state              <= ST_SET_FREQ;
                    end else begin
                        current_freq_hz <= current_freq_hz + step_cfg_hz;
                        state           <= ST_SET_FREQ;
                    end
                end

                ST_PUB_COUNT: begin
                    bram_write_word(OFF_WORD_COUNT, result_count << 1);
                    state <= ST_PUB_ERROR;
                end

                ST_PUB_ERROR: begin
                    bram_write_word(OFF_ERROR_CODE, error_code);
                    state <= ST_PUB_GEN;
                end

                ST_PUB_GEN: begin
                    bram_write_word(OFF_GENERATION, next_generation);
                    generation <= next_generation;
                    state <= ST_PUB_STATUS;
                end

                ST_PUB_STATUS: begin
                    bram_write_word(OFF_STATUS, error ? STATUS_ERROR : STATUS_DONE);
                    state <= ST_FINISH;
                end

                ST_FINISH: begin
                    busy   <= 1'b0;
                    active <= 1'b0;
                    done   <= ~error;
                    state  <= ST_IDLE;
                end

                default: begin
                    error      <= 1'b1;
                    error_code <= ERROR_OVERFLOW;
                    state      <= ST_PUB_COUNT;
                end
            endcase
        end
    end
endmodule

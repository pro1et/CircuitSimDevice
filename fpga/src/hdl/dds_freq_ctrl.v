`timescale 1ns / 1ps

`include "params.vh"

// ============================================================================
// 模块名称：dds_freq_ctrl
//
// 主要功能：
//   将目标 DDS 输出频率（单位 Hz）换算为 DDS Compiler IP 需要的相位增量配置字。
//   本模块只负责频率到 phase increment 的控制换算，不产生 DDS 波形。
//
// 使用方法：
//   1. 上游把目标频率稳定驱动到 dds_freq_hz。
//   2. 若需要立即下发配置，对 dds_freq_we 拉高 1 个 clk 周期。
//   3. 本模块在检测到 dds_freq_we 或频率值变化后，经过计算状态输出
//      dds_cfg_tvalid 单周期脉冲和 dds_cfg_tdata 配置字。
//   4. dds_cfg_tvalid/dds_cfg_tdata 直接连接到 dds_wrapper。
//
// 连接说明：
//   clk/dds_freq_hz/dds_freq_we <- 顶层 DDS 频率 mux。手动模式来自 PS/HMI
//   控制寄存器，扫频模式来自 sweep_ctrl。
//   dds_cfg_tvalid/dds_cfg_tdata -> dds_wrapper 的 DDS IP 配置输入。
//   dds_phase_inc -> 可接 ILA 或 PS 只读状态，用于核对实际相位增量。
//
// 时钟与复位：
//   所有端口除 rst_n 外均同步到 clk。rst_n 为异步低有效复位；复位释放后会
//   自动下发一次 DDS_FREQ_DFLT_HZ 对应的默认配置。
//
// 输入格式：
//   dds_freq_hz 为 unsigned Hz。进入本模块前必须已经完成 CDC，不能直接接
//   AXI/PS 时钟域的多 bit 总线。
//
// 输出格式：
//   dds_cfg_tdata 为 32 bit 配置字，低 PHASE_W 位为 phase increment，高位补 0。
//   phase_inc = round(freq_hz * 2^PHASE_W / SAMPLE_CLK_HZ)。
//
// 握手时序：
//   dds_freq_we 为单周期请求脉冲；dds_cfg_tvalid 为单周期输出脉冲。当前
//   DDS IP 配置接口没有 tready，因此上游不要依赖 ready/valid 双向握手。
//
// 参数说明：
//   SAMPLE_CLK_HZ 必须等于 DDS IP 的 aclk 频率。
//   PHASE_W 必须与 DDS IP 配置的相位增量宽度一致。
//
// 错误行为：
//   输入频率低于 DDS_FREQ_MIN_HZ 或高于 DDS_FREQ_MAX_HZ 时会被钳位，不置 error。
//
// 使用限制：
//   若顶层 mux 在扫频和手动模式间切换，必须保证 dds_freq_hz/dds_freq_we 在
//   clk 域内稳定，避免跨域组合切换。
// ============================================================================
module dds_freq_ctrl #(
    parameter integer SAMPLE_CLK_HZ = `SAMPLE_CLK_HZ,
    parameter integer PHASE_W       = `DDS_PHASE_W
) (
    // 模块工作时钟，同时也是 DDS IP 配置时钟。
    input  wire      clk,
    // 异步低有效复位；复位释放后自动下发默认频率配置。
    input  wire      rst_n,
    // 目标 DDS 输出频率，单位 Hz；来自手动控制或 sweep_ctrl。
    input  wire [31:0] dds_freq_hz,
    // 重新配置请求，单周期脉冲；频率未变化时也会强制下发。
    input  wire      dds_freq_we,
    // DDS 配置有效输出，单周期脉冲，连接 dds_wrapper。
    output reg       dds_cfg_tvalid,
    // DDS 32 bit 配置字；低 PHASE_W 位为相位增量。
    output reg [31:0] dds_cfg_tdata,
    // 计算后的相位增量，可用于 PS/ILA 调试读回。
    output reg [PHASE_W-1:0] dds_phase_inc
);

    // 三步配置状态机：等待请求、计算相位增量、下发 DDS 配置。
    localparam [1:0]   CFG_IDLE    = 2'd0;
    localparam [1:0]   CFG_CALC    = 2'd1;
    localparam [1:0]   CFG_ISSUE   = 2'd2;

    reg init_cfg_pending;
    reg [1:0] cfg_state;
    reg [31:0] dds_freq_seen;
    reg [31:0] freq_hz_latched;
    reg [PHASE_W-1:0] phase_inc_calc;

    // 将请求频率限制在 DDS 支持的工作范围内。
    function [31:0] clamp_freq_hz;
        input [31:0] value;
        begin
            if (value < `DDS_FREQ_MIN_HZ)
                clamp_freq_hz = `DDS_FREQ_MIN_HZ;
            else if (value > `DDS_FREQ_MAX_HZ)
                clamp_freq_hz = `DDS_FREQ_MAX_HZ;
            else
                clamp_freq_hz = value;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_cfg_pending <= 1'b1;
            cfg_state        <= CFG_IDLE;
            dds_freq_seen    <= `DDS_FREQ_DFLT_HZ;
            freq_hz_latched  <= 32'd0;
            phase_inc_calc   <= {PHASE_W{1'b0}};
            dds_cfg_tvalid   <= 1'b0;
            dds_cfg_tdata    <= 32'd0;
            dds_phase_inc    <= {PHASE_W{1'b0}};
        end else begin
            dds_cfg_tvalid <= 1'b0;

            case (cfg_state)
                CFG_IDLE: begin
                    // 复位后配置一次；之后在软件/扫频请求新频率时重新配置。
                    if (init_cfg_pending || (dds_freq_hz != dds_freq_seen) || dds_freq_we) begin
                        dds_freq_seen    <= dds_freq_hz;
                        freq_hz_latched  <= clamp_freq_hz(dds_freq_hz);
                        init_cfg_pending <= 1'b0;
                        cfg_state        <= CFG_CALC;
                    end
                end

                CFG_CALC: begin
                    // DDS 原理：
                    // phase_inc = round(freq_hz * 2^PHASE_W / SAMPLE_CLK_HZ)
                    phase_inc_calc <= ((freq_hz_latched * (64'd1 << PHASE_W)) +
                                       (SAMPLE_CLK_HZ / 2)) / SAMPLE_CLK_HZ;
                    cfg_state      <= CFG_ISSUE;
                end

                CFG_ISSUE: begin
                    dds_phase_inc  <= phase_inc_calc;
                    // DDS IP 接收 32 bit 配置字，相位增量放在低 PHASE_W 位。
                    dds_cfg_tdata  <= {{(32-PHASE_W){1'b0}}, phase_inc_calc};
                    dds_cfg_tvalid <= 1'b1;
                    cfg_state      <= CFG_IDLE;
                end

                default: begin
                    cfg_state <= CFG_IDLE;
                end
            endcase
        end
    end

endmodule

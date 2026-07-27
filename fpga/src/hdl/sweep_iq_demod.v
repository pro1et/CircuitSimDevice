`timescale 1ns / 1ps

`include "params.vh"

// ============================================================================
// 模块名称：sweep_iq_demod
//
// 主要功能：
//   对单个扫频频点执行 I/Q 解调测量。本模块只负责“等待稳定、按 DDS 相位
//   周期对齐、累加固定周期数、输出 int16 I/Q 结果”，不负责频率步进、不控制
//   BRAM，也不直接访问 PS/PL 协议区。
//
// 使用方法：
//   1. sweep_ctrl 在 DDS 频率已经下发后，对 start 拉高 1 个 clk 周期。
//   2. 本模块先等待 SETTLE_CYCLES，再等 DDS 相位回绕对齐到完整周期边界。
//   3. 连续累加 MEASURE_CYCLES 个 DDS 周期后，done 拉高 1 个 clk 周期。
//   4. sweep_ctrl 在 done 周期采样 direct/filtered 四个 int16 输出。
//
// 连接说明：
//   clk/dds/adc  <- 同一个采样时钟域，当前顶层连接 sample_clk_30m。
//   start        <- sweep_ctrl 的单周期启动脉冲。
//   adc0_data    <- AD1，被测电路输出 Y(f)。
//   dds_*        <- dds_wrapper 输出，作为本地参考 X(f) 和周期边界。
//   direct_*     -> sweep_ctrl，写入测量 BRAM word0。
//   filtered_*   -> sweep_ctrl，写入测量 BRAM word1。
//
// 时钟与复位：
//   所有端口除 rst_n 外均同步到 clk。rst_n 为异步低有效复位，复位后 busy、
//   done、error 和输出结果均清零。
//
// 输入格式：
//   adc0_data、dds_sine_data、dds_cosine_data 均为 signed 二进制补码，位宽为
//   DATA_W。dds_phase_data 为 DDS 相位累加器输出，出现从大到小的回绕时表示
//   一个 DDS 周期结束。
//
// 输出格式：
//   direct/filtered 四个分量均为 signed int16 二进制补码。direct 当前表示内部
//   DDS 参考通道 X，filtered 表示 adc0_data 测得的被测输出 Y。
//
// 握手时序：
//   start 仅在 busy=0 时被接受。busy 在测量期间保持为高；done 为单周期脉冲，
//   与输出结果同周期有效。error 预留给参数/数据异常，当前正常算法不会置位。
//
// 参数说明：
//   DATA_W         为输入采样位宽，必须大于 0。
//   SETTLE_CYCLES  为每个频点改频后的等待时钟数。
//   MEASURE_CYCLES 为每个频点累计的 DDS 完整周期数，必须大于 0。
//   IQ_SHIFT       为 48 bit 累加值输出到 int16 前的右移缩放量。
//
// 错误行为：
//   busy=1 时再次 start 会被忽略。若 DDS phase 长时间没有回绕，模块会保持
//   busy，不会输出伪结果。
//
// 使用限制：
//   adc_valid 和 dds_valid 应在同一 clk 域内对齐。若 ADC 或 DDS 来自其他时钟域，
//   必须先在上游完成 CDC。
// ============================================================================
module sweep_iq_demod #(
    parameter integer DATA_W         = `BOARD_DATA_W, // 输入采样位宽，单位 bit。
    parameter integer SETTLE_CYCLES  = 450000,        // 改频后的稳定等待周期数。
    parameter integer MEASURE_CYCLES = 16,            // 每个频点累计的 DDS 完整周期数。
    parameter integer IQ_SHIFT       = 25             // 累加值输出到 int16 前的右移量。
) (
    // 本模块工作时钟，必须与 ADC/DDS 数据同域。
    input  wire                       clk,
    // 异步低有效复位，清零状态机、累加器和输出结果。
    input  wire                       rst_n,

    // 单周期启动脉冲；仅 busy=0 时接受。
    input  wire                       start,

    // ADC0 数据有效信号；为高时 adc0_data 是新的有效采样。
    input  wire                       adc_valid,
    // ADC0 signed 采样，被测输出 Y(f)，二进制补码。
    input  wire signed [DATA_W-1:0]   adc0_data,

    // DDS sine/cosine 数据有效信号，来自 dds_wrapper。
    input  wire                       dds_valid,
    // DDS sine signed 参考采样，二进制补码。
    input  wire signed [DATA_W-1:0]   dds_sine_data,
    // DDS cosine signed 参考采样，二进制补码。
    input  wire signed [DATA_W-1:0]   dds_cosine_data,
    // DDS 相位有效信号；为高时 dds_phase_data 可用于判断相位回绕。
    input  wire                       dds_phase_valid,
    // DDS 相位累加器输出；由大变小表示 DDS 周期回绕。
    input  wire [31:0]                dds_phase_data,

    // 测量进行中标志；从接受 start 到 done 前保持为高。
    output reg                        busy,
    // 单周期完成脉冲；为高时四个 I/Q 输出同周期有效。
    output reg                        done,
    // 异常标志；当前算法无运行时错误，保留给后续超时/参数检查。
    output reg                        error,

    // 直通/参考通道 I 分量，signed int16；当前固定为 0。
    output reg signed [15:0]          direct_i,
    // 直通/参考通道 Q 分量，signed int16；当前为 -sum(sin_ref*sin_ref) 缩放后结果。
    output reg signed [15:0]          direct_q,
    // 滤波/被测通道 I 分量，signed int16；由 adc0_data*cos_ref 累加得到。
    output reg signed [15:0]          filtered_i,
    // 滤波/被测通道 Q 分量，signed int16；由 -adc0_data*sin_ref 累加得到。
    output reg signed [15:0]          filtered_q
);
    localparam integer MULT_W = DATA_W * 2;

    localparam [1:0] ST_IDLE    = 2'd0;
    localparam [1:0] ST_SETTLE  = 2'd1;
    localparam [1:0] ST_ALIGN   = 2'd2;
    localparam [1:0] ST_MEASURE = 2'd3;

    reg [1:0] state;
    reg [31:0] settle_count;
    reg [15:0] cycle_count;
    reg [31:0] phase_d;
    reg        phase_seen;

    reg signed [47:0] acc_direct_q;
    reg signed [47:0] acc_filtered_i;
    reg signed [47:0] acc_filtered_q;
    reg signed [MULT_W-1:0] mult_direct_q;
    reg signed [MULT_W-1:0] mult_filtered_i;
    reg signed [MULT_W-1:0] mult_filtered_q;

    wire phase_wrap = dds_phase_valid && phase_seen && (dds_phase_data < phase_d);

    function signed [15:0] sat16_from_acc;
        input signed [47:0] value;
        reg signed [47:0] scaled;
        begin
            scaled = value >>> IQ_SHIFT;
            if (scaled > 48'sd32767)
                sat16_from_acc = 16'sh7FFF;
            else if (scaled < -48'sd32768)
                sat16_from_acc = 16'sh8000;
            else
                sat16_from_acc = scaled[15:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            settle_count   <= 32'd0;
            cycle_count    <= 16'd0;
            phase_d        <= 32'd0;
            phase_seen     <= 1'b0;
            acc_direct_q   <= 48'sd0;
            acc_filtered_i <= 48'sd0;
            acc_filtered_q <= 48'sd0;
            direct_i       <= 16'sd0;
            direct_q       <= 16'sd0;
            filtered_i     <= 16'sd0;
            filtered_q     <= 16'sd0;
            busy           <= 1'b0;
            done           <= 1'b0;
            error          <= 1'b0;
        end else begin
            done <= 1'b0;

            if (dds_phase_valid) begin
                phase_d    <= dds_phase_data;
                phase_seen <= 1'b1;
            end

            case (state)
                ST_IDLE: begin
                    busy  <= 1'b0;
                    error <= 1'b0;
                    if (start) begin
                        busy           <= 1'b1;
                        settle_count   <= 32'd0;
                        cycle_count    <= 16'd0;
                        phase_seen     <= 1'b0;
                        acc_direct_q   <= 48'sd0;
                        acc_filtered_i <= 48'sd0;
                        acc_filtered_q <= 48'sd0;
                        state          <= ST_SETTLE;
                    end
                end

                ST_SETTLE: begin
                    if (settle_count >= SETTLE_CYCLES - 1) begin
                        state <= ST_ALIGN;
                    end else begin
                        settle_count <= settle_count + 1'b1;
                    end
                end

                ST_ALIGN: begin
                    if (phase_wrap) begin
                        acc_direct_q   <= 48'sd0;
                        acc_filtered_i <= 48'sd0;
                        acc_filtered_q <= 48'sd0;
                        cycle_count    <= 16'd0;
                        state          <= ST_MEASURE;
                    end
                end

                ST_MEASURE: begin
                    if (adc_valid && dds_valid) begin
                        // direct 通道使用内部 DDS 参考形成 X，避免再依赖 AD2 回环。
                        mult_direct_q   = dds_sine_data * dds_sine_data;
                        mult_filtered_i = adc0_data * dds_cosine_data;
                        mult_filtered_q = adc0_data * dds_sine_data;

                        acc_direct_q   <= acc_direct_q -
                                          {{(48-MULT_W){mult_direct_q[MULT_W-1]}}, mult_direct_q};
                        acc_filtered_i <= acc_filtered_i +
                                          {{(48-MULT_W){mult_filtered_i[MULT_W-1]}}, mult_filtered_i};
                        acc_filtered_q <= acc_filtered_q -
                                          {{(48-MULT_W){mult_filtered_q[MULT_W-1]}}, mult_filtered_q};
                    end

                    if (phase_wrap) begin
                        if (cycle_count >= MEASURE_CYCLES - 1) begin
                            direct_i   <= 16'sd0;
                            direct_q   <= sat16_from_acc(acc_direct_q);
                            filtered_i <= sat16_from_acc(acc_filtered_i);
                            filtered_q <= sat16_from_acc(acc_filtered_q);
                            busy       <= 1'b0;
                            done       <= 1'b1;
                            state      <= ST_IDLE;
                        end else begin
                            cycle_count <= cycle_count + 1'b1;
                        end
                    end
                end

                default: begin
                    busy  <= 1'b0;
                    error <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule

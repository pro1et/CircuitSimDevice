`timescale 1ns / 1ps
`default_nettype none

`include "params.vh"

// ============================================================================
// 模块名称：fir_filter
//
// 主要功能：
//   对低速有效脉冲标记的 signed 采样执行可装载系数的定点FIR滤波。模块使用
//   MAC_LANES路并行乘加器分时遍历全部抽头，避免为每个抽头永久占用一个DSP。
//
// 使用方法：
//   1. 复位释放后，由fir_coef_loader先拉高coef_clear，再连续写入全部Q1.31系数。
//   2. 系数装载完成后，sample_valid为高的clk上升沿提交一个新采样。
//   3. 等待ceil(TAP_COUNT/MAC_LANES)个计算周期，out_valid拉高一拍并给出结果。
//   4. 上游必须保证相邻有效采样的间隔不小于上述计算周期数。
//
// 连接说明：
//   clk                      <- clock_tree输出的处理时钟，任务D中为30 MHz
//   rst_n                    <- 本时钟域复位取反后的低有效复位
//   sample_valid/sample_data <- adc_decimator_100的输出
//   coef_*                   <- fir_coef_loader的系数写接口
//   out_valid/out_data       -> fir_data_adapter的FIR输出侧
//
// 时钟与复位：
//   全部逻辑工作在clk域。rst_n异步低有效；复位会清除样本历史、计算状态和输出，
//   同时清零系数。任务D中的rst_n来自clock_tree同步释放的rst_30m取反。
//
// 输入格式：
//   sample_data为DATA_W位signed二进制补码。coef_wdata为signed Q1.31，实际值为
//   coef_wdata/2^31；coef_addr合法范围为0..TAP_COUNT-1。
//
// 输出格式：
//   out_data为DATA_W位signed二进制补码。完整乘加结果加2^30后算术右移31位，
//   即按既有链路采用半LSB偏置舍入，随后饱和到DATA_W位范围。
//
// 握手时序：
//   sample_valid只在模块空闲时被接收。模块没有反压端口；忙期间到达的额外
//   sample_valid会被忽略，因此系统必须按参数约束保证输入间隔。out_valid只保持
//   一个clk周期，与对应out_data同拍有效；out_data在下一结果前保持。
//
// 参数说明：
//   DATA_W为采样位宽，必须大于等于2；TAP_COUNT为抽头数，范围2..256；ACC_W为
//   累加器位宽，至少为DATA_W+32+$clog2(TAP_COUNT)；MAC_LANES为并行乘加路数，
//   范围1..TAP_COUNT。任务D采用129抽头、56位累加器和2路MAC，计算65拍。
//
// 错误行为：
//   越界coef_addr写入被忽略。coef_clear优先终止正在进行的计算并清空历史。
//   系数更新期间不得提交采样；顶层通过coef_ready门控sample_valid。
//
// 使用限制：
//   本接口没有ready/busy输出，必须由系统静态保证采样间隔。若提高等效采样率，
//   应增加MAC_LANES或增加握手接口，并重新检查DSP资源和30 MHz时序。
// ============================================================================
module fir_filter #(
    parameter integer DATA_W    = `BOARD_DATA_W, // 输入/输出采样位宽，单位bit，必须大于等于2
    parameter integer TAP_COUNT = 129,           // FIR抽头数，范围2..256
    parameter integer ACC_W     = 56,            // 累加器位宽，必须覆盖乘积及抽头增长位
    parameter integer MAC_LANES = 2              // 每周期并行计算的抽头数，范围1..TAP_COUNT
) (
    input  wire                         clk,          // 模块工作时钟，任务D连接30 MHz处理时钟
    input  wire                         rst_n,        // 异步低有效复位，释放必须已在clk域同步

    input  wire                         sample_valid, // 输入采样有效脉冲，空闲时接收一拍
    input  wire signed [DATA_W-1:0]     sample_data,  // signed二进制补码输入采样

    input  wire                         coef_we,      // 系数写使能，单周期有效
    input  wire [7:0]                   coef_addr,    // 系数抽头地址，合法范围0..TAP_COUNT-1
    input  wire signed [31:0]           coef_wdata,   // signed Q1.31系数写数据
    input  wire                         coef_clear,   // 高有效单周期清除系数、历史和当前计算

    output reg                          out_valid,    // 输出有效脉冲，与out_data同拍有效
    output reg signed [DATA_W-1:0]      out_data      // 饱和后的signed二进制补码滤波结果
);
    localparam integer INDEX_W = $clog2(TAP_COUNT);
    localparam integer TAP_W   = $clog2(TAP_COUNT + MAC_LANES);
    localparam integer MIN_ACC_W = DATA_W + 32 + $clog2(TAP_COUNT);

    reg signed [31:0] coeff [0:TAP_COUNT-1];
    reg signed [DATA_W-1:0] samples [0:TAP_COUNT-1];

    reg [INDEX_W-1:0] write_index;
    reg [INDEX_W-1:0] newest_index;
    reg [TAP_W-1:0] tap_index;
    reg signed [ACC_W-1:0] accumulator;
    reg busy;

    reg signed [DATA_W+31:0] lane_product [0:MAC_LANES-1];
    reg signed [ACC_W-1:0] lane_sum;
    reg signed [ACC_W-1:0] completed_sum;
    integer lane;
    integer tap_number;
    integer sample_index;
    integer reset_index;

    initial begin
        if (DATA_W < 2)
            $error("DATA_W必须大于等于2");
        if ((TAP_COUNT < 2) || (TAP_COUNT > 256))
            $error("TAP_COUNT必须在2到256之间");
        if ((MAC_LANES < 1) || (MAC_LANES > TAP_COUNT))
            $error("MAC_LANES必须在1到TAP_COUNT之间");
        if (ACC_W < MIN_ACC_W)
            $error("ACC_W不足，至少需要%0d位", MIN_ACC_W);
    end

    function signed [ACC_W-1:0] extend_product;
        input signed [DATA_W+31:0] value;
        begin
            extend_product = {{(ACC_W-(DATA_W+32)){value[DATA_W+31]}}, value};
        end
    endfunction

    function signed [DATA_W-1:0] saturate_sample;
        input signed [ACC_W-1:0] value;
        reg signed [ACC_W-1:0] scaled;
        reg signed [ACC_W-1:0] maximum;
        reg signed [ACC_W-1:0] minimum;
        begin
            scaled  = value >>> 31;
            maximum = ({{(ACC_W-1){1'b0}}, 1'b1} << (DATA_W-1)) - 1'b1;
            minimum = -({{(ACC_W-1){1'b0}}, 1'b1} << (DATA_W-1));
            if (scaled > maximum)
                saturate_sample = {1'b0, {(DATA_W-1){1'b1}}};
            else if (scaled < minimum)
                saturate_sample = {1'b1, {(DATA_W-1){1'b0}}};
            else
                saturate_sample = scaled[DATA_W-1:0];
        end
    endfunction

    // 每个组合乘加支路处理一个抽头。newest_index指向当前输入样本所在的环形
    // 缓冲位置，抽头k读取newest_index-k对应的历史样本。
    always @(*) begin
        lane_sum = {ACC_W{1'b0}};
        for (lane = 0; lane < MAC_LANES; lane = lane + 1) begin
            lane_product[lane] = {(DATA_W+32){1'b0}};
            tap_number = tap_index + lane;
            sample_index = 0;
            if (tap_number < TAP_COUNT) begin
                if (newest_index >= tap_number)
                    sample_index = newest_index - tap_number;
                else
                    sample_index = newest_index + TAP_COUNT - tap_number;
                lane_product[lane] = samples[sample_index] * coeff[tap_number];
                lane_sum = lane_sum + extend_product(lane_product[lane]);
            end
        end
    end

    always @(*) begin
        // 保持与原实现一致的Q1.31半LSB偏置舍入规则。
        completed_sum = accumulator + lane_sum +
                        ({{(ACC_W-1){1'b0}}, 1'b1} << 30);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_index <= {INDEX_W{1'b0}};
            newest_index <= {INDEX_W{1'b0}};
            tap_index <= {TAP_W{1'b0}};
            accumulator <= {ACC_W{1'b0}};
            busy <= 1'b0;
            out_valid <= 1'b0;
            out_data <= {DATA_W{1'b0}};
            for (reset_index = 0; reset_index < TAP_COUNT; reset_index = reset_index + 1) begin
                coeff[reset_index] <= 32'sd0;
                samples[reset_index] <= {DATA_W{1'b0}};
            end
        end else begin
            out_valid <= 1'b0;

            if (coef_clear) begin
                write_index <= {INDEX_W{1'b0}};
                newest_index <= {INDEX_W{1'b0}};
                tap_index <= {TAP_W{1'b0}};
                accumulator <= {ACC_W{1'b0}};
                busy <= 1'b0;
                out_data <= {DATA_W{1'b0}};
                for (reset_index = 0; reset_index < TAP_COUNT; reset_index = reset_index + 1) begin
                    coeff[reset_index] <= 32'sd0;
                    samples[reset_index] <= {DATA_W{1'b0}};
                end
            end else begin
                if (coef_we && (coef_addr < TAP_COUNT))
                    coeff[coef_addr] <= coef_wdata;

                if (busy) begin
                    if ((tap_index + MAC_LANES) >= TAP_COUNT) begin
                        out_data <= saturate_sample(completed_sum);
                        out_valid <= 1'b1;
                        accumulator <= {ACC_W{1'b0}};
                        tap_index <= {TAP_W{1'b0}};
                        busy <= 1'b0;
                    end else begin
                        accumulator <= accumulator + lane_sum;
                        tap_index <= tap_index + MAC_LANES;
                    end
                end else if (sample_valid) begin
                    samples[write_index] <= sample_data;
                    newest_index <= write_index;
                    if (write_index == TAP_COUNT-1)
                        write_index <= {INDEX_W{1'b0}};
                    else
                        write_index <= write_index + 1'b1;
                    tap_index <= {TAP_W{1'b0}};
                    accumulator <= {ACC_W{1'b0}};
                    busy <= 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire

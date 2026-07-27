`timescale 1ns / 1ps

`include "params.vh"

// ============================================================================
// 模块名称：fir_filter
//
// 主要功能：
//   实现一条 signed 实数 FIR 滤波链路。输入采样 sample_data 与 32 bit Q1.31
//   系数相乘后，采用转置型 FIR 结构逐级累加，并输出 DATA_W 位 signed 结果。
//   在当前顶层中，输入来自 adc_decimator_100，因此 FIR 以 300 kHz 等效采样率
//   工作；mode_router 会保持最近一次 FIR 输出，让 DA 仍以 30 MHz 节奏输出。
//
// 使用方法：
//   1. fir_coef_loader 先通过 coef_clear 清空旧系数和内部状态。
//   2. fir_coef_loader 对每个 tap 拉高 coef_we 1 个 clk 周期，同时给出
//      coef_addr 和 coef_wdata。
//   3. 当上游 sample_valid 为高时，本模块接收一个输入采样，并在同一输出
//      寄存器更新周期拉高 out_valid。
//   4. 下游只在 out_valid 为高时采样 out_data。
//
// 连接说明：
//   sample_valid/sample_data <- 当前顶层连接 adc_decimator_100 的 300 kHz 输出。
//   coef_*                  <- fir_coef_loader 从系数 BRAM 装载后的写系数接口。
//   out_valid/out_data      -> mode_router，在 FIR_SIM 模式下驱动 DA1。
//
// 时钟与复位：
//   所有端口除 rst_n 外均同步到 clk。rst_n 为异步低有效复位，复位后系数、
//   转置状态寄存器、out_valid 和 out_data 均清零。
//
// 输入格式：
//   sample_data 为 signed DATA_W 位二进制补码。
//   coef_wdata 为 signed 32 bit Q1.31 系数，实数值 = coef_wdata / 2^31。
//
// 输出格式：
//   out_data 为 signed DATA_W 位二进制补码。内部累加值右移 31 位还原到采样
//   数据尺度，然后对 DATA_W 范围做饱和。
//
// 握手时序：
//   sample_valid 为高的 clk 边沿接收一个新采样；out_valid 与对应 out_data 同步
//   更新并保持 1 个 clk 周期。coef_we 为单周期写脉冲。
//
// 参数说明：
//   DATA_W    为输入/输出采样位宽。
//   TAP_COUNT 为 FIR 抽头数，必须与 PS 发布到系数 BRAM 的 TAP_COUNT 一致。
//   ACC_W     为内部累加器位宽，需要覆盖 DATA_W + 32 bit 乘积和 TAP 累加增长。
//
// 错误行为：
//   coef_addr >= TAP_COUNT 的写入会被忽略。本模块不单独输出 error；系数协议
//   错误由 fir_coef_loader 报告。
//
// 使用限制：
//   装载新系数或 coef_clear 期间，输出不代表稳定滤波结果。系统应通过
//   fir_coef_ready/run_active 等外部控制，避免 PS 正在更新系数时使用输出。
// ============================================================================
module fir_filter #(
    parameter integer DATA_W    = `BOARD_DATA_W, // 输入/输出采样位宽，单位 bit。
    parameter integer TAP_COUNT = 129,           // FIR 抽头数量，需与 PS 发布 TAP_COUNT 一致。
    parameter integer ACC_W     = 56             // 内部累加器位宽，防止乘加溢出。
) (
    // 模块工作时钟，当前连接 30 MHz 采样时钟。
    input  wire                         clk,
    // 异步低有效复位，清零系数、状态寄存器和输出。
    input  wire                         rst_n,
    // 输入采样有效信号；为高时 sample_data 被 FIR 接收。
    input  wire                         sample_valid,
    // 输入 signed 采样数据，二进制补码。
    input  wire signed [DATA_W-1:0]     sample_data,

    // 系数写使能，单周期脉冲；来自 fir_coef_loader。
    input  wire                         coef_we,
    // 系数写地址，表示 tap 下标，合法范围 0..TAP_COUNT-1。
    input  wire [7:0]                   coef_addr,
    // 系数写数据，signed 32 bit Q1.31。
    input  wire signed [31:0]           coef_wdata,
    // 系数/状态清零脉冲；装载新系数前由 fir_coef_loader 拉高。
    input  wire                         coef_clear,

    // 输出有效信号；为高时 out_data 是新的 FIR 输出采样。
    output reg                          out_valid,
    // FIR 输出 signed 采样，二进制补码，已饱和到 DATA_W 位。
    output reg signed [DATA_W-1:0]      out_data
);
    reg signed [31:0] coeff [0:TAP_COUNT-1];
    reg signed [ACC_W-1:0] state [0:TAP_COUNT-2];

    integer i;
    reg signed [DATA_W+31:0] product [0:TAP_COUNT-1];
    reg signed [ACC_W-1:0] rounded;

    function signed [ACC_W-1:0] extend_product;
        input signed [DATA_W+31:0] value;
        begin
            extend_product = {{(ACC_W-(DATA_W+32)){value[DATA_W+31]}}, value};
        end
    endfunction

    function signed [DATA_W-1:0] sat_dac;
        input signed [ACC_W-1:0] acc;
        reg signed [ACC_W-1:0] scaled;
        begin
            scaled = acc >>> 31;
            if (scaled > ((1 << (DATA_W-1)) - 1))
                sat_dac = (1 << (DATA_W-1)) - 1;
            else if (scaled < -(1 << (DATA_W-1)))
                sat_dac = -(1 << (DATA_W-1));
            else
                sat_dac = scaled[DATA_W-1:0];
        end
    endfunction

    // 当前输入采样与每个 tap 系数组合相乘，时序累加在下方 always 块中完成。
    always @(*) begin
        for (i = 0; i < TAP_COUNT; i = i + 1)
            product[i] = sample_data * coeff[i];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_data  <= {DATA_W{1'b0}};
            for (i = 0; i < TAP_COUNT; i = i + 1)
                coeff[i] <= 32'sd0;
            for (i = 0; i < TAP_COUNT-1; i = i + 1)
                state[i] <= {ACC_W{1'b0}};
        end else begin
            out_valid <= sample_valid;

            if (coef_clear) begin
                for (i = 0; i < TAP_COUNT; i = i + 1)
                    coeff[i] <= 32'sd0;
                for (i = 0; i < TAP_COUNT-1; i = i + 1)
                    state[i] <= {ACC_W{1'b0}};
            end else if (coef_we && (coef_addr < TAP_COUNT)) begin
                coeff[coef_addr] <= coef_wdata;
            end

            if (sample_valid) begin
                // 转置型实数 FIR：每个 tap 对应一个乘法/加法状态级。
                // 只在 sample_valid 为高时推进状态，因此可用 clock enable 降低等效采样率。
                rounded = extend_product(product[0]) + state[0] + ({{(ACC_W-1){1'b0}},1'b1} << 30);
                out_data <= sat_dac(rounded);
                for (i = 0; i < TAP_COUNT-2; i = i + 1)
                    state[i] <= extend_product(product[i+1]) + state[i+1];
                state[TAP_COUNT-2] <= extend_product(product[TAP_COUNT-1]);
            end
        end
    end
endmodule

`timescale 1ns / 1ps

`include "params.vh"

/*
 * 模块：adc_decimator_100
 *
 * 主要功能：
 *   将 AD1 的 30 MHz 采样流按 100 倍降采样到 300 kHz，再送入 FIR 仿真链路。
 *   当前实现使用 100 点滑块平均作为简单抗混叠预处理，每收满 100 个输入采样
 *   输出 1 个平均后的 signed 采样。
 *
 * 连接说明：
 *   sample_valid/sample_data 连接 AD1 原始采样流。
 *   decim_valid/decim_data 连接 fir_filter 的 sample_valid/sample_data。
 *
 * 时钟与复位：
 *   所有信号除 rst_n 外均同步到 clk。rst_n 为异步低有效复位。
 *
 * 输入输出规范：
 *   sample_data 和 decim_data 均为 signed 二进制补码，位宽 DATA_W。
 *   decim_valid 为单周期脉冲，表示 decim_data 是新的 300 kHz 等效采样。
 *
 * 使用限制：
 *   DECIM_FACTOR 当前按 100 使用；若改为其他值，COUNT_W 和除法近似系数也要
 *   重新检查。该模块不产生新时钟，只用 clock enable 形式降低数据速率。
 */
module adc_decimator_100 #(
    parameter integer DATA_W       = `BOARD_DATA_W,
    parameter integer DECIM_FACTOR = 100,
    parameter integer ACC_W        = 24
) (
    // 模块工作时钟，当前连接 30 MHz 采样时钟。
    input  wire                     clk,
    // 异步低有效复位，清零计数器、累加器和输出 valid。
    input  wire                     rst_n,
    // 输入采样有效信号，通常为 30 MHz 采样流的 adc_valid。
    input  wire                     sample_valid,
    // 输入 signed 采样数据，二进制补码。
    input  wire signed [DATA_W-1:0] sample_data,

    // 降采样输出有效信号，每 DECIM_FACTOR 个输入采样输出 1 个周期。
    output reg                      decim_valid,
    // 降采样后的 signed 采样数据，二进制补码。
    output reg signed [DATA_W-1:0]  decim_data
);
    localparam integer COUNT_W = 7;

    reg [COUNT_W-1:0] count;
    reg signed [ACC_W-1:0] acc;

    wire signed [ACC_W-1:0] sample_ext =
        {{(ACC_W-DATA_W){sample_data[DATA_W-1]}}, sample_data};
    wire signed [ACC_W-1:0] acc_next = acc + sample_ext;
    wire signed [ACC_W+11:0] avg_scaled = acc_next * 12'sd1311;
    wire signed [ACC_W-1:0] avg_approx = avg_scaled >>> 17;

    function signed [DATA_W-1:0] sat_sample;
        input signed [ACC_W-1:0] value;
        begin
            if (value > ((1 << (DATA_W-1)) - 1))
                sat_sample = (1 << (DATA_W-1)) - 1;
            else if (value < -(1 << (DATA_W-1)))
                sat_sample = -(1 << (DATA_W-1));
            else
                sat_sample = value[DATA_W-1:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count       <= {COUNT_W{1'b0}};
            acc         <= {ACC_W{1'b0}};
            decim_valid <= 1'b0;
            decim_data  <= {DATA_W{1'b0}};
        end else begin
            decim_valid <= 1'b0;

            if (sample_valid) begin
                if (count == DECIM_FACTOR-1) begin
                    // 用 *1311/2^17 近似 /100，避免综合出除法器。
                    decim_data  <= sat_sample(avg_approx);
                    decim_valid <= 1'b1;
                    count       <= {COUNT_W{1'b0}};
                    acc         <= {ACC_W{1'b0}};
                end else begin
                    count <= count + 1'b1;
                    acc   <= acc_next;
                end
            end
        end
    end
endmodule

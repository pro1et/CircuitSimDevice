`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：adc_capture_check_top
//
// 主要功能：
//   仅用于综合和静态检查，将 clock_tree 与 adc_capture 按实际时钟关系连接。
//   本模块不是最终工程顶层，不包含管脚分配或板级业务逻辑。
//
// 使用方法：
//   由 fpga/scripts/synth_adc_capture.tcl 自动读取和综合，无需手工实例化。
//
// 连接说明：
//   clk_50m、rst_n 对应板级时钟和复位；ADC 物理接口直接透传到 adc_capture。
//
// 时钟与复位：
//   clock_tree 生成 30 MHz 捕获时钟及相对其延后 45° 的 ADC 驱动时钟。
//
// 输入格式：两路 10 位无符号直二进制 ADC 数据。
//
// 输出格式：两路 10 位采集结果、有效信号及 ADC 物理控制输出。
//
// 握手时序：与 adc_capture 相同，无反压、每周期一组双通道样本。
//
// 参数说明：无。
//
// 错误行为：由被实例化模块定义。
//
// 使用限制：仅用于验证，不应加入最终工程 sources_1。
// ============================================================================

module adc_capture_check_top (
    input  wire  logic       clk_50m,     // 板级 50 MHz 输入时钟
    input  wire  logic       rst_n,       // 板级低有效异步复位
    input  wire  logic [9:0] adc_data_a,  // 通道 1 ADC 并行数据
    input  wire  logic [9:0] adc_data_b,  // 通道 2 ADC 并行数据
    output wire  logic       adc_clk_a,   // 通道 1 ADC 物理时钟
    output wire  logic       adc_clk_b,   // 通道 2 ADC 物理时钟
    output wire  logic       adc_oe_a,    // 通道 1 ADC 输出控制，高电平为高阻
    output wire  logic       adc_oe_b,    // 通道 2 ADC 输出控制，高电平为高阻
    output       logic [9:0] data_a,      // 通道 1 已采集数据
    output       logic [9:0] data_b,      // 通道 2 已采集数据
    output       logic       out_valid    // 双通道采集数据有效
);

    logic clk_100m_unused;
    logic clk_capture;
    logic clk_drive;
    logic rst_100m_unused;
    logic rst_capture;
    logic locked_unused;

    clock_tree u_clock_tree (
        .clk_50m    (clk_50m),
        .rst_n      (rst_n),
        .clk_100m   (clk_100m_unused),
        .clk_30m    (clk_capture),
        .clk_30m_adc(clk_drive),
        .rst_100m   (rst_100m_unused),
        .rst_30m    (rst_capture),
        .locked     (locked_unused)
    );

    adc_capture u_adc_capture (
        .clk       (clk_capture),
        .clk_drive (clk_drive),
        .rst       (rst_capture),
        .adc_data_a(adc_data_a),
        .adc_data_b(adc_data_b),
        .adc_clk_a (adc_clk_a),
        .adc_clk_b (adc_clk_b),
        .adc_oe_a  (adc_oe_a),
        .adc_oe_b  (adc_oe_b),
        .data_a    (data_a),
        .data_b    (data_b),
        .out_valid (out_valid)
    );

endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：dac_output_check_top
//
// 主要功能：
//   仅用于综合和静态检查，将 clock_tree 与 dac_output 按实际 30 MHz 时钟关系连接。
//   本模块不是最终工程顶层，不包含管脚分配或其他板级业务逻辑。
//
// 使用方法：由 fpga/scripts/synth_dac_output.tcl 自动读取和综合。
//
// 连接说明：clk_50m、rst_n 对应板级源；内部计数器模拟同步上游数据流。
//
// 时钟与复位：clock_tree 生成 30 MHz DA 接口时钟及同步释放复位。
//
// 输入/输出格式：两路 10 位无符号直二进制 DA 码。
//
// 握手时序：与 dac_output 相同，每周期最多接收一组双通道样本。
//
// 参数说明：无。
//
// 错误行为：由被实例化模块定义。
//
// 使用限制：仅用于验证，不应加入最终工程 sources_1。
// ============================================================================

module dac_output_check_top (
    input  wire  logic       clk_50m,     // 板级 50 MHz 输入时钟
    input  wire  logic       rst_n,       // 板级低有效异步复位
    output       logic [9:0] dac_data_a,  // 通道 1 DA 并行数据
    output       logic [9:0] dac_data_b,  // 通道 2 DA 并行数据
    output wire  logic       dac_clk_a,   // 通道 1 DA 物理时钟
    output wire  logic       dac_clk_b    // 通道 2 DA 物理时钟
);

    logic clk_100m_unused;
    logic clk_dac;
    logic clk_30m_adc_unused;
    logic rst_100m_unused;
    logic rst_dac;
    logic locked_unused;
    logic [9:0] source_data_a;
    logic [9:0] source_data_b;
    logic in_ready_unused;

    clock_tree u_clock_tree (
        .clk_50m    (clk_50m),
        .rst_n      (rst_n),
        .clk_100m   (clk_100m_unused),
        .clk_30m    (clk_dac),
        .clk_30m_adc(clk_30m_adc_unused),
        .rst_100m   (rst_100m_unused),
        .rst_30m    (rst_dac),
        .locked     (locked_unused)
    );

    // 同步上游模型为静态时序检查建立真实的寄存器到寄存器数据路径。
    always_ff @(posedge clk_dac) begin
        if (rst_dac) begin
            source_data_a <= 10'd0;
            source_data_b <= 10'd1023;
        end else begin
            source_data_a <= source_data_a + 10'd1;
            source_data_b <= source_data_b - 10'd3;
        end
    end

    dac_output u_dac_output (
        .clk       (clk_dac),
        .rst       (rst_dac),
        .data_a    (source_data_a),
        .data_b    (source_data_b),
        .in_valid  (1'b1),
        .in_ready  (in_ready_unused),
        .dac_data_a(dac_data_a),
        .dac_data_b(dac_data_b),
        .dac_clk_a (dac_clk_a),
        .dac_clk_b (dac_clk_b)
    );

endmodule

`default_nettype wire

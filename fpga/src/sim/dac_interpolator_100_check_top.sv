`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：dac_interpolator_100_check_top
//
// 主要功能：为独立综合、时序和CDC检查提供带寄存输入输出的30 MHz检查顶层。
//
// 使用方法：由synth_dac_interpolator_100.tcl读取，不加入最终工程顶层。
//
// 连接说明：内部计数器模拟同域上游，输出端口用于建立完整时序路径。
//
// 时钟与复位：clk为30 MHz；rst为高有效同步复位。
//
// 输入格式：signed 10位补码及单拍valid。
//
// 输出格式：signed 10位补码、valid、ready和overflow。
//
// 握手时序：与被测模块一致。
//
// 参数说明：无。
//
// 错误行为：由被测模块定义。
//
// 使用限制：仅用于静态验证。
// ============================================================================

module dac_interpolator_100_check_top (
    input  wire logic                     clk,       // 30 MHz检查时钟
    input  wire logic                     rst_n,     // 低有效异步复位源
    output wire logic                     in_ready,  // 输入就绪
    output      logic signed [9:0]        data_out,  // signed输出样本
    output      logic                     out_valid, // 输出有效
    output      logic                     overflow   // 过早输入错误
);

    logic signed [9:0] source_data;
    logic [6:0] source_count;
    logic source_valid;
    logic rst;
    (* ASYNC_REG = "TRUE" *) logic [1:0] rst_sync;

    // 检查顶层模拟clock_tree的异步置位、同步释放域复位。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rst_sync <= 2'b11;
        else
            rst_sync <= {rst_sync[0], 1'b0};
    end
    assign rst = rst_sync[1];

    // 每100拍产生一个寄存输入，验证与任务D实际FIR输出相同的同域路径。
    always_ff @(posedge clk) begin
        if (rst) begin
            source_data  <= 10'sd0;
            source_count <= 7'd0;
            source_valid <= 1'b0;
        end else begin
            source_valid <= 1'b0;
            if (source_count == 7'd99) begin
                source_count <= 7'd0;
                source_data  <= source_data + 10'sd1;
                source_valid <= 1'b1;
            end else begin
                source_count <= source_count + 1'b1;
            end
        end
    end

    dac_interpolator_100 u_dut (
        .clk      (clk),
        .rst      (rst),
        .data_in  (source_data),
        .in_valid (source_valid),
        .in_ready (in_ready),
        .data_out (data_out),
        .out_valid(out_valid),
        .overflow (overflow)
    );

endmodule

`default_nettype wire

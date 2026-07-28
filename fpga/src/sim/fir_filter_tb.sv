`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：fir_filter_tb
//
// 主要功能：
//   自检分时MAC FIR的系数装载、卷积结果、固定延迟、正负数运算、valid脉冲和
//   运行中复位。测试使用7抽头、2路MAC以缩短仿真，接口和运算格式与任务D一致。
//
// 使用方法：
//   从仓库work目录运行fpga/scripts/sim_fir_filter.tcl。
//
// 时钟与复位：
//   clk周期10 ns；rst_n为异步低有效复位。
//
// 输入/输出格式：
//   样本为10位signed补码，系数为Q1.31。参考滤波器为[0.25,0.5,0.25,0,0,0,0]。
//
// 检查方法：
//   依次输入正、负脉冲并比较精确卷积结果；每个输入必须在4个计算周期后产生
//   单拍out_valid。任一断言失败调用$fatal，全部通过后置位test_passed。
// ============================================================================
module fir_filter_tb;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int TAP_COUNT = 7;
    localparam int MAC_LANES = 2;
    localparam int LATENCY = (TAP_COUNT + MAC_LANES - 1) / MAC_LANES;

    logic clk;
    logic rst_n;
    logic sample_valid;
    logic signed [9:0] sample_data;
    logic coef_we;
    logic [7:0] coef_addr;
    logic signed [31:0] coef_wdata;
    logic coef_clear;
    logic out_valid;
    logic signed [9:0] out_data;
    logic test_passed;

    int unsigned output_count;
    logic waiting_output;
    time accepted_time;
    logic signed [9:0] expected [0:7];

    fir_filter #(
        .DATA_W   (10),
        .TAP_COUNT(TAP_COUNT),
        .ACC_W    (48),
        .MAC_LANES(MAC_LANES)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_valid(sample_valid),
        .sample_data (sample_data),
        .coef_we     (coef_we),
        .coef_addr   (coef_addr),
        .coef_wdata  (coef_wdata),
        .coef_clear  (coef_clear),
        .out_valid   (out_valid),
        .out_data    (out_data)
    );

    always #5ns clk = ~clk;

    task automatic write_coefficient(input int unsigned address,
                                     input logic signed [31:0] value);
        begin
            @(negedge clk);
            coef_addr  = address[7:0];
            coef_wdata = value;
            coef_we    = 1'b1;
            @(negedge clk);
            coef_we    = 1'b0;
        end
    endtask

    task automatic send_sample(input logic signed [9:0] value);
        begin
            @(negedge clk);
            sample_data  = value;
            sample_valid = 1'b1;
            @(posedge clk);
            #1ps;
            waiting_output = 1'b1;
            accepted_time = $time;
            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            output_count <= 0;
        end else begin
            #1ps;
            if (out_valid) begin
                assert (waiting_output)
                    else $fatal(1, "出现无对应输入的out_valid，时间=%0t", $time);
                assert (($time - accepted_time) == LATENCY * 10ns)
                    else $fatal(1, "FIR延迟错误：实际=%0t，期望=%0t",
                                $time - accepted_time, LATENCY * 10ns);
                assert (out_data === expected[output_count])
                    else $fatal(1, "FIR输出错误：序号=%0d，实际=%0d，期望=%0d",
                                output_count, out_data, expected[output_count]);
                output_count <= output_count + 1;
                waiting_output = 1'b0;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_valid = 1'b0;
        sample_data = 10'sd0;
        coef_we = 1'b0;
        coef_addr = 8'd0;
        coef_wdata = 32'sd0;
        coef_clear = 1'b0;
        test_passed = 1'b0;
        output_count = 0;
        waiting_output = 1'b0;
        accepted_time = 0ns;

        expected[0] = 10'sd100;
        expected[1] = 10'sd200;
        expected[2] = 10'sd100;
        expected[3] = 10'sd0;
        expected[4] = -10'sd100;
        expected[5] = -10'sd200;
        expected[6] = -10'sd100;
        expected[7] = 10'sd0;

        #30ns rst_n = 1'b1;
        write_coefficient(0, 32'sh2000_0000);
        write_coefficient(1, 32'sh4000_0000);
        write_coefficient(2, 32'sh2000_0000);
        write_coefficient(3, 32'sd0);
        write_coefficient(4, 32'sd0);
        write_coefficient(5, 32'sd0);
        write_coefficient(6, 32'sd0);

        send_sample(10'sd400);
        wait (!waiting_output);
        send_sample(10'sd0);
        wait (!waiting_output);
        send_sample(10'sd0);
        wait (!waiting_output);
        send_sample(10'sd0);
        wait (!waiting_output);
        send_sample(-10'sd400);
        wait (!waiting_output);
        send_sample(10'sd0);
        wait (!waiting_output);
        send_sample(10'sd0);
        wait (!waiting_output);
        send_sample(10'sd0);
        wait (!waiting_output);
        #1ns; // 等待output_count的非阻塞赋值提交后再检查总数。

        assert (output_count == 8)
            else $fatal(1, "FIR输出数量错误：实际=%0d，期望=8", output_count);

        // 运行中复位必须终止尚未完成的计算，并清零valid和输出。
        send_sample(10'sd300);
        @(negedge clk);
        rst_n = 1'b0;
        #1ns;
        assert (!out_valid && out_data == 10'sd0)
            else $fatal(1, "运行中复位未清零FIR输出");
        waiting_output = 1'b0;
        repeat (2) @(posedge clk);

        test_passed = 1'b1;
        $display("TEST PASSED: 分时MAC FIR卷积、延迟、valid和复位检查通过");
        $finish;
    end
endmodule

`default_nettype wire

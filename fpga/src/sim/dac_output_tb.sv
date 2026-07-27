`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：dac_output_tb
//
// 主要功能：
//   自检双通道 DA 接口的复位码、valid/ready 握手、下降沿数据更新、保持行为、
//   双通道独立性、边界码和 ODDR 时钟转发。
//
// 使用方法：
//   通过 fpga/scripts/sim_dac_output.tcl 在 Vivado batch 模式中运行。
//
// 连接说明：本 testbench 直接驱动 dac_output，不连接板级管脚。
//
// 时钟与复位：clk 周期约 33.333 ns；rst 为高有效同步业务复位。
//
// 输入/输出格式：两路均为 10 位无符号直二进制码。
//
// 握手时序：在上升沿检查接收，在后续下降沿检查物理输出更新。
//
// 参数说明：使用默认 RESET_CODE=512。
//
// 错误行为：任一断言失败时调用 $fatal；全部通过后置位 test_passed。
//
// 使用限制：需要 Vivado UNISIM 仿真库支持 ODDR。
// ============================================================================

module dac_output_tb;

    timeunit 1ns;
    timeprecision 1ps;

    localparam logic [9:0] RESET_CODE = 10'd512;

    logic       clk;
    logic       rst;
    logic [9:0] data_a;
    logic [9:0] data_b;
    logic       in_valid;
    logic       in_ready;
    logic [9:0] dac_data_a;
    logic [9:0] dac_data_b;
    logic       dac_clk_a;
    logic       dac_clk_b;
    logic       test_passed;

    logic [9:0] expected_pending_a;
    logic [9:0] expected_pending_b;
    logic [9:0] previous_dac_a;
    logic [9:0] previous_dac_b;
    logic       monitor_active;
    int unsigned accepted_samples;

    dac_output #(
        .RESET_CODE(RESET_CODE)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .data_a    (data_a),
        .data_b    (data_b),
        .in_valid  (in_valid),
        .in_ready  (in_ready),
        .dac_data_a(dac_data_a),
        .dac_data_b(dac_data_b),
        .dac_clk_a (dac_clk_a),
        .dac_clk_b (dac_clk_b)
    );

    initial begin
        clk = 1'b0;
        forever #16.6665ns clk = ~clk;
    end

    // 在上升沿建立期望暂存值；延迟一个仿真精度后检查时钟转发和 ready。
    always @(posedge clk) begin
        if (rst) begin
            expected_pending_a = RESET_CODE;
            expected_pending_b = RESET_CODE;
        end else if (in_valid && in_ready) begin
            expected_pending_a = data_a;
            expected_pending_b = data_b;
            accepted_samples   = accepted_samples + 1;
        end

        #1ns;
        assert (dac_clk_a == !rst && dac_clk_b == !rst)
            else $fatal(1, "DA 转发时钟上升沿错误，时间 %0t", $time);
        assert (in_ready == !rst)
            else $fatal(1, "in_ready 错误，时间 %0t", $time);
        if (monitor_active) begin
            assert (dac_data_a == previous_dac_a && dac_data_b == previous_dac_b)
                else $fatal(1, "DA 数据在上升沿发生变化，时间 %0t", $time);
        end
    end

    // 物理数据应只在下降沿更新，并等于最近一次已接收的双通道样本。
    always @(negedge clk) begin
        // clk 在仿真 0 时刻由 X 初始化为 0 会形成伪下降沿，必须跳过。
        if ($time > 1ns) begin
            #1ns;
            assert (!dac_clk_a && !dac_clk_b)
                else $fatal(1, "DA 转发时钟下降沿错误，时间 %0t", $time);

            if (rst) begin
                assert (dac_data_a == RESET_CODE && dac_data_b == RESET_CODE)
                    else $fatal(1, "复位码错误，时间 %0t", $time);
            end else begin
                assert (dac_data_a == expected_pending_a)
                    else $fatal(1, "通道 1 输出错误，时间 %0t，实际 %0d，期望 %0d",
                                $time, dac_data_a, expected_pending_a);
                assert (dac_data_b == expected_pending_b)
                    else $fatal(1, "通道 2 输出错误，时间 %0t，实际 %0d，期望 %0d",
                                $time, dac_data_b, expected_pending_b);
            end

            previous_dac_a = dac_data_a;
            previous_dac_b = dac_data_b;
            monitor_active  = 1'b1;
        end
    end

    task automatic submit_sample(input logic [9:0] sample_a,
                                 input logic [9:0] sample_b);
        @(negedge clk);
        #1ns;
        data_a   = sample_a;
        data_b   = sample_b;
        in_valid = 1'b1;
        @(posedge clk);
        #1ns;
        in_valid = 1'b0;
    endtask

    initial begin
        test_passed       = 1'b0;
        rst               = 1'b1;
        data_a            = 10'd0;
        data_b            = 10'd0;
        in_valid          = 1'b0;
        expected_pending_a = RESET_CODE;
        expected_pending_b = RESET_CODE;
        previous_dac_a    = RESET_CODE;
        previous_dac_b    = RESET_CODE;
        monitor_active     = 1'b0;
        accepted_samples  = 0;

        repeat (3) @(negedge clk);
        #2ns rst = 1'b0;

        // 最小码、最大码、中间码和双通道不同码。
        submit_sample(10'd0,    10'd1023);
        submit_sample(10'd1023, 10'd0);
        submit_sample(10'd512,  10'd257);

        // 制造空拍并改变无效输入，输出必须保持最后一次有效样本。
        @(negedge clk);
        #1ns;
        data_a = 10'd99;
        data_b = 10'd100;
        repeat (3) @(posedge clk);

        // 连续每周期提交，验证满吞吐率。
        submit_sample(10'h155, 10'h2AA);
        submit_sample(10'h3A5, 10'h05A);
        submit_sample(10'h001, 10'h3FE);

        repeat (2) @(negedge clk);

        // 运行中复位应立即停止外部时钟，并在下一下降沿恢复默认码。
        #3ns rst = 1'b1;
        #1ns;
        assert (!dac_clk_a && !dac_clk_b && !in_ready)
            else $fatal(1, "运行中复位未立即停止 DA 接口，时间 %0t", $time);
        repeat (2) @(negedge clk);
        #2ns rst = 1'b0;

        submit_sample(10'd17, 10'd1001);
        repeat (2) @(negedge clk);

        assert (accepted_samples == 7)
            else $fatal(1, "接收样本计数错误，实际 %0d，期望 7", accepted_samples);

        test_passed = 1'b1;
        $display("TEST PASSED");
    end

endmodule

`default_nettype wire

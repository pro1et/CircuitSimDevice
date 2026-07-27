`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：adc_capture_tb
//
// 主要功能：
//   自检双通道 ADC 时钟转发、OE、连续采集、启动屏蔽和运行中复位行为。
//
// 使用方法：
//   通过 fpga/scripts/sim_adc_capture.tcl 在 Vivado batch 模式下运行。
//
// 连接说明：
//   本 testbench 使用 25 ns 输出延迟模型模拟两颗 3PA1030，无外部连接。
//
// 时钟与复位：
//   clk 和 clk_drive 周期约 33.333 ns，clk_drive 相对 clk 延后 45°；rst 为
//   高有效同步复位。
//
// 输入格式：两路 ADC 模型产生 10 位无符号递增码。
//
// 输出格式：通过断言比较被测模块输出和时钟沿处的期望输入值。
//
// 握手时序：out_valid 为高后每周期检查一组双通道数据。
//
// 参数说明：使用默认 6 周期启动屏蔽。
//
// 错误行为：任一断言失败时调用 $fatal，并由 Tcl 脚本返回失败状态。
//
// 使用限制：需要 Vivado UNISIM 仿真库支持 ODDR。
// ============================================================================

module adc_capture_tb;

    timeunit 1ns;
    timeprecision 1ps;

    localparam int unsigned STARTUP_CYCLES = 6;

    logic       clk;
    logic       clk_drive;
    logic       rst;
    logic [9:0] adc_data_a;
    logic [9:0] adc_data_b;
    logic       adc_clk_a;
    logic       adc_clk_b;
    logic       adc_oe_a;
    logic       adc_oe_b;
    logic [9:0] data_a;
    logic [9:0] data_b;
    logic       out_valid;
    logic       test_passed;

    logic [9:0] source_a;
    logic [9:0] source_b;
    logic [9:0] expected_a;
    logic [9:0] expected_b;
    int unsigned active_edges;
    int unsigned valid_samples;

    adc_capture #(
        .STARTUP_CYCLES(STARTUP_CYCLES)
    ) dut (
        .clk       (clk),
        .clk_drive (clk_drive),
        .rst       (rst),
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

    initial begin
        clk = 1'b0;
        forever #16.6665ns clk = ~clk;
    end

    // 驱动时钟相对捕获时钟延后 45°，30 MHz 下约为 4.167 ns。
    initial begin
        clk_drive = 1'b0;
        #4.166625ns;
        forever #16.6665ns clk_drive = ~clk_drive;
    end

    // 3PA1030 模型：每个外部时钟上升沿后最多 25 ns 更新并行输出。
    always @(posedge adc_clk_a) begin
        source_a <= source_a + 10'd1;
        adc_data_a <= #25ns source_a;
    end

    always @(posedge adc_clk_b) begin
        source_b <= source_b - 10'd3;
        adc_data_b <= #25ns source_b;
    end

    // 在被测模块输入寄存前保存本周期期望值，避开非阻塞赋值竞争。
    always @(posedge clk) begin
        expected_a = adc_data_a;
        expected_b = adc_data_b;

        if (rst) begin
            active_edges = 0;
        end else begin
            active_edges = active_edges + 1;
        end

        #1ps;
        if (rst) begin
            assert (!out_valid && data_a == 10'd0 && data_b == 10'd0)
                else $fatal(1, "复位输出错误，时间=%0t", $time);
        end else begin
            assert (out_valid == (active_edges >= STARTUP_CYCLES))
                else $fatal(1, "out_valid 启动时序错误，时间=%0t，周期=%0d", $time, active_edges);

            if (out_valid) begin
                assert (data_a == expected_a)
                    else $fatal(1, "通道 1 数据错误，时间=%0t，实际=%0d，期望=%0d",
                                $time, data_a, expected_a);
                assert (data_b == expected_b)
                    else $fatal(1, "通道 2 数据错误，时间=%0t，实际=%0d，期望=%0d",
                                $time, data_b, expected_b);
                valid_samples = valid_samples + 1;
            end
        end
    end

    initial begin
        test_passed  = 1'b0;
        rst          = 1'b1;
        adc_data_a   = 10'd0;
        adc_data_b   = 10'd1023;
        source_a     = 10'd1;
        source_b     = 10'd1022;
        active_edges = 0;
        valid_samples = 0;

        #5ns;
        assert (adc_oe_a && adc_oe_b && !adc_clk_a && !adc_clk_b)
            else $fatal(1, "复位期间 ADC 控制输出错误，时间=%0t", $time);

        repeat (3) @(posedge clk);
        #2ns rst = 1'b0;

        wait (valid_samples >= 16);

        // 运行中异步停止外部时钟并关闭 ADC 输出，内部状态在下一 clk 上升沿复位。
        #7ns rst = 1'b1;
        #1ns;
        assert (adc_oe_a && adc_oe_b && !adc_clk_a && !adc_clk_b)
            else $fatal(1, "运行中复位未立即停止 ADC 接口，时间=%0t", $time);

        repeat (2) @(posedge clk);
        #2ns rst = 1'b0;
        wait (valid_samples >= 24);

        test_passed = 1'b1;
        $display("TEST PASSED");
        $finish;
    end

endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：top_adc_dac_loopback_tb
//
// 主要功能：
//   自检 AD-Digital-DA 顶层的双通道位序、默认极性补偿、连续吞吐、启动复位、
//   ADC/DAC 转发时钟及运行中复位行为。
//
// 使用方法：
//   从仓库 work 目录通过 sim_top_adc_dac_loopback.tcl 启动 Vivado 行为仿真。
//
// 连接说明：
//   testbench 产生 50 MHz 板级时钟，并用两组不同的 10 位序列模拟双通道 ADC。
//
// 时钟与复位：
//   clk_50m 周期为 20 ns；rst_n 模拟低有效 PL_KEY1。其余时钟由真实 clock_tree
//   产生，因此需要 UNISIM 的 MMCME2_BASE、BUFG 和 ODDR 仿真模型。
//
// 输入格式：两路 ADC 模型输出 10 位无符号直二进制码，并在 ADC 时钟后更新。
//
// 输出格式：检查 DAC 物理数据等于对应 ADC 已采样数据的 10 位反码。
//
// 握手时序：ADC 有效后每个 30 MHz 周期检查一对输出，无反压。
//
// 参数说明：测试将 ADC 启动屏蔽缩短为 3 周期，极性补偿保持默认开启。
//
// 错误行为：任一断言失败时调用 $fatal；全部检查完成后输出 TEST PASSED。
//
// 使用限制：该仿真验证数字连接和控制时序，不能替代实际模拟幅频、噪声或眼图测试。
// ============================================================================

module top_adc_dac_loopback_tb;

    timeunit 1ns;
    timeprecision 1ps;

    logic       clk_50m;
    logic       rst_n;
    logic [9:0] adc_data_a;
    logic [9:0] adc_data_b;
    logic       adc_clk_a;
    logic       adc_clk_b;
    logic       adc_oe_a;
    logic       adc_oe_b;
    logic [9:0] dac_data_a;
    logic [9:0] dac_data_b;
    logic       dac_clk_a;
    logic       dac_clk_b;
    logic       test_passed;

    logic [9:0] source_a;
    logic [9:0] source_b;
    logic [9:0] expected_dac_a;
    logic [9:0] expected_dac_b;
    logic       expected_valid;
    int unsigned checked_samples;
    int unsigned adc_clock_edges;
    int unsigned dac_clock_edges;

    top_adc_dac_loopback #(
        .ADC_STARTUP_CYCLES      (3),
        .COMPENSATE_DAC_INVERSION(1'b1)
    ) dut (
        .clk_50m   (clk_50m),
        .rst_n     (rst_n),
        .adc_data_a(adc_data_a),
        .adc_data_b(adc_data_b),
        .adc_clk_a (adc_clk_a),
        .adc_clk_b (adc_clk_b),
        .adc_oe_a  (adc_oe_a),
        .adc_oe_b  (adc_oe_b),
        .dac_data_a(dac_data_a),
        .dac_data_b(dac_data_b),
        .dac_clk_a (dac_clk_a),
        .dac_clk_b (dac_clk_b)
    );

    initial begin
        clk_50m = 1'b0;
        forever #10ns clk_50m = ~clk_50m;
    end

    // ADC 行为模型：用不同步长覆盖两路不同数据、进位和全部数据位。
    always @(posedge adc_clk_a) begin
        adc_clock_edges <= adc_clock_edges + 1;
        source_a <= source_a + 10'h12D;
        #25ns adc_data_a <= source_a;
    end

    always @(posedge adc_clk_b) begin
        source_b <= source_b - 10'h0B7;
        #25ns adc_data_b <= source_b;
    end

    always @(posedge dac_clk_a) begin
        dac_clock_edges <= dac_clock_edges + 1;
    end

    // dac_output 在采样时钟上升沿接收 ADC 上一拍寄存结果。
    always @(posedge dut.clk_sample) begin
        logic       accepted_valid;
        logic [9:0] accepted_a;
        logic [9:0] accepted_b;

        accepted_valid = dut.adc_valid;
        accepted_a     = dut.adc_sample_a;
        accepted_b     = dut.adc_sample_b;
        #1ps;
        if (dut.rst_sample) begin
            expected_dac_a <= 10'd512;
            expected_dac_b <= 10'd512;
            expected_valid <= 1'b0;
        end else if (accepted_valid) begin
            expected_dac_a <= ~accepted_a;
            expected_dac_b <= ~accepted_b;
            expected_valid <= 1'b1;
        end
    end

    // 物理数据在采样时钟下降沿更新；等待 NBA 后比较本拍期望值。
    always @(negedge dut.clk_sample) begin
        #1ps;
        if (!dut.rst_sample && expected_valid) begin
            assert (dac_data_a === expected_dac_a)
                else $fatal(1, "DA 通道 1 回环错误：实际=%03h，期望=%03h，时间=%0t",
                            dac_data_a, expected_dac_a, $time);
            assert (dac_data_b === expected_dac_b)
                else $fatal(1, "DA 通道 2 回环错误：实际=%03h，期望=%03h，时间=%0t",
                            dac_data_b, expected_dac_b, $time);
            checked_samples <= checked_samples + 1;
        end
    end

    initial begin
        test_passed     = 1'b0;
        rst_n           = 1'b0;
        adc_data_a      = 10'd0;
        adc_data_b      = 10'd1023;
        source_a        = 10'h001;
        source_b        = 10'h3FE;
        expected_dac_a  = 10'd512;
        expected_dac_b  = 10'd512;
        expected_valid  = 1'b0;
        checked_samples = 0;
        adc_clock_edges = 0;
        dac_clock_edges = 0;

        #200ns rst_n = 1'b1;

        fork
            begin
                #20us;
                $fatal(1, "等待 MMCM 首次锁定超时，时间=%0t", $time);
            end
            begin
                @(posedge dut.clock_locked_unused);
            end
        join_any
        disable fork;

        wait (!dut.rst_sample);
        #1ns;
        assert (!adc_oe_a && !adc_oe_b)
            else $fatal(1, "解除复位后 ADC OE 未拉低，时间=%0t", $time);

        wait (checked_samples >= 24);
        assert (adc_clock_edges >= 24 && dac_clock_edges >= 24)
            else $fatal(1, "转发时钟边沿计数不足：ADC=%0d，DAC=%0d",
                        adc_clock_edges, dac_clock_edges);

        // 运行中复位必须立即停止接口时钟、关闭 ADC 总线，并恢复 DAC 中间码。
        #7ns rst_n = 1'b0;
        #2ns;
        assert (adc_oe_a && adc_oe_b)
            else $fatal(1, "运行中复位未关闭 ADC 数据输出，时间=%0t", $time);
        assert (!adc_clk_a && !adc_clk_b && !dac_clk_a && !dac_clk_b)
            else $fatal(1, "运行中复位未停止外部接口时钟，时间=%0t", $time);
        wait (dac_data_a == 10'd512 && dac_data_b == 10'd512);

        #200ns rst_n = 1'b1;
        fork
            begin
                #20us;
                $fatal(1, "等待 MMCM 再次锁定超时，时间=%0t", $time);
            end
            begin
                @(posedge dut.clock_locked_unused);
            end
        join_any
        disable fork;

        wait (!dut.rst_sample);
        wait (checked_samples >= 32);

        test_passed = 1'b1;
        $display("TEST PASSED: checked_samples=%0d", checked_samples);
        $finish;
    end

endmodule

`default_nettype wire

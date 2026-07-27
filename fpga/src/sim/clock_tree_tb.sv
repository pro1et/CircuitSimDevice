`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：clock_tree_tb
//
// 主要功能：
//   自检 clock_tree 的输出频率、锁定状态、复位释放及运行中复位行为。
//
// 使用方法：
//   通过 fpga/scripts/sim_clock_tree.tcl 在 Vivado batch 模式下运行。
//
// 连接说明：
//   本 testbench 直接产生 50 MHz 输入时钟并实例化被测模块，无外部接口。
//
// 时钟与复位：
//   输入时钟周期为 20 ns；rst_n 为低有效异步复位。
//
// 输入格式：无数据输入。
//
// 输出格式：无数据输出；所有结果通过断言自动判断。
//
// 握手时序：无。
//
// 参数说明：无。
//
// 错误行为：任一检查失败时调用 $fatal，使仿真返回失败。
//
// 使用限制：需要 Vivado UNISIM 仿真库支持 MMCME2_BASE 和 BUFG。
// ============================================================================

module clock_tree_tb;

    timeunit 1ns;
    timeprecision 1ps;

    logic clk_50m;
    logic rst_n;
    logic clk_100m;
    logic clk_30m;
    logic clk_30m_adc;
    logic rst_100m;
    logic rst_30m;
    logic locked;
    logic test_passed;

    time edge_time;
    time period_100m;
    time period_30m;
    realtime edge_realtime;
    realtime phase_30m_adc;

    clock_tree dut (
        .clk_50m (clk_50m),
        .rst_n   (rst_n),
        .clk_100m(clk_100m),
        .clk_30m (clk_30m),
        .clk_30m_adc(clk_30m_adc),
        .rst_100m(rst_100m),
        .rst_30m (rst_30m),
        .locked  (locked)
    );

    initial begin
        clk_50m = 1'b0;
        forever #10ns clk_50m = ~clk_50m;
    end

    initial begin
        test_passed = 1'b0;
        rst_n = 1'b0;
        #200ns;
        rst_n = 1'b1;

        fork
            begin
                #20us;
                $fatal(1, "等待 MMCM 首次锁定超时，时间=%0t", $time);
            end
            begin
                @(posedge locked);
            end
        join_any
        disable fork;

        wait (!rst_100m && !rst_30m);

        @(posedge clk_100m);
        edge_time = $time;
        @(posedge clk_100m);
        period_100m = $time - edge_time;
        assert (period_100m >= 9999ps && period_100m <= 10001ps)
            else $fatal(1, "100 MHz 时钟周期错误：实际=%0t，期望=10 ns", period_100m);

        // 30 MHz 的单周期为无限循环小数，跨 30 个周期测量可避免时间量化误差。
        @(posedge clk_30m);
        edge_time = $time;
        repeat (30) @(posedge clk_30m);
        period_30m = $time - edge_time;
        assert (period_30m >= 999999ps && period_30m <= 1000001ps)
            else $fatal(1, "30 MHz 的 30 周期总时长错误：实际=%0t，期望=1 us", period_30m);

        @(posedge clk_30m);
        edge_realtime = $realtime;
        @(posedge clk_30m_adc);
        phase_30m_adc = $realtime - edge_realtime;
        assert (phase_30m_adc >= 4.165ns && phase_30m_adc <= 4.168ns)
            else $fatal(1, "ADC 驱动时钟相位错误：实际延后=%0.3f ns，期望约=4.167 ns",
                        phase_30m_adc);

        // 运行过程中复位必须立即让 MMCM 失锁，并保持两个输出域处于复位。
        #17ns;
        rst_n = 1'b0;
        #1ns;
        assert (rst_100m && rst_30m)
            else $fatal(1, "运行中复位未异步置位，时间=%0t", $time);
        fork
            begin
                #1us;
                $fatal(1, "输入复位后 MMCM 未在超时前失锁，时间=%0t", $time);
            end
            begin
                @(negedge locked);
            end
        join_any
        disable fork;

        #200ns;
        rst_n = 1'b1;
        fork
            begin
                #20us;
                $fatal(1, "等待 MMCM 再次锁定超时，时间=%0t", $time);
            end
            begin
                @(posedge locked);
            end
        join_any
        disable fork;

        wait (!rst_100m && !rst_30m);
        assert (locked)
            else $fatal(1, "域复位释放时 MMCM 未锁定，时间=%0t", $time);

        test_passed = 1'b1;
        $display("TEST PASSED");
        $finish;
    end

endmodule

`default_nettype wire

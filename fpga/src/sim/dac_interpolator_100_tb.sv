`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：dac_interpolator_100_tb
//
// 主要功能：
//   自检100倍多相插值器的冲激卷积、输出计数、直流相位一致性、连续块交接、
//   过早输入错误和运行中复位。
//
// 使用方法：由fpga/scripts/sim_dac_interpolator_100.tcl自动运行。
//
// 连接说明：testbench直接驱动被测模块，不连接板级接口。
//
// 时钟与复位：clk为30 MHz等效时钟；rst为高有效同步复位。
//
// 输入格式：signed 10位补码，使用冲激、直流及符号边界样本。
//
// 输出格式：参考模型按Q2.16系数执行卷积、半LSB偏置舍入和10位饱和。
//
// 握手时序：输入只在in_ready高时提交；专门测试一次违反约束的过早脉冲。
//
// 参数说明：使用默认DATA_W=10、ACC_W=30。
//
// 错误行为：任何结果、valid、ready或overflow不符合预期即调用$fatal。
//
// 使用限制：参考模型调用DUT系数ROM，主要验证多相寻址、定点运算和控制时序；
//   系数频响由可复现生成脚本独立检查。
// ============================================================================

module dac_interpolator_100_tb;

    timeunit 1ns;
    timeprecision 1ps;

    localparam int DATA_W = 10;
    localparam int ACC_W = 30;

    logic clk;
    logic rst;
    logic signed [DATA_W-1:0] data_in;
    logic in_valid;
    logic in_ready;
    logic signed [DATA_W-1:0] data_out;
    logic out_valid;
    logic overflow;
    logic test_passed;

    logic signed [DATA_W-1:0] ref_history [0:3];
    integer output_count;
    integer index;

    dac_interpolator_100 #(
        .DATA_W(DATA_W),
        .ACC_W (ACC_W)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .data_in  (data_in),
        .in_valid (in_valid),
        .in_ready (in_ready),
        .data_out (data_out),
        .out_valid(out_valid),
        .overflow (overflow)
    );

    initial begin
        clk = 1'b0;
        forever #16.6665ns clk = ~clk;
    end

    function automatic integer expected_sample(input integer phase_number);
        longint signed sum;
        longint signed scaled;
        integer k;
        begin
            sum = 0;
            for (k = 0; k < 4; k = k + 1)
                sum = sum + $signed(ref_history[k]) *
                            $signed(dut.coefficient(phase_number + 100*k));
            scaled = (sum + 32768) >>> 16;
            if (scaled > 511)
                expected_sample = 511;
            else if (scaled < -512)
                expected_sample = -512;
            else
                expected_sample = scaled;
        end
    endfunction

    task automatic update_reference(input integer sample_value);
        begin
            ref_history[3] = ref_history[2];
            ref_history[2] = ref_history[1];
            ref_history[1] = ref_history[0];
            ref_history[0] = sample_value;
        end
    endtask

    task automatic submit_sample(input integer sample_value);
        begin
            @(negedge clk);
            assert (in_ready)
                else $fatal(1, "提交输入时in_ready为低，时间%0t", $time);
            data_in  = sample_value;
            in_valid = 1'b1;
            @(posedge clk);
            update_reference(sample_value);
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    task automatic check_block(input bit check_dc, input integer dc_value);
        integer phase_number;
        integer expected;
        begin
            for (phase_number = 0; phase_number < 100; phase_number = phase_number + 1) begin
                @(posedge clk);
                expected = expected_sample(phase_number);
                #1ns;
                assert (out_valid)
                    else $fatal(1, "phase=%0d时out_valid缺失，时间%0t", phase_number, $time);
                assert ($signed(data_out) == expected)
                    else $fatal(1, "phase=%0d输出错误，实际%0d，期望%0d",
                                phase_number, $signed(data_out), expected);
                if (check_dc) begin
                    assert (($signed(data_out) >= dc_value-1) &&
                            ($signed(data_out) <= dc_value+1))
                        else $fatal(1, "直流稳态相位纹波过大，phase=%0d，输出%0d",
                                    phase_number, $signed(data_out));
                end
                output_count = output_count + 1;
            end
        end
    endtask

    task automatic apply_reset;
        begin
            @(negedge clk);
            rst = 1'b1;
            in_valid = 1'b0;
            repeat (2) @(posedge clk);
            #1ns;
            assert (!out_valid && !overflow && in_ready && data_out == 0)
                else $fatal(1, "复位状态错误，时间%0t", $time);
            @(negedge clk);
            rst = 1'b0;
            for (index = 0; index < 4; index = index + 1)
                ref_history[index] = 0;
        end
    endtask

    initial begin
        rst          = 1'b1;
        data_in      = '0;
        in_valid     = 1'b0;
        test_passed  = 1'b0;
        output_count = 0;
        for (index = 0; index < 4; index = index + 1)
            ref_history[index] = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // 冲激后补三个零，逐相检查完整400抽头卷积响应和符号边界输入。
        submit_sample(511);
        check_block(1'b0, 0);
        submit_sample(0);
        check_block(1'b0, 0);
        submit_sample(0);
        check_block(1'b0, 0);
        submit_sample(0);
        check_block(1'b0, 0);

        // 四个相同样本填满历史后，第五块应保持200且相位纹波不超过1 LSB。
        apply_reset();
        repeat (4) begin
            submit_sample(200);
            check_block(1'b0, 0);
        end
        submit_sample(200);
        check_block(1'b1, 200);

        // 过早的单拍输入必须被拒绝并置位粘滞overflow。
        apply_reset();
        submit_sample(-512);
        repeat (5) @(posedge clk);
        @(negedge clk);
        assert (!in_ready)
            else $fatal(1, "活动中间相位错误拉高in_ready");
        data_in  = 10'sd123;
        in_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        in_valid = 1'b0;
        #1ns;
        assert (overflow)
            else $fatal(1, "过早输入未置位overflow");

        // 运行中复位必须终止剩余输出并清除错误。
        rst = 1'b1;
        @(posedge clk);
        #1ns;
        assert (!out_valid && !overflow && in_ready && data_out == 0)
            else $fatal(1, "运行中复位行为错误");

        assert (output_count == 900)
            else $fatal(1, "已检查输出数量错误，实际%0d，期望900", output_count);

        test_passed = 1'b1;
        $display("TEST PASSED");
    end

endmodule

`default_nettype wire

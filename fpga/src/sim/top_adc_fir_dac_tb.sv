`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：top_adc_fir_dac_tb
//
// 主要功能：
//   自检任务D双通道顶层的MMCM启动、COE系数装载、100倍降采样、FIR定点卷积、
//   双路valid对齐、FIR到DAC码制转换以及运行中复位。
//
// 使用方法：
//   从仓库work目录运行fpga/scripts/sim_top_adc_fir_dac.tcl。
//
// 连接说明：
//   testbench产生50 MHz板级时钟，并在两路ADC转发时钟之后更新不同的10位码流。
//
// 时钟与复位：
//   clk_50m周期20 ns；真实clock_tree产生30 MHz时钟。rst_n模拟低有效PL_KEY1。
//
// 输入格式：
//   两路ADC均为10位偏移二进制；数据源每100个ADC周期切换电平，使降采样结果
//   覆盖正数、负数和零附近值。
//
// 输出格式与检查：
//   参考模型直接读取装载完成后的Q1.31系数，对每个实际decim_valid样本执行129抽头
//   64位卷积，再按RTL的右移/饱和规则比较两路FIR结果；随后检查双路插值连续性、
//   插值器到DAC的一拍数据对齐、偏移码和反相。
//
// 错误行为：
//   任一协议、数据、延迟对齐、复位或物理接口断言失败均调用$fatal。全部检查完成
//   后test_passed置1并打印TEST PASSED。
//
// 使用限制：
//   该测试验证数字链路，不能替代模拟幅频、ADC/DAC噪声、过量程或板级眼图测试。
// ============================================================================
module top_adc_fir_dac_tb;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int TAP_COUNT = 129;

    logic clk_50m;
    logic rst_n;
    logic [9:0] adc_data_a;
    logic [9:0] adc_data_b;
    logic adc_clk_a;
    logic adc_clk_b;
    logic adc_oe_a;
    logic adc_oe_b;
    logic [9:0] dac_data_a;
    logic [9:0] dac_data_b;
    logic dac_clk_a;
    logic dac_clk_b;
    logic test_passed;

    logic signed [9:0] history_a [0:TAP_COUNT-2];
    logic signed [9:0] history_b [0:TAP_COUNT-2];
    logic signed [9:0] expected_fir_a;
    logic signed [9:0] expected_fir_b;
    logic expected_pending;
    logic [9:0] expected_dac_a;
    logic [9:0] expected_dac_b;
    logic [9:0] dac_stage_a;
    logic [9:0] dac_stage_b;
    logic dac_stage_valid;
    logic dac_pending;
    int unsigned adc_edge_count_a;
    int unsigned adc_edge_count_b;
    int unsigned output_count;
    int unsigned interp_output_count;
    integer model_index;
    longint signed accumulator_a;
    longint signed accumulator_b;
    longint signed sample_value_a;
    longint signed sample_value_b;
    longint signed coefficient_value;

    top_adc_fir_dac #(
        .ADC_STARTUP_CYCLES      (3),
        .FIR_TAPS                (TAP_COUNT),
        .FIR_MAC_LANES           (2),
        .COEF_POLL_CYCLES        (4),
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

    always #10ns clk_50m = ~clk_50m;

    function automatic logic [9:0] source_code_a(input int unsigned block_number);
        begin
            case (block_number % 6)
                0: source_code_a = 10'd612;
                1: source_code_a = 10'd712;
                2: source_code_a = 10'd512;
                3: source_code_a = 10'd362;
                4: source_code_a = 10'd462;
                default: source_code_a = 10'd562;
            endcase
        end
    endfunction

    function automatic logic [9:0] source_code_b(input int unsigned block_number);
        begin
            case (block_number % 6)
                0: source_code_b = 10'd432;
                1: source_code_b = 10'd532;
                2: source_code_b = 10'd632;
                3: source_code_b = 10'd512;
                4: source_code_b = 10'd292;
                default: source_code_b = 10'd752;
            endcase
        end
    endfunction

    function automatic logic signed [9:0] saturate_reference(input longint signed sum);
        longint signed scaled;
        begin
            scaled = (sum + (64'sd1 <<< 30)) >>> 31;
            if (scaled > 511)
                saturate_reference = 10'sd511;
            else if (scaled < -512)
                saturate_reference = -10'sd512;
            else
                saturate_reference = scaled[9:0];
        end
    endfunction

    function automatic logic [9:0] fir_to_dac_code(input logic signed [9:0] value);
        logic signed [10:0] extended;
        logic signed [9:0] inverted;
        begin
            extended = -$signed({value[9], value});
            if (extended > 511)
                inverted = 10'sd511;
            else if (extended < -512)
                inverted = -10'sd512;
            else
                inverted = extended[9:0];
            fir_to_dac_code = $unsigned(inverted) ^ 10'h200;
        end
    endfunction

    // ADC模型在转发时钟上升沿后25 ns更新，匹配现有XDC采用的最大tCO模型。
    always @(posedge adc_clk_a) begin
        adc_edge_count_a <= adc_edge_count_a + 1;
        #25ns adc_data_a <= source_code_a(adc_edge_count_a / 100);
    end

    always @(posedge adc_clk_b) begin
        adc_edge_count_b <= adc_edge_count_b + 1;
        #25ns adc_data_b <= source_code_b(adc_edge_count_b / 100);
    end

    // 以真正送入FIR的降采样样本建立直接卷积参考模型，避免依赖ADC模型相位。
    always @(posedge dut.clk_sample) begin
        logic accept_sample;
        logic signed [9:0] accepted_a;
        logic signed [9:0] accepted_b;

        accept_sample = dut.decim_valid_a && dut.decim_valid_b &&
                        dut.coef_ready && !dut.coef_error;
        accepted_a = dut.decim_data_a;
        accepted_b = dut.decim_data_b;
        #1ps;

        if (dut.rst_sample || dut.coef_clear) begin
            expected_pending = 1'b0;
            dac_pending = 1'b0;
            dac_stage_valid = 1'b0;
            output_count = 0;
            interp_output_count = 0;
            for (model_index = 0; model_index < TAP_COUNT-1;
                 model_index = model_index + 1) begin
                history_a[model_index] = 10'sd0;
                history_b[model_index] = 10'sd0;
            end
        end else begin
            if (accept_sample) begin
                assert (!expected_pending)
                    else $fatal(1, "上一FIR样本尚未完成就收到新样本");
                accumulator_a = 64'sd0;
                accumulator_b = 64'sd0;
                sample_value_a = accepted_a;
                sample_value_b = accepted_b;
                coefficient_value = $signed(dut.u_fir_a.coeff[0]);
                accumulator_a = sample_value_a * coefficient_value;
                accumulator_b = sample_value_b * coefficient_value;
                for (model_index = 1; model_index < TAP_COUNT;
                     model_index = model_index + 1) begin
                    coefficient_value = $signed(dut.u_fir_a.coeff[model_index]);
                    sample_value_a = history_a[model_index-1];
                    sample_value_b = history_b[model_index-1];
                    accumulator_a = accumulator_a + sample_value_a * coefficient_value;
                    accumulator_b = accumulator_b + sample_value_b * coefficient_value;
                end
                for (model_index = TAP_COUNT-2; model_index > 0;
                     model_index = model_index - 1) begin
                    history_a[model_index] = history_a[model_index-1];
                    history_b[model_index] = history_b[model_index-1];
                end
                history_a[0] = accepted_a;
                history_b[0] = accepted_b;
                expected_fir_a = saturate_reference(accumulator_a);
                expected_fir_b = saturate_reference(accumulator_b);
                expected_pending = 1'b1;
            end

            assert (dut.fir_valid_a == dut.fir_valid_b)
                else $fatal(1, "双路FIR valid失配，时间=%0t", $time);
            if (dut.fir_valid_a) begin
                assert (expected_pending)
                    else $fatal(1, "FIR输出没有对应参考输入");
                assert (dut.fir_data_a === expected_fir_a)
                    else $fatal(1, "FIR通道A错误：实际=%0d，期望=%0d，序号=%0d",
                                dut.fir_data_a, expected_fir_a, output_count);
                assert (dut.fir_data_b === expected_fir_b)
                    else $fatal(1, "FIR通道B错误：实际=%0d，期望=%0d，序号=%0d",
                                dut.fir_data_b, expected_fir_b, output_count);
                expected_pending = 1'b0;
                output_count = output_count + 1;
            end

            assert (dut.interp_valid_a == dut.interp_valid_b)
                else $fatal(1, "双路插值valid失配，时间=%0t", $time);
            if (dut.interp_valid_a) begin
                // dac_output在本上升沿接收上一拍适配结果，随后下降沿更新物理数据。
                if (dac_stage_valid) begin
                    expected_dac_a = dac_stage_a;
                    expected_dac_b = dac_stage_b;
                    dac_pending = 1'b1;
                end
                dac_stage_a = fir_to_dac_code(dut.interp_data_a);
                dac_stage_b = fir_to_dac_code(dut.interp_data_b);
                dac_stage_valid = 1'b1;
                interp_output_count = interp_output_count + 1;
            end
        end
    end

    always @(negedge dut.clk_sample) begin
        #1ns;
        if (!dut.rst_sample && dac_pending) begin
            assert (dac_data_a === expected_dac_a)
                else $fatal(1, "DAC通道A插值码错误：实际=%03h，期望=%03h",
                            dac_data_a, expected_dac_a);
            assert (dac_data_b === expected_dac_b)
                else $fatal(1, "DAC通道B插值码错误：实际=%03h，期望=%03h",
                            dac_data_b, expected_dac_b);
            dac_pending = 1'b0;
        end
    end

    initial begin
        test_passed = 1'b0;
        clk_50m = 1'b0;
        rst_n = 1'b0;
        adc_data_a = 10'd512;
        adc_data_b = 10'd512;
        adc_edge_count_a = 0;
        adc_edge_count_b = 0;
        output_count = 0;
        expected_pending = 1'b0;
        dac_pending = 1'b0;
        dac_stage_a = 10'd512;
        dac_stage_b = 10'd512;
        dac_stage_valid = 1'b0;
        interp_output_count = 0;
        expected_fir_a = 10'sd0;
        expected_fir_b = 10'sd0;
        expected_dac_a = 10'd512;
        expected_dac_b = 10'd512;
        for (model_index = 0; model_index < TAP_COUNT-1;
             model_index = model_index + 1) begin
            history_a[model_index] = 10'sd0;
            history_b[model_index] = 10'sd0;
        end

        #200ns rst_n = 1'b1;
        fork
            begin
                #20us;
                $fatal(1, "等待MMCM锁定超时");
            end
            begin
                @(posedge dut.clock_locked_unused);
            end
        join_any
        disable fork;

        wait (!dut.rst_sample);
        wait (dut.coef_ready || dut.coef_error);
        #1ns;
        assert (dut.coef_ready && !dut.coef_error)
            else $fatal(1, "带通COE协议检查或系数装载失败");
        assert (dut.coef_generation == 32'd1)
            else $fatal(1, "系数generation错误：实际=%0d", dut.coef_generation);
        assert (dut.u_fir_a.coeff[0] == 32'sh0000_753E &&
                dut.u_fir_a.coeff[64] == 32'sh0E87_684F &&
                dut.u_fir_a.coeff[128] == 32'sh0000_753E)
            else $fatal(1, "FIR通道A关键带通系数错误");
        assert (dut.u_fir_b.coeff[0] == dut.u_fir_a.coeff[0] &&
                dut.u_fir_b.coeff[64] == dut.u_fir_a.coeff[64] &&
                dut.u_fir_b.coeff[128] == dut.u_fir_a.coeff[128])
            else $fatal(1, "双路FIR系数不一致");

        wait (output_count >= 10 && interp_output_count >= 950 && !dac_pending);
        assert (!dut.valid_mismatch)
            else $fatal(1, "运行期间出现双路valid失配");
        assert (!dut.interp_overflow_a && !dut.interp_overflow_b)
            else $fatal(1, "FIR输出间隔不足，插值器发生输入溢出");
        assert (!dut.bram_addrb_error)
            else $fatal(1, "系数BRAM出现非法地址");

        // 运行中复位应立即停止外部时钟、关闭ADC总线，并恢复DAC中间码。
        #7ns rst_n = 1'b0;
        #2ns;
        assert (adc_oe_a && adc_oe_b)
            else $fatal(1, "运行中复位未关闭ADC输出");
        assert (!adc_clk_a && !adc_clk_b && !dac_clk_a && !dac_clk_b)
            else $fatal(1, "运行中复位未停止接口时钟");
        wait (dac_data_a == 10'd512 && dac_data_b == 10'd512);

        test_passed = 1'b1;
        $display("TEST PASSED: 任务D双路COE装载、降采样、FIR卷积、DAC码制和复位通过");
        $finish;
    end

    initial begin
        #2ms;
        $fatal(1, "top_adc_fir_dac集成仿真超时");
    end
endmodule

`default_nettype wire

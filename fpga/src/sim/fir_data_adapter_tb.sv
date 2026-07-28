`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：fir_data_adapter_tb
//
// 主要功能：
//   穷举验证10位ADC偏移二进制到FIR补码、FIR补码到DAC偏移二进制、DA反相
//   补偿、最小负数饱和和两路valid组合透传。
//
// 使用方法：
//   从仓库work目录运行fpga/scripts/sim_fir_data_adapter.tcl。
//
// 连接说明：
//   实例化一份启用反相补偿和一份关闭反相补偿的被测模块，无外部连接。
//
// 时钟与复位：
//   被测模块为纯组合逻辑，本testbench不产生时钟或复位。
//
// 输入格式：
//   穷举全部1024个10位ADC码和全部1024个10位FIR补码位模式。
//
// 输出格式：
//   使用整数参考模型逐项比较数据、valid和饱和标志。
//
// 握手时序：
//   每次改变输入后等待1 ns使组合逻辑稳定，再执行断言。
//
// 参数说明：
//   固定DATA_W=10，与当前AD、FIR和DA接口一致。
//
// 错误行为：
//   任一比较失败调用$fatal；全部2048组主要输入检查通过后输出TEST PASSED。
//
// 使用限制：
//   仅验证数字码制关系，不模拟ADC/DAC模拟增益、偏置和噪声。
// ============================================================================

module fir_data_adapter_tb;

    timeunit 1ns;
    timeprecision 1ps;

    localparam int unsigned DATA_W = 10;
    localparam int signed CODE_COUNT = 1 << DATA_W;
    localparam int signed HALF_SCALE = 1 << (DATA_W-1);

    logic [DATA_W-1:0] adc_data;
    logic              adc_valid;
    logic signed [DATA_W-1:0] fir_in_data_comp;
    logic              fir_in_valid_comp;
    logic signed [DATA_W-1:0] fir_out_data;
    logic              fir_out_valid;
    logic [DATA_W-1:0] dac_data_comp;
    logic              dac_valid_comp;
    logic              dac_clipped_comp;

    logic signed [DATA_W-1:0] fir_in_data_plain;
    logic              fir_in_valid_plain;
    logic [DATA_W-1:0] dac_data_plain;
    logic              dac_valid_plain;
    logic              dac_clipped_plain;
    logic              test_passed;

    int signed code;
    int signed signed_value;
    int signed converted_value;
    int signed expected_dac_comp;
    int signed expected_dac_plain;
    logic expected_valid;

    fir_data_adapter #(
        .DATA_W(DATA_W),
        .COMPENSATE_DAC_INVERSION(1'b1)
    ) dut_comp (
        .adc_data     (adc_data),
        .adc_valid    (adc_valid),
        .fir_in_data  (fir_in_data_comp),
        .fir_in_valid (fir_in_valid_comp),
        .fir_out_data (fir_out_data),
        .fir_out_valid(fir_out_valid),
        .dac_data     (dac_data_comp),
        .dac_valid    (dac_valid_comp),
        .dac_clipped  (dac_clipped_comp)
    );

    fir_data_adapter #(
        .DATA_W(DATA_W),
        .COMPENSATE_DAC_INVERSION(1'b0)
    ) dut_plain (
        .adc_data     (adc_data),
        .adc_valid    (adc_valid),
        .fir_in_data  (fir_in_data_plain),
        .fir_in_valid (fir_in_valid_plain),
        .fir_out_data (fir_out_data),
        .fir_out_valid(fir_out_valid),
        .dac_data     (dac_data_plain),
        .dac_valid    (dac_valid_plain),
        .dac_clipped  (dac_clipped_plain)
    );

    initial begin
        test_passed  = 1'b0;
        adc_data     = '0;
        adc_valid    = 1'b0;
        fir_out_data = '0;
        fir_out_valid = 1'b0;

        // 穷举ADC偏移二进制到FIR补码，并交替检查valid高低两种状态。
        for (code = 0; code < CODE_COUNT; code = code + 1) begin
            adc_data  = DATA_W'(code);
            adc_valid = ((code & 1) != 0);
            #1ns;
            signed_value = code - HALF_SCALE;

            assert ($signed(fir_in_data_comp) == signed_value)
                else $fatal(1, "ADC到FIR转换错误：ADC=%0d，实际=%0d，期望=%0d",
                            code, $signed(fir_in_data_comp), signed_value);
            assert (fir_in_data_plain === fir_in_data_comp)
                else $fatal(1, "ADC到FIR转换不应受DA反相参数影响：ADC=%0d", code);
            assert ((fir_in_valid_comp === adc_valid) &&
                    (fir_in_valid_plain === adc_valid))
                else $fatal(1, "ADC valid透传错误：ADC=%0d", code);
        end

        // 穷举FIR补码的全部位模式，同时验证普通码制转换和DA反相补偿。
        for (code = 0; code < CODE_COUNT; code = code + 1) begin
            fir_out_data  = DATA_W'(code);
            expected_valid = ((code % 3) != 0);
            fir_out_valid = expected_valid;
            #1ns;

            if (code >= HALF_SCALE)
                signed_value = code - CODE_COUNT;
            else
                signed_value = code;

            expected_dac_plain = signed_value + HALF_SCALE;
            converted_value = -signed_value;
            if (converted_value > HALF_SCALE-1)
                converted_value = HALF_SCALE-1;
            else if (converted_value < -HALF_SCALE)
                converted_value = -HALF_SCALE;
            expected_dac_comp = converted_value + HALF_SCALE;

            assert ($unsigned(dac_data_plain) == expected_dac_plain)
                else $fatal(1, "FIR到DAC普通转换错误：FIR=%0d，实际=%0d，期望=%0d",
                            signed_value, $unsigned(dac_data_plain), expected_dac_plain);
            assert ($unsigned(dac_data_comp) == expected_dac_comp)
                else $fatal(1, "FIR到DAC反相转换错误：FIR=%0d，实际=%0d，期望=%0d",
                            signed_value, $unsigned(dac_data_comp), expected_dac_comp);
            assert ((dac_valid_comp === expected_valid) &&
                    (dac_valid_plain === expected_valid))
                else $fatal(1, "DAC valid透传错误：FIR位模式=%0h", code);
            assert (!dac_clipped_plain)
                else $fatal(1, "关闭反相补偿时不应饱和：FIR=%0d", signed_value);
            assert (dac_clipped_comp ===
                    (expected_valid && (signed_value == -HALF_SCALE)))
                else $fatal(1, "DA反相饱和标志错误：FIR=%0d，valid=%0b",
                            signed_value, expected_valid);
        end

        // 单独确认最小负数在valid为高时饱和并报告，避免穷举中的valid模式遗漏。
        fir_out_data  = DATA_W'(-HALF_SCALE);
        fir_out_valid = 1'b1;
        #1ns;
        assert ((dac_data_comp == {DATA_W{1'b1}}) && dac_clipped_comp)
            else $fatal(1, "最小负数反相饱和检查失败");

        test_passed = 1'b1;
        $display("TEST PASSED: ADC码1024组，FIR码1024组");
        $finish;
    end

endmodule

`default_nettype wire

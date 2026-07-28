`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：fir_data_adapter
//
// 主要功能：
//   完成 ADC、FIR 和 DAC 之间的采样码制转换。ADC 到 FIR 方向将无符号偏移
//   二进制转换为同位宽 signed 二进制补码；FIR 到 DAC 方向将 signed 二进制
//   补码转换为无符号偏移二进制，并可选择补偿 DA 板模拟输出级的反相特性。
//
// 使用方法：
//   1. 将 adc_data/adc_valid 连接到 adc_capture 的采样数据和有效信号。
//   2. 任务D中将 fir_in_data/fir_in_valid 先连接 adc_decimator_100，再由降采样
//      输出连接 fir_filter；旁路降采样时可直接连接 fir_filter 的输入接口。
//   3. 将 fir_out_data/fir_out_valid 连接到 fir_filter 的输出接口。
//   4. 将 dac_data/dac_valid 连接到 dac_output 的输入接口。
//
// 连接说明：
//   adc_data      <- adc_capture 的已寄存 ADC 原始码。
//   adc_valid     <- adc_capture 的 out_valid。
//   fir_in_data   -> adc_decimator_100 的 sample_data，或旁路时连接 fir_filter。
//   fir_in_valid  -> adc_decimator_100 的 sample_valid，组合透传 adc_valid。
//   fir_out_data  <- fir_filter 的 out_data。
//   fir_out_valid <- fir_filter 的 out_valid。
//   dac_data      -> dac_output 的 data_a 或 data_b。
//   dac_valid     -> dac_output 的 in_valid，组合透传 fir_out_valid。
//   dac_clipped   -> 顶层状态观察或 ILA；表示本拍反相补偿发生边界饱和。
//
// 时钟与复位：
//   本模块为纯组合逻辑，没有时钟和复位。ADC、FIR、DAC 数据接口必须属于同一
//   时钟域；本模块不提供跨时钟域同步，也不保存任何历史状态。
//
// 输入格式：
//   adc_data 为 DATA_W 位无符号偏移二进制。DATA_W=10 时，0、512、1023
//   分别表示最小负值、零和最大正值。
//   fir_out_data 为 DATA_W 位 signed 二进制补码，范围为 -2^(DATA_W-1) 到
//   2^(DATA_W-1)-1。
//
// 输出格式：
//   fir_in_data 为 DATA_W 位 signed 二进制补码。转换仅翻转最高位，不改变
//   其余位，因此 DATA_W=10 时映射为 0->-512、512->0、1023->511。
//   dac_data 为 DATA_W 位无符号偏移二进制。启用 DA 反相补偿后，先对 FIR
//   输出做算术取负和饱和，再翻转最高位完成偏移二进制编码。
//
// 握手时序：
//   两条 valid 均为组合透传，不提供 ready 或反压。输入变化后输出经过组合逻辑
//   稳定，没有额外寄存周期；每个时钟周期均可转换一组数据。
//
// 参数说明：
//   DATA_W 为三侧统一数据位宽，必须大于等于 2。
//   COMPENSATE_DAC_INVERSION 为 1 时补偿 DA 模拟输出反相，为 0 时仅转换码制。
//
// 输出有效与延迟：
//   fir_in_valid/dac_valid 有效期间，相应数据输出有效。组合延迟由最高位异或、
//   可选取负和边界比较构成，不引入整周期延迟。
//
// 舍入、截位和饱和：
//   码制转换没有小数位变化，因此不舍入、不截位。反相补偿时，最小补码
//   -2^(DATA_W-1) 的相反数无法用 DATA_W 位表示，会饱和为最大正数并拉高
//   dac_clipped；其他输入均可精确转换。
//
// 错误行为：
//   valid 为低时数据输出仍保持对应输入的组合转换结果，但下游不得使用该数据。
//   数据位宽配置小于 2 时，仿真立即报错并停止。
//
// 使用限制：
//   本模块假定 ADC 和 DAC 均采用以半量程为零点的偏移二进制。更换转换器或
//   确认 DA 模拟级不反相后，必须相应调整参数，不得把本模块用于不同码制。
// ============================================================================

module fir_data_adapter #(
    parameter int unsigned DATA_W = 10,                    // ADC、FIR、DAC 统一位宽，必须大于等于 2
    parameter bit COMPENSATE_DAC_INVERSION = 1'b1          // 为 1 时对 FIR 输出取负以补偿 DA 模拟反相
) (
    input  wire  logic [DATA_W-1:0]        adc_data,       // ADC原始采样，无符号偏移二进制
    input  wire  logic                     adc_valid,      // ADC输入有效，高电平期间adc_data可用
    output       logic signed [DATA_W-1:0] fir_in_data,    // FIR输入，signed二进制补码
    output       logic                     fir_in_valid,   // FIR输入有效，组合透传adc_valid

    input  wire  logic signed [DATA_W-1:0] fir_out_data,   // FIR输出，signed二进制补码
    input  wire  logic                     fir_out_valid,  // FIR输出有效，高电平期间fir_out_data可用
    output       logic [DATA_W-1:0]        dac_data,       // DAC输出码，无符号偏移二进制
    output       logic                     dac_valid,      // DAC输出有效，组合透传fir_out_valid
    output       logic                     dac_clipped     // 本拍反相补偿发生饱和，且dac_valid有效
);

    localparam logic [DATA_W-1:0] OFFSET_MASK = {
        1'b1, {(DATA_W-1){1'b0}}
    };
    localparam logic signed [DATA_W-1:0] SIGNED_MAX = {
        1'b0, {(DATA_W-1){1'b1}}
    };
    localparam logic signed [DATA_W-1:0] SIGNED_MIN = {
        1'b1, {(DATA_W-1){1'b0}}
    };
    localparam logic signed [DATA_W:0] SIGNED_MAX_EXT = {
        1'b0, SIGNED_MAX
    };
    localparam logic signed [DATA_W:0] SIGNED_MIN_EXT = {
        1'b1, SIGNED_MIN
    };

    logic signed [DATA_W:0] fir_out_ext;
    logic signed [DATA_W:0] converted_ext;
    logic signed [DATA_W-1:0] converted_signed;

    initial begin
        assert (DATA_W >= 2)
            else $fatal(1, "DATA_W 必须大于等于 2");
    end

    always_comb begin
        // 偏移二进制与同位宽补码之间只需翻转最高位，其余位保持不变。
        fir_in_data  = $signed(adc_data ^ OFFSET_MASK);
        fir_in_valid = adc_valid;

        fir_out_ext     = {fir_out_data[DATA_W-1], fir_out_data};
        converted_ext   = fir_out_ext;
        converted_signed = fir_out_data;
        dac_clipped     = 1'b0;

        if (COMPENSATE_DAC_INVERSION) begin
            converted_ext = -fir_out_ext;
            if (converted_ext > SIGNED_MAX_EXT) begin
                converted_signed = SIGNED_MAX;
                dac_clipped = fir_out_valid;
            end else if (converted_ext < SIGNED_MIN_EXT) begin
                converted_signed = SIGNED_MIN;
                dac_clipped = fir_out_valid;
            end else begin
                converted_signed = converted_ext[DATA_W-1:0];
            end
        end

        dac_data  = $unsigned(converted_signed) ^ OFFSET_MASK;
        dac_valid = fir_out_valid;
    end

endmodule

`default_nettype wire

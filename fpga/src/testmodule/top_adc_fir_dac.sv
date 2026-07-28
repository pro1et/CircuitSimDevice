`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：top_adc_fir_dac
//
// 主要功能：
//   在Mizar Z7上建立双通道AD-FIR-DA实时链路，独立验证300 kS/s、129抽头带通
//   FIR的码制转换、系数初始化、有效信号、固定点乘加和物理ADC/DAC接口。
//   本顶层不包含DDS、扫频、IQ、PS或AXI通信；本地BRAM只提供上电初始系数。
//
// 使用方法：
//   1. AD板插JP2/GPIO2，DA板插JP1/GPIO1，并确认两个接口均使用3.3 V电平。
//   2. 用fir_bandpass_10k_25k.coe重新生成coef_bram_ip。
//   3. 在Vivado中选择top_adc_fir_dac.xdc并将本模块设为综合顶层。
//   4. 分别输入通带内和通带外的小幅正弦波，比较DAC输出幅度。
//
// 连接说明：
//   clk_50m/rst_n         <- Mizar Z7板载PL时钟和PL_KEY1
//   adc_data_a/b          <- AD板双通道D0..D9
//   adc_clk_a/b、adc_oe_* -> AD板双通道时钟和输出允许
//   dac_data_a/b、dac_clk_* -> DA板双通道数据和锁存时钟
//
// 时钟与复位：
//   clock_tree由50 MHz产生30 MHz处理/接口时钟。板级rst_n低有效异步输入，
//   下游使用clock_tree产生的30 MHz域高有效复位；旧式低有效接口连接其反相信号。
//
// 输入格式：
//   ADC物理码为10位偏移二进制，0/512/1023对应最小值/零/最大值。适配器翻转
//   最高位得到10位signed补码，100点滑动块平均每100个30 MHz样本产生一个
//   300 kS/s有效样本。
//
// 输出格式：
//   FIR使用signed 10位样本和Q1.31系数，56位累加，右移31位后饱和为signed
//   10位。适配器转换回偏移二进制，并默认补偿DA板模拟输出级的反相极性。
//
// 握手时序：
//   ADC启动后每拍有效；降采样器每100拍输出一个有效脉冲。coef_ready前FIR输入
//   被门控。每路FIR使用FIR_MAC_LANES路MAC，约ceil(FIR_TAPS/FIR_MAC_LANES)
//   拍后输出单拍valid；两路valid同时有效时DAC接收一对新样本，其余时间保持。
//
// 参数说明：
//   ADC_STARTUP_CYCLES为ADC启动屏蔽拍数；FIR_TAPS固定应与COE头一致；
//   FIR_MAC_LANES控制每路DSP并行数；COEF_POLL_CYCLES控制本地快照首次轮询等待；
//   COMPENSATE_DAC_INVERSION控制DA模拟反相补偿。
//
// 输出有效与延迟：
//   启动时先等待MMCM、ADC屏蔽和系数装载。稳态样本延迟包含100点块平均窗口、
//   FIR的ceil(FIR_TAPS/FIR_MAC_LANES)拍计算以及DAC半拍输出寄存延迟。
//
// 错误行为：
//   COE协议头错误时coef_ready不成立，DAC保持复位中间码。内部保留系数错误、
//   BRAM地址错误、双路valid失配和DAC饱和标志，必要时可接ILA观察。
//
// Vivado使用：
//   必须从仓库work目录，在conda环境vivado2022中运行
//   fpga/scripts/sim_top_adc_fir_dac.tcl和build_top_adc_fir_dac.tcl。
//
// 上板测试与预期现象：
//   先给两路输入15 kHz、小幅正弦波，DAC应输出同频波形；再换为3 kHz或40 kHz，
//   输出应明显衰减。10 kHz和25 kHz处幅度理论上约为通带中心的-3 dB。
//
// 使用限制：
//   仅针对xc7z020clg400-2和当前3.3 V转接板。300 kS/s输出采用零阶保持，DAC
//   波形会包含采样镜像；模拟滤波器幅频和板级增益不属于本数字顶层保证范围。
// ============================================================================
module top_adc_fir_dac #(
    parameter int unsigned ADC_STARTUP_CYCLES = 6, // ADC解除复位后的数据屏蔽周期数
    parameter int unsigned FIR_TAPS = 129,         // FIR抽头数，必须与COE头一致
    parameter int unsigned FIR_MAC_LANES = 2,      // 每路FIR并行MAC数量，默认2路、65拍完成
    parameter int unsigned COEF_POLL_CYCLES = 16,  // 本地系数快照轮询间隔，单位30 MHz周期
    parameter bit COMPENSATE_DAC_INVERSION = 1'b1  // 为1时补偿DA板模拟输出反相
) (
    input  wire  logic       clk_50m,     // 板载PL 50 MHz时钟输入，连接H16
    input  wire  logic       rst_n,       // PL_KEY1低有效人工复位，连接R19

    input  wire  logic [9:0] adc_data_a,  // AD通道1并行输入，10位偏移二进制
    input  wire  logic [9:0] adc_data_b,  // AD通道2并行输入，10位偏移二进制
    output wire  logic       adc_clk_a,   // AD通道1转发时钟，30 MHz
    output wire  logic       adc_clk_b,   // AD通道2转发时钟，30 MHz
    output wire  logic       adc_oe_a,    // AD通道1输出允许，高电平关闭ADC总线
    output wire  logic       adc_oe_b,    // AD通道2输出允许，高电平关闭ADC总线

    output       logic [9:0] dac_data_a,  // DA通道1并行输出，10位偏移二进制
    output       logic [9:0] dac_data_b,  // DA通道2并行输出，10位偏移二进制
    output wire  logic       dac_clk_a,   // DA通道1转发时钟，30 MHz
    output wire  logic       dac_clk_b    // DA通道2转发时钟，30 MHz
);
    localparam int unsigned DECIM_FACTOR = 100;
    localparam int unsigned FIR_ACC_W = 56;

    logic       clk_100m_unused;
    logic       clk_sample;
    logic       clk_adc_drive;
    logic       rst_100m_unused;
    logic       rst_sample;
    logic       rst_sample_n;
    logic       clock_locked_unused;

    logic [9:0] adc_sample_a;
    logic [9:0] adc_sample_b;
    logic       adc_valid;
    logic signed [9:0] adc_signed_a;
    logic signed [9:0] adc_signed_b;
    logic       adc_signed_valid_a;
    logic       adc_signed_valid_b;
    logic signed [9:0] decim_data_a;
    logic signed [9:0] decim_data_b;
    logic       decim_valid_a;
    logic       decim_valid_b;

    logic signed [9:0] fir_data_a;
    logic signed [9:0] fir_data_b;
    logic       fir_valid_a;
    logic       fir_valid_b;
    logic [9:0] dac_input_a;
    logic [9:0] dac_input_b;
    logic       dac_valid_a;
    logic       dac_valid_b;
    logic       dac_clipped_a;
    logic       dac_clipped_b;
    logic       dac_ready_unused;

    logic       bram_clkb;
    logic       bram_rstb;
    logic       bram_enb;
    logic [3:0] bram_web;
    logic [31:0] bram_addrb;
    logic [31:0] bram_dinb;
    logic [31:0] bram_doutb;
    logic       bram_addra_error_unused;
    (* mark_debug = "true" *) logic bram_addrb_error;
    logic       coef_we;
    logic [7:0] coef_addr;
    logic [31:0] coef_wdata;
    logic       coef_clear;
    (* mark_debug = "true" *) logic coef_ready;
    (* mark_debug = "true" *) logic coef_error;
    logic [31:0] coef_generation;
    (* mark_debug = "true" *) logic valid_mismatch;

    initial begin
        assert (ADC_STARTUP_CYCLES >= 1)
            else $fatal(1, "ADC_STARTUP_CYCLES必须大于等于1");
        assert (FIR_TAPS == 129)
            else $fatal(1, "当前带通COE要求FIR_TAPS等于129");
        assert (((FIR_TAPS + FIR_MAC_LANES - 1) / FIR_MAC_LANES) < DECIM_FACTOR)
            else $fatal(1, "FIR计算周期必须小于100拍降采样间隔");
        assert (COEF_POLL_CYCLES >= 1)
            else $fatal(1, "COEF_POLL_CYCLES必须大于等于1");
    end

    assign rst_sample_n = ~rst_sample;

    clock_tree u_clock_tree (
        .clk_50m    (clk_50m),
        .rst_n      (rst_n),
        .clk_100m   (clk_100m_unused),
        .clk_30m    (clk_sample),
        .clk_30m_adc(clk_adc_drive),
        .rst_100m   (rst_100m_unused),
        .rst_30m    (rst_sample),
        .locked     (clock_locked_unused)
    );

    adc_capture #(
        .STARTUP_CYCLES(ADC_STARTUP_CYCLES)
    ) u_adc_capture (
        .clk       (clk_sample),
        .clk_drive (clk_adc_drive),
        .rst       (rst_sample),
        .adc_data_a(adc_data_a),
        .adc_data_b(adc_data_b),
        .adc_clk_a (adc_clk_a),
        .adc_clk_b (adc_clk_b),
        .adc_oe_a  (adc_oe_a),
        .adc_oe_b  (adc_oe_b),
        .data_a    (adc_sample_a),
        .data_b    (adc_sample_b),
        .out_valid (adc_valid)
    );

    fir_data_adapter #(
        .DATA_W(10),
        .COMPENSATE_DAC_INVERSION(COMPENSATE_DAC_INVERSION)
    ) u_adapter_a (
        .adc_data     (adc_sample_a),
        .adc_valid    (adc_valid),
        .fir_in_data  (adc_signed_a),
        .fir_in_valid (adc_signed_valid_a),
        .fir_out_data (fir_data_a),
        .fir_out_valid(fir_valid_a),
        .dac_data     (dac_input_a),
        .dac_valid    (dac_valid_a),
        .dac_clipped  (dac_clipped_a)
    );

    fir_data_adapter #(
        .DATA_W(10),
        .COMPENSATE_DAC_INVERSION(COMPENSATE_DAC_INVERSION)
    ) u_adapter_b (
        .adc_data     (adc_sample_b),
        .adc_valid    (adc_valid),
        .fir_in_data  (adc_signed_b),
        .fir_in_valid (adc_signed_valid_b),
        .fir_out_data (fir_data_b),
        .fir_out_valid(fir_valid_b),
        .dac_data     (dac_input_b),
        .dac_valid    (dac_valid_b),
        .dac_clipped  (dac_clipped_b)
    );

    adc_decimator_100 #(
        .DATA_W      (10),
        .DECIM_FACTOR(DECIM_FACTOR),
        .ACC_W       (24)
    ) u_decimator_a (
        .clk         (clk_sample),
        .rst_n       (rst_sample_n),
        .sample_valid(adc_signed_valid_a),
        .sample_data (adc_signed_a),
        .decim_valid (decim_valid_a),
        .decim_data  (decim_data_a)
    );

    adc_decimator_100 #(
        .DATA_W      (10),
        .DECIM_FACTOR(DECIM_FACTOR),
        .ACC_W       (24)
    ) u_decimator_b (
        .clk         (clk_sample),
        .rst_n       (rst_sample_n),
        .sample_valid(adc_signed_valid_b),
        .sample_data (adc_signed_b),
        .decim_valid (decim_valid_b),
        .decim_data  (decim_data_b)
    );

    // BRAM A口在任务D中禁用；保留完整封装，使同一个IP后续可直接接AXI控制器。
    coef_bram u_coef_bram (
        .clka        (clk_sample),
        // 两个BRAM口同属30 MHz域，统一使用加载器寄存后的同步复位，避免
        // 异步复位寄存器直接驱动RAMB控制脚产生REQP-1839 DRC警告。
        .rsta        (bram_rstb),
        .ena         (1'b0),
        .wea         (4'b0000),
        .addra       (32'd0),
        .dina        (32'd0),
        .douta       (),
        .addra_error (bram_addra_error_unused),
        .clkb        (bram_clkb),
        .rstb        (bram_rstb),
        .enb         (bram_enb),
        .web         (bram_web),
        .addrb       (bram_addrb),
        .dinb        (bram_dinb),
        .doutb       (bram_doutb),
        .addrb_error (bram_addrb_error)
    );

    fir_coef_loader #(
        .TAP_COUNT  (FIR_TAPS),
        .POLL_CYCLES(COEF_POLL_CYCLES)
    ) u_coef_loader (
        .clk             (clk_sample),
        .rst_n           (rst_sample_n),
        .bram_clkb       (bram_clkb),
        .bram_rstb       (bram_rstb),
        .bram_enb        (bram_enb),
        .bram_web        (bram_web),
        .bram_addrb      (bram_addrb),
        .bram_dinb       (bram_dinb),
        .bram_doutb      (bram_doutb),
        .coef_we         (coef_we),
        .coef_addr       (coef_addr),
        .coef_wdata      (coef_wdata),
        .coef_clear      (coef_clear),
        .coef_ready      (coef_ready),
        .coef_error      (coef_error),
        .coef_generation (coef_generation)
    );

    fir_filter #(
        .DATA_W   (10),
        .TAP_COUNT(FIR_TAPS),
        .ACC_W    (FIR_ACC_W),
        .MAC_LANES(FIR_MAC_LANES)
    ) u_fir_a (
        .clk         (clk_sample),
        .rst_n       (rst_sample_n),
        .sample_valid(decim_valid_a && coef_ready && !coef_error),
        .sample_data (decim_data_a),
        .coef_we     (coef_we),
        .coef_addr   (coef_addr),
        .coef_wdata  (coef_wdata),
        .coef_clear  (coef_clear),
        .out_valid   (fir_valid_a),
        .out_data    (fir_data_a)
    );

    fir_filter #(
        .DATA_W   (10),
        .TAP_COUNT(FIR_TAPS),
        .ACC_W    (FIR_ACC_W),
        .MAC_LANES(FIR_MAC_LANES)
    ) u_fir_b (
        .clk         (clk_sample),
        .rst_n       (rst_sample_n),
        .sample_valid(decim_valid_b && coef_ready && !coef_error),
        .sample_data (decim_data_b),
        .coef_we     (coef_we),
        .coef_addr   (coef_addr),
        .coef_wdata  (coef_wdata),
        .coef_clear  (coef_clear),
        .out_valid   (fir_valid_b),
        .out_data    (fir_data_b)
    );

    // 任何双路valid失配都会阻止DAC接收半组数据，并留下粘滞状态供ILA检查。
    always_ff @(posedge clk_sample) begin
        if (rst_sample)
            valid_mismatch <= 1'b0;
        else if (dac_valid_a != dac_valid_b)
            valid_mismatch <= 1'b1;
    end

    dac_output #(
        .RESET_CODE(10'd512)
    ) u_dac_output (
        .clk       (clk_sample),
        .rst       (rst_sample),
        .data_a    (dac_input_a),
        .data_b    (dac_input_b),
        .in_valid  (dac_valid_a && dac_valid_b),
        .in_ready  (dac_ready_unused),
        .dac_data_a(dac_data_a),
        .dac_data_b(dac_data_b),
        .dac_clk_a (dac_clk_a),
        .dac_clk_b (dac_clk_b)
    );

endmodule

`default_nettype wire

// ============================================================================
// 当前顶层检查发现的问题与解决方法
// ============================================================================
// 1. 现象/位置：原fir_filter每路为129个抽头同时实例化乘法器。
//    原因：原转置结构按每拍一个30 MHz样本设计，没有利用实际300 kS/s有效脉冲间隔。
//    影响：双路共258个乘法器，超过xc7z020的220个DSP，无法可靠布局实现。
//    解决方法：改为每路2路MAC分时计算，65拍完成，小于100拍输入间隔。
//    当前状态：已解决；Vivado 2022.2实现使用10个DSP（含两路降采样器）且时序通过。
// 2. 现象/位置：任务D不接PS，但FIR复位后内部系数为零。
//    原因：fir_filter的系数必须通过写接口装载，不能直接读取COE语法。
//    影响：没有启动系数源时DAC只输出零点。
//    解决方法：本地coef_bram由带通COE初始化，fir_coef_loader校验协议头后装载；
//    A口保持禁用，不引入PS/AXI通信，后续PS开发仍复用同一BRAM封装。
//    当前状态：仿真、综合和实现已通过，仍需上板确认模拟效果。
// 3. 现象/位置：30 MHz输入需要降到300 kS/s才能匹配所设计的10~25 kHz FIR。
//    原因：MATLAB系数按300 kHz采样率设计，直接用于30 MHz会把通带扩大100倍。
//    影响：不降采样将无法得到目标带通响应。
//    解决方法：两路分别使用100点块平均和100倍有效脉冲降采样，不生成派生时钟。
//    当前状态：已实现；块平均自身幅频影响仍需纳入最终模拟测量。
// 4. 现象/位置：JP1/DA位于可调Bank 34，XDC使用LVCMOS33。
//    原因：开发板可通过电阻配置不同Bank电压。
//    影响：实板若非3.3 V会造成接口异常或电气风险。
//    解决方法：复用已核对的回环顶层管脚，上电前确认R208已贴、R209/R210未贴。
//    当前状态：待人工检查实板。
// 5. 现象/位置：DAC板模拟级极性、转换器延迟和板级时序来自现有资料。
//    原因：仓库没有完整转接板原理图及实测眼图。
//    影响：数字仿真/STA通过不能完全证明模拟幅频和硬件稳定性。
//    解决方法：默认开启反相补偿，按现有XDC延迟建模，并用示波器/ILA上板复核。
//    当前状态：待上板验证。
// 6. 现象/位置：最终DRC包含DSP未使用输入/M/P流水寄存器的建议性警告。
//    原因：当前MAC按30 MHz、每100拍一个输入设计，组合乘法结果直接进入累加寄存器。
//    影响：可能增加动态功耗，但实现后WNS为正且不影响300 kS/s吞吐。
//    解决方法：本测试顶层保留当前低延迟结构；若提高时钟再增加DSP流水并同步调整valid。
//    当前状态：已评估并接受，非功能或时序违例。

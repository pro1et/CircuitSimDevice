`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：top_adc_dac_loopback
//
// 主要功能：
//   在 Mizar Z7 开发板上建立双通道 AD-Digital-DA 实时回环链路，用于独立检查
//   ADC、DAC、两块 GPIO 转接板、并行数据位序和接口时钟。顶层只实例化时钟树、
//   ADC 采集和 DAC 输出模块，并完成 DAC 模拟极性所需的最小码值适配。
//
// 使用方法：
//   1. 将正点原子-微相-AD 转接板插入 Mizar Z7 的 JP2/GPIO2。
//   2. 将正点原子-微相-DA 转接板插入 Mizar Z7 的 JP1/GPIO1。
//   3. 使用 top_adc_dac_loopback.xdc，并将本模块设为 Vivado 综合顶层。
//   4. 上电前确认 Bank 34 的 R208 已贴装、R209/R210 未贴装，即 I/O 电压为 3.3 V。
//   5. 给 ADC 通道输入不超过模块允许范围的低频波形，用示波器观察对应 DAC 输出。
//
// 连接说明：
//   clk_50m     <- Mizar Z7 板载 PL 50 MHz 有源晶振 U19，FPGA 管脚 H16
//   rst_n       <- Mizar Z7 PL_KEY1/K4，FPGA 管脚 R19，按下为低电平
//   adc_data_a  <- AD 转接板通道 1 的 D0_1~D9_1，D9 为最高位
//   adc_data_b  <- AD 转接板通道 2 的 D0_2~D9_2，D9 为最高位
//   adc_clk_a/b -> AD 转接板的 CLK_1/CLK_2
//   adc_oe_a/b  -> AD 转接板的 OE_1/OE_2，低电平允许 ADC 驱动数据总线
//   dac_data_a  -> DA 转接板通道 1 的 D0_1~D9_1，D9 为最高位
//   dac_data_b  -> DA 转接板通道 2 的 D0_2~D9_2，D9 为最高位
//   dac_clk_a/b -> DA 转接板的 CLK1/CLK2
//
// 时钟与复位：
//   clock_tree 将 50 MHz 输入转换为 30 MHz 采样时钟，并产生与采样时钟同相的
//   ADC 驱动时钟。rst_n 为板级低有效异步复位输入；各子模块实际使用
//   clock_tree 产生的 30 MHz 域高有效、异步置位同步释放复位。
//
// 输入格式：
//   两路 ADC 数据均为 10 位无符号直二进制码，典型映射为 0=-5 V、512=0 V、
//   1023=+5 V。每个采样周期连续输入一组数据，不提供反压。
//
// 输出格式：
//   两路 DAC 数据均为 10 位无符号直二进制码。DA 板模拟放大级的输出极性与
//   数字码反向；默认对 ADC 码逐位取反，即执行 1023-adc_code，使模拟输入和
//   模拟输出保持同极性。若实测硬件不需要补偿，可将参数设为 0 后重新综合。
//
// 握手时序：
//   adc_capture 的 out_valid 在启动屏蔽结束后持续为高，并直接连接 dac_output
//   的 in_valid。dac_output 在每个 30 MHz 上升沿接收数据、下降沿更新 GPIO，
//   下一上升沿由 DAC 锁存；链路无反压，满吞吐率为每通道每周期一个样本。
//
// 参数说明：
//   ADC_STARTUP_CYCLES 为复位释放后的 ADC 数据屏蔽周期数，必须大于等于 1。
//   COMPENSATE_DAC_INVERSION 为 1 时执行 10 位满量程反码以补偿 DA 模拟反相。
//
// 输出有效与延迟：
//   复位期间 ADC 数据总线关闭、DAC 输出中间码 512。启动屏蔽结束后，ADC 输入
//   先寄存一次，DAC 再在有效上升沿接收并于下降沿输出，因此数字链路具有一个
//   完整 30 MHz 周期加半周期以内的接口流水延迟，具体模拟延迟还包括转换器延迟。
//
// 错误行为：
//   本顶层没有过量程、掉钟或接线错误检测。AD 转接板未向此接口提供 OTR，输入
//   超量程时只能通过 ILA 或外部仪器判断。DAC 不接受数据时保持最近一次输出码。
//
// Vivado 使用：
//   可在仓库 work 中运行 fpga/scripts/sim_top_adc_dac_loopback.tcl 做行为仿真，
//   再运行 fpga/scripts/build_top_adc_dac_loopback.tcl 完成综合、实现和时序检查。
//
// 上板测试与预期现象：
//   先用 1 kHz、小幅度正弦波分别输入两路 ADC；对应 DAC 通道应输出同频、同相
//   的阶梯波，幅值受模块增益调整影响。随后使用直流中点和接近正负满量程的安全
//   电平检查 D0~D9 位序。禁止在未确认量程、共地和 Bank 34 电压前连接模拟源。
//
// 使用限制：
//   仅适用于 Mizar Z7020（xc7z020clg400-2）、当前两块照片所示转接板及 3.3 V
//   数字接口。更换转接板、调整 Bank 34 电压或提高时钟后必须重新检查 XDC、
//   电气兼容性、输入输出延迟及时序裕量。
// ============================================================================

module top_adc_dac_loopback #(
    parameter int unsigned ADC_STARTUP_CYCLES = 6, // ADC 解除复位后的数据屏蔽周期数，必须大于等于 1
    parameter bit COMPENSATE_DAC_INVERSION = 1'b1  // 为 1 时执行 1023-adc_code，补偿 DA 模拟输出反相
) (
    input  wire  logic       clk_50m,     // 板载 PL 50 MHz 时钟输入，连接 H16
    input  wire  logic       rst_n,       // PL_KEY1 低有效人工复位，连接 R19

    input  wire  logic [9:0] adc_data_a,  // AD 通道 1 并行输入，无符号直二进制，D9 为最高位
    input  wire  logic [9:0] adc_data_b,  // AD 通道 2 并行输入，无符号直二进制，D9 为最高位
    output wire  logic       adc_clk_a,   // AD 通道 1 转发时钟，30 MHz
    output wire  logic       adc_clk_b,   // AD 通道 2 转发时钟，30 MHz
    output wire  logic       adc_oe_a,    // AD 通道 1 输出允许，高电平关闭 ADC 数据输出
    output wire  logic       adc_oe_b,    // AD 通道 2 输出允许，高电平关闭 ADC 数据输出

    output       logic [9:0] dac_data_a,  // DA 通道 1 并行输出，无符号直二进制，D9 为最高位
    output       logic [9:0] dac_data_b,  // DA 通道 2 并行输出，无符号直二进制，D9 为最高位
    output wire  logic       dac_clk_a,   // DA 通道 1 转发时钟，30 MHz
    output wire  logic       dac_clk_b    // DA 通道 2 转发时钟，30 MHz
);

    logic       clk_100m_unused;
    logic       clk_sample;
    logic       clk_adc_drive;
    logic       rst_100m_unused;
    logic       rst_sample;
    logic       clock_locked_unused;
    logic [9:0] adc_sample_a;
    logic [9:0] adc_sample_b;
    logic       adc_valid;
    logic [9:0] dac_input_a;
    logic [9:0] dac_input_b;
    logic       dac_ready_unused;

    initial begin
        assert (ADC_STARTUP_CYCLES >= 1)
            else $fatal(1, "ADC_STARTUP_CYCLES 必须大于等于 1");
    end

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

    // 10 位逐位取反严格等价于 1023-adc_code，不引入额外位宽或舍入误差。
    always_comb begin
        if (COMPENSATE_DAC_INVERSION) begin
            dac_input_a = ~adc_sample_a;
            dac_input_b = ~adc_sample_b;
        end else begin
            dac_input_a = adc_sample_a;
            dac_input_b = adc_sample_b;
        end
    end

    dac_output #(
        .RESET_CODE(10'd512)
    ) u_dac_output (
        .clk       (clk_sample),
        .rst       (rst_sample),
        .data_a    (dac_input_a),
        .data_b    (dac_input_b),
        .in_valid  (adc_valid),
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
// 1. 现象/位置：DA 板模拟输出极性与数字输入码反向。
//    原因：现有 dac_output 说明中的板级模拟放大级为反相结构。
//    影响：ADC 码直接送入 DAC 时，模拟输出相对输入反相。
//    解决方法：默认对 10 位 ADC 码逐位取反；保留参数供实测后关闭。
//    当前状态：数字逻辑已解决，模拟极性仍需上板示波器验证。
// 2. 现象/位置：JP1/DA 信号全部位于电压可调的 Bank 34。
//    原因：Mizar Z7 允许通过 R208/R209/R210 将 Bank 34 配成不同电压。
//    影响：硬件电压若不是 3.3 V，LVCMOS33 约束可能导致接口异常甚至器件损坏。
//    解决方法：上电前确认只贴装 R208；XDC 按手册出厂默认值使用 LVCMOS33。
//    当前状态：待人工检查开发板电阻配置。
// 3. 现象/位置：AD 转接板接口没有向 FPGA 提供两路 OTR 过量程状态。
//    原因：当前 40 针转接板仅将数据、CLK 和 OE 接入 JP2。
//    影响：逻辑无法自动识别模拟输入过量程，削顶可能被误认为正常数据。
//    解决方法：上板测试限制输入量程，并用示波器或 ILA 检查削顶。
//    当前状态：接口限制，待上板验证。
// 4. 现象/位置：ADC/DAC 外部时序使用现有模块记录的器件延迟参数。
//    原因：仓库中没有两块转换模块的完整原理图和实测板级延迟数据。
//    影响：静态时序通过不能完全替代接口眼图和上板稳定性测试。
//    解决方法：XDC 按 ADC 最大 25 ns 时钟到输出、DAC 建立 2 ns/保持 1.5 ns
//    建模；上板后用 ILA/示波器确认，并按实测结果收紧约束。
//    当前状态：待上板验证。
// 5. 现象/位置：原时钟树的 ADC 驱动时钟延后 45° 时，布局布线后 ADC 输入建立
//    时间最差裕量为 -1.974 ns。
//    原因：理论外部有效窗口未计入 ODDR/OBUF、IBUF、布线和时钟不确定度。
//    影响：硬件可能在 PVT 极限条件下偶发采到跳变中的 ADC 数据。
//    解决方法：将 ADC 驱动时钟改为与捕获时钟同相，并将输入寄存器约束进 IOB；
//    外部 ADC 在本捕获沿后启动转换，数据由下一捕获沿接收。
//    当前状态：已解决；实现后最差 ADC 输入建立裕量为 2.773 ns，仍需上板确认。
// 6. 现象/位置：PL-only 顶层的 Vivado DRC 报告包含 ZPS7-1 Warning。
//    原因：本测试顶层不实例化 Processing System 7，而 Vivado 建议 Zynq 设计使用
//    PS7 配置默认 PS 状态。
//    影响：不影响本次 PL 管脚布局、布线和 bitstream 生成，但不是完整 PS 启动平台。
//    解决方法：本链路测试通过 JTAG 配置 PL；未来 PS/BRAM 顶层再加入 PS7 Block Design。
//    当前状态：当前任务保留并已说明，不应将此 bitstream 当作 PS 软件平台。

`timescale 1ns/1ps
`default_nettype none

`include "params.vh"

// ============================================================================
// 模块名称：top_ps_dds
//
// 主要功能：
//   Mizar Z7 当前完整板级顶层。实例化 PS—AXI—三 BRAM 子系统，先实现
//   “PS 参数 BRAM -> 参数读取器 -> DDS 频率控制 -> DDS -> 双通道 DAC”链路。
//   IQ BRAM 和 FIR BRAM 的 PL 端口保留为内部连接点，当前安全禁用，不占用管脚。
//
// 使用方法：
//   1. 将本模块设为综合顶层并使用 top_ps_dds.xdc。
//   2. 用 fpga/scripts/generate_dds_ip.tcl 生成 DDS IP。
//   3. PS 按参数 BRAM 协议向 0x4002_0000 发布 unsigned Hz 快照。
//   4. 串口屏 TX 接 T10、RX 接 T11，DA 转接板接 JP1/GPIO1。
//
// 连接说明：
//   DDR/FIXED_IO <- Mizar Z7 的 Zynq PS 专用 DDR3/MIO 管脚
//   clk_50m      <- 板载 PL 50 MHz 晶振 H16
//   rst_n        <- PL_KEY1/K4，R19，按下为低
//   hmi_uart_rx  <- 串口屏 TX，T10，3.3 V TTL
//   hmi_uart_tx  -> 串口屏 RX，T11，3.3 V TTL
//   dac_*        -> JP1 上的双通道 DA 转接板
//
// 时钟与复位：
//   clock_tree 从 50 MHz 产生 30 MHz DDS/DAC/BRAM Port B 时钟。PS AXI 和三块
//   BRAM Port A 使用 PS FCLK0 100 MHz。双口 BRAM允许两个端口异步；参数快照的
//   generation/STATUS 前后复核保证跨域数据一致性。rst_n 只复位 PL 数据通路，
//   PS 自身复位由 FIXED_IO 专用管脚管理。
//
// 输入格式：
//   参数 BRAM offset 0x40 保存 unsigned 32-bit Hz；协议头见 dds_param_protocol.vh。
//
// 输出格式：
//   DDS 内部 sine/cosine 为 10 位 signed 二进制补码；顶层转换为 DAC 的 10 位
//   offset-binary。通道A输出 sine，通道B输出 cosine。默认再执行满量程反码，
//   补偿当前 DA 板模拟放大级反相。
//
// 握手时序与吞吐率：
//   新 generation 只触发一次 DDS 配置；DDS稳定后每个30 MHz周期产生一对样本。
//   dac_output 每周期接收，并在下降沿更新数据、下一上升沿由DAC锁存。
//
// 参数说明：
//   PARAM_POLL_CYCLES 是参数轮询间隔；COMPENSATE_DAC_INVERSION 控制模拟极性补偿。
//
// 错误行为：
//   参数协议错误或越界时保持最近一次频率；PS尚未发布时输出默认500 Hz。
//   当前协议错误仅保留在内部信号，后续可连接 ILA 或状态 BRAM。
//
// Vivado 使用与上板预期：
//   运行 fpga/scripts/build_top_ps_dds.tcl 可完成实现、bitstream和固定XSA导出。
//   PS未运行时示波器应看到约500 Hz；PS发布合法频率后，两个DAC通道应切换到
//   对应频率且相差约90°。实际模拟极性、幅值和相位仍需示波器确认。
//
// 使用限制：
//   仅适用于 xc7z020clg400-2、30 MHz DDS配置和当前3.3 V DA/UART硬件。
// ============================================================================
module top_ps_dds #(
    parameter int unsigned PARAM_POLL_CYCLES = 256, // 参数 BRAM 轮询间隔，单位30 MHz周期
    parameter bit COMPENSATE_DAC_INVERSION = 1'b1  // 补偿 DA 模拟输出反相
) (
    inout  wire [14:0] DDR_addr,          // PS DDR3地址总线，专用管脚
    inout  wire [2:0]  DDR_ba,            // PS DDR3 bank地址，专用管脚
    inout  wire        DDR_cas_n,         // PS DDR3 CAS，低有效
    inout  wire        DDR_ck_n,          // PS DDR3差分时钟N
    inout  wire        DDR_ck_p,          // PS DDR3差分时钟P
    inout  wire        DDR_cke,           // PS DDR3时钟使能
    inout  wire        DDR_cs_n,          // PS DDR3片选，低有效
    inout  wire [3:0]  DDR_dm,            // PS DDR3数据掩码
    inout  wire [31:0] DDR_dq,            // PS DDR3双向数据
    inout  wire [3:0]  DDR_dqs_n,         // PS DDR3差分数据选通N
    inout  wire [3:0]  DDR_dqs_p,         // PS DDR3差分数据选通P
    inout  wire        DDR_odt,           // PS DDR3片上终端控制
    inout  wire        DDR_ras_n,         // PS DDR3 RAS，低有效
    inout  wire        DDR_reset_n,       // PS DDR3复位，低有效
    inout  wire        DDR_we_n,          // PS DDR3写使能，低有效
    inout  wire        FIXED_IO_ddr_vrn,  // PS DDR参考电阻N
    inout  wire        FIXED_IO_ddr_vrp,  // PS DDR参考电阻P
    inout  wire [53:0] FIXED_IO_mio,      // PS MIO专用管脚
    inout  wire        FIXED_IO_ps_clk,   // PS参考时钟
    inout  wire        FIXED_IO_ps_porb,  // PS上电复位，低有效
    inout  wire        FIXED_IO_ps_srstb, // PS系统复位，低有效

    input  wire logic       clk_50m,      // 板载PL 50 MHz时钟，H16
    input  wire logic       rst_n,        // PL_KEY1低有效复位，R19
    input  wire logic       hmi_uart_rx,  // PS UART1 RX，串口屏TX接T10
    output wire logic       hmi_uart_tx,  // PS UART1 TX，串口屏RX接T11

    output      logic [9:0] dac_data_a,   // DA通道A offset-binary数据，sine
    output      logic [9:0] dac_data_b,   // DA通道B offset-binary数据，cosine
    output wire logic       dac_clk_a,    // DA通道A 30 MHz转发时钟
    output wire logic       dac_clk_b     // DA通道B 30 MHz转发时钟
);

    logic clk_100m_unused;
    logic clk_sample;
    logic clk_adc_unused;
    logic rst_100m_unused;
    logic rst_sample;
    logic clock_locked_unused;

    // IQ BRAM内部扩展点：后续 IQ 模块替换这些安全默认驱动，不得提升为板级端口。
    logic        iq_wr_en;
    logic [31:0] iq_wr_addr;
    logic [3:0]  iq_wr_strb;
    logic [31:0] iq_wr_data;

    // FIR BRAM内部扩展点：后续 fir_coef_loader 驱动读使能和地址并使用返回数据。
    logic        fir_rd_en;
    logic [31:0] fir_rd_addr;
    logic [31:0] fir_rd_data;

    logic        param_rd_en;
    logic [31:0] param_rd_addr;
    logic [31:0] param_rd_data;
    logic [31:0] dds_freq_hz;
    logic        dds_freq_we;
    logic [31:0] active_generation_unused;
    logic        param_protocol_error_unused;
    logic        dds_cfg_valid;
    logic [31:0] dds_cfg_data;
    logic [`DDS_PHASE_W-1:0] dds_phase_inc_unused;
    logic        dds_valid;
    logic signed [`BOARD_DATA_W-1:0] dds_sine;
    logic signed [`BOARD_DATA_W-1:0] dds_cosine;
    logic        dds_phase_valid_unused;
    logic [31:0] dds_phase_data_unused;
    logic [9:0]  sine_offset;
    logic [9:0]  cosine_offset;
    logic [9:0]  dac_input_a;
    logic [9:0]  dac_input_b;
    logic        dac_ready_unused;

    assign iq_wr_en   = 1'b0;
    assign iq_wr_addr = 32'd0;
    assign iq_wr_strb = 4'd0;
    assign iq_wr_data = 32'd0;
    assign fir_rd_en   = 1'b0;
    assign fir_rd_addr = 32'd0;

    clock_tree u_clock_tree (
        .clk_50m    (clk_50m),
        .rst_n      (rst_n),
        .clk_100m   (clk_100m_unused),
        .clk_30m    (clk_sample),
        .clk_30m_adc(clk_adc_unused),
        .rst_100m   (rst_100m_unused),
        .rst_30m    (rst_sample),
        .locked     (clock_locked_unused)
    );

    ps_bram_subsystem_wrapper u_ps_bram_subsystem (
        .DDR_addr          (DDR_addr),
        .DDR_ba            (DDR_ba),
        .DDR_cas_n         (DDR_cas_n),
        .DDR_ck_n          (DDR_ck_n),
        .DDR_ck_p          (DDR_ck_p),
        .DDR_cke           (DDR_cke),
        .DDR_cs_n          (DDR_cs_n),
        .DDR_dm            (DDR_dm),
        .DDR_dq            (DDR_dq),
        .DDR_dqs_n         (DDR_dqs_n),
        .DDR_dqs_p         (DDR_dqs_p),
        .DDR_odt           (DDR_odt),
        .DDR_ras_n         (DDR_ras_n),
        .DDR_reset_n       (DDR_reset_n),
        .DDR_we_n          (DDR_we_n),
        .FIXED_IO_ddr_vrn  (FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp  (FIXED_IO_ddr_vrp),
        .FIXED_IO_mio      (FIXED_IO_mio),
        .FIXED_IO_ps_clk   (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb  (FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb),
        .hmi_uart_rx       (hmi_uart_rx),
        .hmi_uart_tx       (hmi_uart_tx),
        .iq_pl_clk         (clk_sample),
        // BRAM端口复位不清存储内容且会引入RAMB异步控制警告；业务控制器自行复位。
        .iq_pl_rst         (1'b0),
        .iq_pl_en          (iq_wr_en),
        .iq_pl_addr        (iq_wr_addr),
        .iq_pl_we          (iq_wr_strb),
        .iq_pl_wdata       (iq_wr_data),
        .fir_pl_clk        (clk_sample),
        .fir_pl_rst        (1'b0),
        .fir_pl_en         (fir_rd_en),
        .fir_pl_addr       (fir_rd_addr),
        .fir_pl_rdata      (fir_rd_data),
        .param_pl_clk      (clk_sample),
        .param_pl_rst      (1'b0),
        .param_pl_en       (param_rd_en),
        .param_pl_addr     (param_rd_addr),
        .param_pl_rdata    (param_rd_data)
    );

    dds_param_reader #(
        .POLL_CYCLES(PARAM_POLL_CYCLES)
    ) u_dds_param_reader (
        .clk              (clk_sample),
        .rst_n            (~rst_sample),
        .bram_en          (param_rd_en),
        .bram_addr        (param_rd_addr),
        .bram_rdata       (param_rd_data),
        .dds_freq_hz      (dds_freq_hz),
        .dds_freq_we      (dds_freq_we),
        .active_generation(active_generation_unused),
        .protocol_error   (param_protocol_error_unused)
    );

    dds_freq_ctrl u_dds_freq_ctrl (
        .clk           (clk_sample),
        .rst_n         (~rst_sample),
        .dds_freq_hz   (dds_freq_hz),
        .dds_freq_we   (dds_freq_we),
        .dds_cfg_tvalid(dds_cfg_valid),
        .dds_cfg_tdata (dds_cfg_data),
        .dds_phase_inc (dds_phase_inc_unused)
    );

    dds_wrapper u_dds_wrapper (
        .clk             (clk_sample),
        .rst_n           (~rst_sample),
        .dds_cfg_tvalid  (dds_cfg_valid),
        .dds_cfg_tdata   (dds_cfg_data),
        .dds_valid       (dds_valid),
        .dds_sine_data   (dds_sine),
        .dds_cosine_data (dds_cosine),
        .dds_phase_valid (dds_phase_valid_unused),
        .dds_phase_data  (dds_phase_data_unused)
    );

    // 二进制补码到 offset-binary 只需翻转符号位；可选反码补偿 DA 模拟反相。
    always_comb begin
        sine_offset   = $unsigned(dds_sine)   ^ 10'h200;
        cosine_offset = $unsigned(dds_cosine) ^ 10'h200;
        if (COMPENSATE_DAC_INVERSION) begin
            dac_input_a = ~sine_offset;
            dac_input_b = ~cosine_offset;
        end else begin
            dac_input_a = sine_offset;
            dac_input_b = cosine_offset;
        end
    end

    dac_output #(
        .RESET_CODE(10'd512)
    ) u_dac_output (
        .clk       (clk_sample),
        .rst       (rst_sample),
        .data_a    (dac_input_a),
        .data_b    (dac_input_b),
        .in_valid  (dds_valid),
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
// 1. 现象：旧wrapper单独实现时144个BRAM内部信号被当作I/O，Place失败。
//    原因：三组PL侧BRAM端口位于当时的板级顶层。
//    影响：普通I/O资源超限，且这些信号本来就不应连接封装管脚。
//    解决方法：本顶层在内部连接或安全禁用三组端口，只保留真实板级接口。
//    当前状态：RTL已解决，需以本顶层重新实现确认。
// 2. 现象：参数BRAM的PS写时钟和PL读时钟异步。
//    原因：Port A使用100 MHz FCLK0，Port B使用30 MHz DDS时钟。
//    影响：发布过程中可能读取到跨代数据。
//    解决方法：reader前后复核generation和STATUS，撕裂快照整轮丢弃。
//    当前状态：已设计并由独立testbench验证，仍需上板快速更新压力测试。
// 3. 现象：IQ和FIR业务模块尚未接入。
//    原因：当前阶段只要求先实现DDS链路。
//    影响：IQ BRAM不会产生测量数据，FIR BRAM内容暂不被PL消费。
//    解决方法：保留iq_wr_*和fir_rd_*内部连接点，后续由对应模块替换安全默认驱动。
//    当前状态：按阶段计划保留。
// 4. 现象：DA模拟输出极性和绝对幅值依赖转接板模拟链路。
//    原因：DA板后级为反相结构，且实际增益需要硬件标定。
//    影响：数字相位正确时，模拟输出仍可能表现为反相或幅值偏差。
//    解决方法：默认执行满量程反码补偿，并保留参数；用示波器确认后决定是否关闭。
//    当前状态：待上板验证。
// 5. 现象：Block Memory Generator的Port B复位输入直接进入RAMB异步复位脚。
//    原因：clock_tree域复位采用异步置位、同步释放，直接连接会触发REQP-1839。
//    影响：复位附近的BRAM输出值不参与默认时序分析；该复位本身也不会清空存储器。
//    解决方法：三组BRAM Port B复位固定无效，各PL读写控制模块独立同步复位并在
//    复位期间关闭en/we；reader恢复后重新按generation/STATUS取得有效快照。
//    当前状态：RTL已解决，已通过实现DRC复核。

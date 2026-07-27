/*
 * 文件: params.vh
 * 用法:
 *   本文件集中定义 ADDA/DDS/HMI/模式控制相关的全局宏，供 PL RTL 模块
 *   通过 `include "params.vh"` 引用。修改这里的宏会影响多个模块，交接
 *   时应优先确认采样时钟、数据位宽、DDS 频率范围和 HMI 控件编号是否与
 *   Block Design、DDS IP、PS 软件以及串口屏工程保持一致。
 *
 * 连接关系:
 *   - SAMPLE_CLK_HZ/DDS_* 宏主要被 dds_freq_ctrl、dds_wrapper、sweep_ctrl
 *     和 sweep_iq_demod 使用。
 *   - HMI_* 宏需要与串口屏页面/控件 ID 以及 PS 侧解析代码保持一致。
 *   - MODE_* 宏需要与 ctrl_reg_bank、mode_router、PS/HMI 模式枚举保持一致。
 *
 * 约束:
 *   - SAMPLE_CLK_HZ 必须等于 DDS、ADC/DA 数据通路和扫频/IQ 模块所在时钟域。
 *   - BOARD_DATA_W 必须匹配板级 AD/DA 有效数据位宽。
 *   - DDS_OUTPUT_W 必须匹配 DDS IP 输出 waveform 每路位宽。
 *   - DDS_PHASE_W 必须匹配 DDS IP 配置相位增量宽度。
 *   - 修改 HMI 页面/控件 ID 后，PS 侧和串口屏工程必须同步更新。
 */

// PL 采样/DDS 主时钟频率，单位 Hz；用于 DDS 相位增量计算和扫频时序估算。
`define SAMPLE_CLK_HZ      30_000_000
// 板级 AD/DA 数据通路有效位宽。
`define BOARD_DATA_W       10
// DDS Compiler 配置 AXIS 数据宽度。
`define DDS_CONFIG_W       32
// DDS 相位增量有效位宽；必须与 DDS IP 配置一致。
`define DDS_PHASE_W        27
// DDS IP 每路 sine/cosine 原始输出位宽。
`define DDS_OUTPUT_W       8
// 串口屏 UART 波特率；需要与 HMI 屏幕工程和 PS/PL UART 配置一致。
`define HMI_UART_BPS       9600

// 串口屏页面 ID；PS/HMI 解析事件时用来过滤当前页面。
`define HMI_PAGE_ID        8'd1
// 串口屏手动模式控件 ID。
`define HMI_MANUAL_COMP_ID 8'd1
// 串口屏自动/扫频模式控件 ID。
`define HMI_AUTO_COMP_ID   8'd2
// 串口屏频率输入/显示控件 ID。
`define HMI_FREQ_COMP_ID   8'd3
// 串口屏 Vpp 幅度输入/显示控件 ID。
`define HMI_VPP_COMP_ID    8'd4
// 串口屏启动按钮控件 ID。
`define HMI_START_COMP_ID  8'd5

// ADDA 直通模式：ADC 数据直接进入 DAC/后级通路。
`define MODE_ADDA_BYPASS   2'd0
// DDS 手动模式：PS/HMI 直接设置 DDS 频率/幅度。
`define MODE_DDS_MANUAL    2'd1
// 已知信号/自动模式：保留给自动测试或预设流程。
`define MODE_KNOWN_AUTO    2'd2
// FIR 仿真/滤波模式：使用 FIR/下变频等处理链路。
`define MODE_FIR_SIM       2'd3

// DDS 允许的最小输出频率，单位 Hz；dds_freq_ctrl 会对输入频率做下限钳位。
`define DDS_FREQ_MIN_HZ    32'd100
// DDS 允许的最大输出频率，单位 Hz；需要小于采样率 Nyquist 且符合系统需求。
`define DDS_FREQ_MAX_HZ    32'd1_000_000
// 复位后 DDS 默认输出频率，单位 Hz。
`define DDS_FREQ_DFLT_HZ   32'd1_000

// DAC 满量程参考 Vpp，单位 mV；幅度缩放模块用作标定基准。
`define DAC_FS_VPP_DFLT_MV 32'd3000
// 手动模式默认输出幅度，单位 mV。
`define MANUAL_VPP_DFLT_MV 32'd3000
// 自动/扫频模式默认输出幅度，单位 mV。
`define AUTO_VPP_DFLT_MV   32'd2000

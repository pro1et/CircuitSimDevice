# HMI Mode0—PS UART1—参数 BRAM—DDS 实施计划

## 1. 目标与本阶段边界

本计划依据 `fpga/doc/HMI逻辑.txt`、当前 `ps_bram_subsystem_bd`、参数 BRAM 接口、`params.vh` 和 `dds_freq_ctrl.v` 制定。目标链路为：

```text
串口屏
  │  UART 115200 bit/s，8N1；屏幕5 V供电、3.3 V TTL
  ▼
PS UART1（经 EMIO 穿过 PL 管脚）
  │  解析 Mode0、步长选择、加/减命令
  ▼
PS 运行时状态 target_freq_hz
  │  AXI，STATUS/GENERATION 快照发布
  ▼
参数 BRAM，0x4002_0000
  │  独立 30 MHz Port B
  ▼
dds_param_reader
  │  dds_freq_hz + 单周期 dds_freq_we
  ▼
dds_freq_ctrl → dds_wrapper → DAC
```

本阶段只实现 HMI 所称的 Mode0。Mode1、Mode2 命令可以被解析器识别并记录日志，但不得改变参数 BRAM 或 DDS。

### 1.1 “频率控制字”的定义

参数 BRAM 中保存的是 **32-bit unsigned 目标频率，单位 Hz**，不是 DDS phase increment。当前 `dds_freq_ctrl` 已统一执行：

```text
phase_inc = round(freq_hz × 2^PHASE_W / SAMPLE_CLK_HZ)
```

保持 Hz 作为 PS–PL 接口可以避免 PS 重复依赖 `SAMPLE_CLK_HZ=30 MHz` 和 `PHASE_W=27`，以后 DDS IP 参数改变时也不需要修改 HMI 软件协议。

### 1.2 已冻结约定

- HMI 文档规定进入 Mode0 默认输出500 Hz、默认步长100 Hz。
- PL的 `DDS_FREQ_DFLT_HZ` 统一改为500 Hz，避免 PS首次发布前出现1000 Hz的瞬态默认值。
- HMI名称“Mode0”只属于 PS/HMI命令解析，不作为 PL模式编码，也不写入参数 BRAM。
- 串口屏波特率固定为115200 bit/s，格式为8N1。
- 串口屏使用5 V供电，但 UART信号电平为3.3 V TTL，可以连接3.3 V PL I/O；双方必须共地。

## 2. HMI Mode0 命令表

串口屏事件帧固定为 7 bytes：4-byte 事件内容后跟 `FF FF FF`。PS 必须按完整帧匹配，不能只根据某一个 component ID 判断。

| 完整帧（hex） | 动作 |
| --- | --- |
| `65 01 01 00 FF FF FF` | 进入 Mode0；频率500 Hz、步长100 Hz，并发布一次频率参数 |
| `65 03 08 01 FF FF FF` | 步长改为 100 Hz，不更新 DDS |
| `65 03 09 01 FF FF FF` | 步长改为 1 kHz，不更新 DDS |
| `65 03 0A 01 FF FF FF` | 步长改为 10 kHz，不更新 DDS |
| `65 03 0B 01 FF FF FF` | 步长改为 100 kHz，不更新 DDS |
| `65 03 06 00 FF FF FF` | 当前频率加一个步长，成功后发布 |
| `65 03 07 00 FF FF FF` | 当前频率减一个步长，成功后发布 |

频率范围先与 PL 保持一致：100 Hz～1,000,000 Hz。加减采用饱和策略，不允许 unsigned 下溢或上溢。每次成功修改后，PS 发送 ASCII：

```text
Frequency.t0.txt="500"
```

随后追加三个结束 byte `FF FF FF`。数字部分不包含 `Hz`，除非串口屏工程后续明确要求。

串口屏注释中的 GB2312 问题只影响中文字符串；上述命令名和十进制数字都是 ASCII，不需要编码转换。

## 3. 阶段 A：配置 Processing System 和 wrapper

### 3.1 PS7 IP 配置

在 `build_ps_bram_subsystem.tcl` 中保持现有 DDR、`M_AXI_GP0`、FCLK0、三 BRAM 和全部地址不变，只增加：

1. 启用 PS UART1。
2. 将 UART1 I/O route 设置为 `EMIO`，不占用 PS MIO48/49。
3. 只启用 TX/RX，不启用 RTS/CTS 全调制解调器接口。
4. UART1 软件目标波特率固定为115200 bit/s；由 Vitis 中 `XUartPs_SetBaudRate()` 设置并检查返回值。
5. 将 PS7 的 UART1 EMIO 接口外部化到 BD 边界。

Vivado 2022.2 预期使用的关键属性是：

```tcl
CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1}
CONFIG.PCW_UART1_UART1_IO          {EMIO}
```

实施时先通过 `list_property/get_property` 核对本机 PS7 IP 的准确属性名，再写入正式构建脚本，禁止仅凭字符串假设。

### 3.2 wrapper 端口

稳定 wrapper 增加两个角色清晰的端口：

```systemverilog
input  wire hmi_uart_rx; // 串口屏TX → FPGA管脚 → PS UART1 RX
output wire hmi_uart_tx; // PS UART1 TX → FPGA管脚 → 串口屏RX
```

这两个端口是实际 PL I/O，方向和封装管脚已经冻结：串口屏TX接FPGA T10，即 `hmi_uart_rx`；串口屏RX接FPGA T11，即 `hmi_uart_tx`。

已确认的电气条件和接线规则：

- 串口屏为5 V供电、3.3 V TTL UART；PL端使用 `LVCMOS33`。
- 仍应在首次连接前用万用表/示波器确认空闲高电平约为3.3 V，而不是5 V。
- TX/RX 交叉连接并共地。
- T11/T10当前没有出现在 ADC–FIR–DAC XDC 中，与现有管脚分配无冲突。

XDC 至少设置 `PACKAGE_PIN` 和 `LVCMOS33`；UART 是异步接口，不为 RX 创建虚假的同步输入时钟。固定约束为：

```tcl
set_property PACKAGE_PIN T10 [get_ports hmi_uart_rx]
set_property PACKAGE_PIN T11 [get_ports hmi_uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports {hmi_uart_rx hmi_uart_tx}]
```

### 3.3 阶段 A 验收

1. Vivado 2022.2 执行 BD Validate，无 error/critical warning。
2. Address Editor 三段地址完全不变，参数 BRAM仍为 `0x4002_0000–0x4002_0FFF`。
3. 自动 wrapper 和稳定 wrapper 都出现方向正确的 UART RX/TX。
4. 综合通过，并用 `report_io` 确认最终顶层 UART 管脚与 IOSTANDARD。
5. 重新导出 fixed XSA；Vitis 更新 Platform/BSP 后应生成 UART1 对应的 `XPAR_XUARTPS_1_*` 定义。
6. 先做物理回环：临时短接 HMI TX/RX 或用 USB-UART，确认 PS UART1 经 EMIO 能收发115200 8N1；没有通过回环前不进入 BRAM 联调。

### 3.4 阶段 A 实施结果

阶段 A 已完成工具侧实现和验证：

- Vivado 2022.2已确认并应用 `UART1=Enable`、`UART1 I/O=EMIO`，BD导出 `UART_1`。
- 稳定 wrapper已导出 `hmi_uart_rx` 和 `hmi_uart_tx`，自动 wrapper对应端口为 `HMI_UART_rxd/txd`。
- XDC已固定 `hmi_uart_rx=T10`、`hmi_uart_tx=T11`、`LVCMOS33`；Vivado `report_io`确认两者位于 Bank 34，TX为 DRIVE 8/SLEW SLOW。
- 三段 BRAM地址未改变；BD Validate和稳定 wrapper综合通过，综合结果为0 error、0 critical warning。
- fixed XSA已重新导出，HWH中包含 `UART_1`、`UART1_RX` 和 `UART1_TX`。

尚不能由自动化环境代替的硬件验收只有两项：确认实板 Bank 34供电为3.3 V，以及使用串口屏或 USB-UART完成115200 8N1物理回环。Vitis Platform/BSP将在建立 PS软件工程时由新 XSA更新并检查 `XPAR_XUARTPS_1_*`。

## 4. 阶段 B：PS 保存和修改 Mode0 频率

### 4.1 PS 运行时状态

新增一个单写者状态结构，保存在 PS DDR/OCM 普通变量中：

```c
typedef struct {
    uint32_t hmi_mode;        /* 仅供PS解析/界面状态使用，不发布到PL */
    uint32_t target_freq_hz;  /* 当前目标频率，默认500 */
    uint32_t step_hz;         /* 100/1000/10000/100000，仅PS使用 */
    uint32_t generation;      /* 每次成功发布递增 */
} hmi_control_state_t;
```

这里的“保存”只指本次上电运行期间保存，不默认写入 QSPI/SD。若以后要求掉电保持最后频率，应另立非易失存储需求，不能在每次按键时直接擦写 Flash。

### 4.2 UART接收与解析

首版采用 `XUartPs` 驱动和非阻塞主循环解析即可满足115200 bit/s；解析器必须是逐 byte状态机，并处理：

- 一帧被拆成多次接收；
- 多帧一次到达；
- 噪声 byte 后重新寻找 `0x65`；
- 结束符不足三个；
- 未知 page/component/event；
- Mode1/Mode2 当前只记录，不发布。

不要在收到半帧时修改频率，也不要把串口接收 ISR 写成直接访问 BRAM 的长临界区。如果以后采用中断方式，ISR 只把 byte 放入 ring buffer，协议解析和 BRAM 发布仍在主循环完成。

### 4.3 状态更新顺序

1. 接收并验证完整帧。
2. 根据命令计算候选频率，执行 100～1,000,000 Hz 范围检查。
3. 更新 PS 状态结构。
4. 调用单一函数 `param_bram_publish_mode0()` 发布快照。
5. 发布成功后再向屏幕发送 `Frequency.t0.txt="N"`。

这样显示值只反映已经提交给 PL 的值。步长选择只更新 `step_hz`，不增加 generation，也不触发 DDS 重配。

### 4.4 阶段 B 验收

1. 在 PC 单元测试中喂入上述全部 hex 帧，逐项检查 mode、frequency、step 和“是否应发布”。
2. 测试拆帧、连帧、错误结束符、随机噪声和未知命令。
3. 测试 100 Hz 下继续减、1 MHz 上继续加以及大步长接近边界，不出现 wrap-around。
4. UART 日志打印接收帧、解析动作、旧值、新值和 generation。
5. 用串口监听器确认返回命令是正确 ASCII，且末尾严格为三个 `FF`。

## 5. 阶段 C：参数 BRAM 地址和数据协议

参数 BRAM 的 AXI 物理范围保持：

```text
BASE = 0x4002_0000
SIZE = 0x1000 bytes = 1024 × 32-bit words
```

沿用现有共享 BRAM 的 16-word header 和字节地址规则。首版 Mode0 参数快照定义如下：

| PS 地址 | BRAM offset | 字段 | 首版值/说明 |
| --- | ---: | --- | --- |
| `0x4002_0000` | `0x00` | `MAGIC` | `0x5041_524D`，ASCII `PARM` |
| `0x4002_0004` | `0x04` | `VERSION` | `0x0001_0000` |
| `0x4002_0008` | `0x08` | `GENERATION` | 每次发布递增，32-bit 回绕允许 |
| `0x4002_000C` | `0x0C` | `STATUS` | 0=BUSY，1=VALID，2=ERROR |
| `0x4002_0010` | `0x10` | `WORD_COUNT` | 首版固定为1 |
| `0x4002_0014` | `0x14` | `FORMAT` | 1=`DDS_FREQ_HZ_U32` |
| `0x4002_0018` | `0x18` | `ERROR_CODE` | 正常为0 |
| `0x4002_001C–003C` | `0x1C–0x3C` | reserved | 写0 |
| `0x4002_0040` | `0x40` | `TARGET_FREQ_HZ` | unsigned 32-bit Hz |

HMI Mode0名称、`hmi_mode` 和 `step_hz` 都是 HMI/PS界面状态，不是 DDS执行参数，因此首版不写入 BRAM。若以后 PL需要模式或步长，应增加新 FORMAT或新协议版本，不能在不修改版本的情况下改变 payload。

### 5.1 PS 发布顺序

PS 使用 `Xil_Out32()` 访问 uncached MMIO，并严格执行：

1. 写 `STATUS=BUSY`。
2. 写 MAGIC、VERSION、WORD_COUNT、FORMAT、ERROR_CODE 和 reserved。
3. 写 payload：TARGET_FREQ_HZ。
4. 写新的 GENERATION。
5. 执行 ARM data memory barrier。
6. 最后写 `STATUS=VALID`。

禁止先写 VALID 再填数据。PS 是参数 BRAM 的唯一写者；PL 不写 STATUS 或 ACK。需要 ACK 时应设计独立单写者字段或寄存器。

### 5.2 阶段 C 验收

1. PS 单元测试使用内存数组替代 MMIO，检查每个 offset、数值和发布顺序。
2. 上板初期允许 PS 在发布后用 `Xil_In32()` 做诊断读回，逐字打印 `0x00–0x44`；产品代码不依赖读回。
3. XSDB/ILA 检查 `STATUS` 最后变为 VALID、generation递增、频率位于 offset `0x40`。
4. 连续快速发布不同频率，确认每次 header 格式不变且地址没有越过4 KiB窗口。
5. 将上述布局补入《PS端共享BRAM访问与STATUS通知协议》，并在 PS header 与 PL `vh` 文件中使用同一组常量和值。

## 6. 阶段 D：PL 参数 BRAM读取模块

### 6.1 模块职责

新增简洁、角色明确的模块：

```text
dds_param_reader.sv
```

它只负责从参数 BRAM取得一个稳定的频率参数快照、校验协议并向 `dds_freq_ctrl` 发出更新。它不解析 UART、不识别 HMI模式、不计算 phase increment，也不直接产生 DDS波形。

建议接口：

```systemverilog
module dds_param_reader #(
    parameter int unsigned POLL_CYCLES = 256
) (
    input  wire        clk,
    input  wire        rst_n,

    output wire        bram_en,
    output wire [31:0] bram_addr,
    input  wire [31:0] bram_rdata,

    output reg  [31:0] dds_freq_hz,
    output reg         dds_freq_we,
    output reg  [31:0] active_generation,
    output reg         protocol_error
);
```

连接关系：

```text
param_pl_clk   ← clk_30m
param_pl_rst   ← rst_30m
param_pl_en    ← dds_param_reader.bram_en
param_pl_addr  ← dds_param_reader.bram_addr
param_pl_rdata → dds_param_reader.bram_rdata

dds_param_reader.dds_freq_hz → dds_freq_ctrl.dds_freq_hz
dds_param_reader.dds_freq_we → dds_freq_ctrl.dds_freq_we
```

当前链路可以直接连接。后续加入扫频后，应在 reader/manual path与 `sweep_ctrl` 之间增加独立的顶层频率 mux或控制仲裁；不要把 HMI Mode编号塞入本参数协议，也不要修改 `dds_freq_ctrl` 来混合模式职责。

### 6.2 读取状态机

参数 BRAM 是同步读，每次改变地址并拉高 `bram_en` 后，状态机至少隔一拍再采样 `bram_rdata`。建议流程：

1. 按可参数化间隔轮询 STATUS。
2. STATUS不是 VALID则等待；ERROR置 `protocol_error`。
3. 读取 generation A。
4. 依次读取 MAGIC、VERSION、WORD_COUNT、FORMAT、TARGET_FREQ_HZ。
5. 再读取 generation B 和 STATUS B。
6. 只有 A=B、最终 STATUS仍为 VALID且 generation不同于 `active_generation` 才接受。
7. 校验 FORMAT=1、WORD_COUNT=1且频率范围合法。
8. 同一拍锁存 `dds_freq_hz`，下一拍产生一个周期的 `dds_freq_we`。
9. 更新 `active_generation`，重复 generation不再次触发。

任何校验失败都保持上一有效频率，不向 DDS 发送错误值。`dds_freq_ctrl` 的钳位继续作为第二层保护，但 reader 不应依赖钳位掩盖协议错误。

BRAM双时钟只解决存储器端口的电气访问；generation/status前后复核负责避免 PS 100 MHz 写入与 PL 30 MHz读取期间得到撕裂快照。

### 6.3 阶段 D 验收

1. 为 `dds_param_reader` 建立独立 testbench和行为 BRAM模型，模拟同步读延迟。
2. 使用不同的 PS发布时钟与30 MHz PL读取时钟，覆盖真实异步访问。
3. 验证合法快照只产生一次 `dds_freq_we`。
4. 验证重复 generation、BUSY、错误 MAGIC/VERSION/FORMAT、非法 mode、越界频率都不更新 DDS。
5. 在读取中途改变 generation或STATUS，reader必须丢弃本次数据并重试。
6. 复位不会清空 BRAM；reader复位释放后应能重新加载当前有效 generation。
7. `dds_freq_we`严格为一个 `clk_30m` 周期，`dds_freq_hz`在脉冲期间稳定。

### 6.4 阶段 D 与首版完整顶层实施结果

阶段 D 已完成，新增 `fpga/src/hdl/dds_param_reader.sv` 和协议常量
`fpga/src/hdl/dds_param_protocol.vh`。自检 testbench 位于
`fpga/src/sim/dds_param_reader_tb.sv`，已覆盖 BUSY、合法快照、重复 generation、
错误 MAGIC、越界频率、错误修复和 reader 复位后重新加载，并在 Vivado 2022.2
XSim 中通过。

首版板级集成顶层为 `fpga/src/testmodule/top_ps_dds.sv`。该顶层内部连接参数 BRAM
reader、`dds_freq_ctrl`、DDS Compiler 和双通道 DAC；DAC A 输出 sine，DAC B 输出
cosine。IQ BRAM 写接口和 FIR BRAM 读接口保留为顶层内部连接点，当前安全禁用，
不会再被 Vivado 误认为外部封装 I/O。后续 IQ/FIR 模块应在该顶层内部替换
`iq_wr_*`/`fir_rd_*` 的默认驱动，不得把这些总线提升为板级端口。

完整工程由 `fpga/scripts/build_top_ps_dds.tcl` 重建。Vivado 2022.2 最终实现结果：
26 个普通 PL I/O、0 Error、0 Critical Warning，WNS=2.271 ns、WHS=0.057 ns；
bitstream 与包含 bitstream 的固定 XSA 均已生成。当前唯一 DRC Warning 为尚未使用的
IQ/FIR BRAM Port B 内部延迟网络无可布线负载，接入对应业务模块后应自然消失。

## 7. 阶段 E：整链路验证

按以下顺序逐级联调，出现失败时停在当前边界，不跨级猜测：

1. **UART物理层**：USB-UART/串口屏发送已知帧，PS打印原始7 bytes。
2. **HMI解析层**：PS日志显示 Mode0、step和目标频率变化，屏幕显示返回值。
3. **AXI/BRAM层**：ILA观察参数 BRAM Port B读取到 MAGIC、generation、mode和Hz值。
4. **PL reader层**：ILA观察一次新 generation对应一次 `dds_freq_we`。
5. **DDS控制层**：ILA同时观察 `dds_freq_hz`、`dds_cfg_tvalid`、`dds_cfg_tdata`和`dds_phase_inc`，并用软件公式核对 phase increment。
6. **DAC输出层**：示波器/频率计检查500 Hz，以及100 Hz、1 kHz、10 kHz、100 kHz步长操作后的输出频率。
7. **持续性测试**：快速连续按键、串口噪声、PS复位、PL复位、generation回绕附近仿真、上下限饱和。

端到端验收判据：每个被接受的加减命令最终只造成一次 DDS配置更新；屏幕显示值、参数 BRAM中的 Hz值、ILA中的 `dds_freq_hz` 和示波器实测频率一致。

## 8. 预计修改文件与实施顺序

建议按以下顺序实施，每一步单独提交并保留验证记录：

1. 修改 `fpga/scripts/build_ps_bram_subsystem.tcl`：UART1 EMIO配置和导出。
2. 修改 `fpga/src/hdl/ps_bram_subsystem_wrapper.sv`：增加 HMI UART端口。
3. 修改最终完整顶层及其 XDC：连接 EMIO UART，固定 `hmi_uart_rx=T10`、`hmi_uart_tx=T11`。
4. 扩展共享参数 BRAM 协议文档，增加 PS/PL 协议常量。
5. 新增 Vitis PS UART/HMI解析和参数发布代码；仓库当前尚无 `vitis/` 目录，需要先确定 Platform/Application目录结构。
6. 新增 `fpga/src/hdl/dds_param_reader.sv` 和独立 testbench。
7. 在完整顶层连接 reader、参数 BRAM和 `dds_freq_ctrl`。
8. 依次完成仿真、BD Validate、综合、实现、CDC/STA、XSA更新和上板测试。

## 9. 已确认条件与剩余确认项

已确认：5 V屏幕供电、3.3 V TTL、115200 8N1、`hmi_uart_rx=T10`、`hmi_uart_tx=T11`、DDS默认500 Hz，以及 HMI Mode0不进入 PL协议。

实施前只需继续确认：

1. 每次重新收到 Mode0启动命令时都重置到500 Hz，还是仅系统首次进入时使用500 Hz；当前计划采用“每次进入都重置”。
2. “保存频率”是否只要求本次上电运行有效；当前计划不包含掉电保存。

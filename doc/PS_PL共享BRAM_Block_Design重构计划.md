# PS–PL 共享 BRAM Block Design 重构计划

更新日期：2026-07-26  
适用器件：XC7Z020-CLG400-2  
目标 Vivado 版本：2025.2

## 实施状态

截至 2026-07-26，基础设施阶段已经完成：

- 新增可重复执行的 `scripts/ps_pl_bram.tcl`，并在 Vivado 2025.2 中连续重建验证；
- `scripts/CircuitSimDevice.tcl` 已切换到 `ps_pl_bram`，不再引用旧 `system`、LED、按键、GPIO、XDC 或 COE；
- 已创建第 7.4 节规定的全部协议源文件与 testbench；
- 两个 XSim 自检均通过，PS 公共协议源通过 Cortex-A9 GCC 的 `-Wall -Wextra -Werror` 编译；
- 旧 `scripts/system.tcl`、LED/按键 RTL 和对应 XDC 已移除；
- 尚未完成的工作是将实际 DDS、采集控制和 FIR 业务 RTL 接入协议模块，以及生成新 bitstream/XSA 并迁移 Vitis 应用。

## 1. 重构目标

废弃当前以 `system`、LED、按键和 AXI GPIO 为中心的设计，建立一个边界清晰、可由 Tcl 重建的 PS–PL 基础平台。

新 Block Design（建议命名为 `ps_pl_bram`）只负责：

- Zynq-7000 Processing System、PS DDR 和 FIXED_IO；
- PS `M_AXI_GP0` 到 PL 存储器的 AXI 访问路径；
- 两个 AXI BRAM Controller；
- 两个 True Dual Port Block Memory Generator；
- AXI 时钟和复位；
- 将两块 BRAM 的第二个原生端口导出到 BD 外部。

DDS、扫频/采集控制、FIR、ADC/DAC 接口和其他业务 RTL 均保持为普通 RTL，不放进 BD，也不封装为 AXI IP。PS 与业务 RTL 不建立模块级直连，双方只通过共享 BRAM 中定义好的数据字和状态字通信。

## 2. 当前工程检查结论

重构前的实际工程为 `work/CircuitSimDevice.xpr`；新的可重建工程位于 `work/CircuitSimDevice/CircuitSimDevice.xpr`，器件是 `xc7z020clg400-2`。版本管理中的工程入口为 `scripts/CircuitSimDevice.tcl`，新 BD 重建脚本为 `scripts/ps_pl_bram.tcl`。

现有 `system` BD 包含：

- `processing_system7_0`；
- 一个 AXI SmartConnect；
- 一个 AXI BRAM Controller 和一个 True Dual Port BRAM；
- AXI GPIO、`LED` module reference、按键/LED 外部端口和 PL 到 PS 中断；
- `proc_sys_reset`；
- 100 MHz `FCLK_CLK0`。

现有地址为：

| 从设备 | PS 地址范围 | 大小 |
| --- | --- | ---: |
| `axi_bram_ctrl_0` | `0x4000_0000–0x4000_7FFF` | 32 KiB |
| `axi_gpio_0` | `0x4120_0000–0x4120_FFFF` | 64 KiB |

需要特别处理的现状问题：

1. `scripts/system.tcl` 中 BRAM 实际参数是 32-bit × 8192，而 `doc/CircuitSimDevice_当前现状报告.md` 描述为 64-bit × 4096。二者容量相同，但原生端口宽度、地址步进和数据打包不同。新架构统一采用 32-bit word，并在接口文档中固定下来。
2. 当前 BRAM 仅有 Port A 接 AXI BRAM Controller，Port B 未导出，尚不能供仓库中的普通 RTL 使用。
3. 当前 `axi_bram_ctrl_0`、AXI GPIO、LED module reference、按键中断和约束相互耦合，不符合新架构边界。
4. `scripts/CircuitSimDevice.tcl` 仍强制依赖 LED/按键源码、XDC、旧 `system.tcl` 和 BRAM 初始化 COE，必须随新 BD 一起整理。
5. 当前 Vitis 软件依赖 `XPAR_AXI_BRAM_CTRL_0_*`、旧 GPIO/中断平台和旧 XSA；硬件重构后必须重新导出 XSA，并迁移软件符号。

## 3. 目标结构

```text
                           +----------------------+
DDR / FIXED_IO <---------->| Zynq-7000 PS         |
                           | M_AXI_GP0             |
                           +----------+-----------+
                                      |
                               AXI Interconnect
                         +------------+------------+
                         |                         |
                 AXI BRAM Ctrl              AXI BRAM Ctrl
                   (measure)                   (coeff)
                         | Port A                   | Port A
                 +-------+-------+          +------+--------+
PL measurement -->| True Dual    |          | True Dual     |--> PL FIR
writer via Port B  | Port BRAM    |          | Port BRAM     |    reader via Port B
                 +---------------+          +---------------+
                    measurement                  coefficients
```

建议实例命名：

| 类型 | 实例/接口名称 |
| --- | --- |
| Processing System 7 | `ps7` |
| AXI 互连 | `axi_mem_interconnect` |
| 测量 AXI BRAM Controller | `meas_bram_ctrl` |
| 测量 BRAM | `meas_bram` |
| 测量 PL 原生端口 | `MEAS_BRAM_PL` |
| 系数 AXI BRAM Controller | `coeff_bram_ctrl` |
| 系数 BRAM | `coeff_bram` |
| 系数 PL 原生端口 | `COEFF_BRAM_PL` |
| AXI 复位模块 | `rst_ps7_fclk0` |

`proc_sys_reset` 属于基础设施，可以保留在 BD 中。新 BD 不包含 AXI GPIO、LED、按键、中断控制器或任何业务 RTL。

## 4. BRAM 参数与端口约定

### 4.1 建议初始配置

| 属性 | 测量 BRAM | 系数 BRAM |
| --- | ---: | ---: |
| 类型 | True Dual Port RAM | True Dual Port RAM |
| Port A 使用者 | AXI BRAM Controller | AXI BRAM Controller |
| Port B 使用者 | PL 测量结果写入 RTL | PL FIR 系数读取 RTL |
| 数据宽度 | 32 bit | 32 bit |
| 深度 | 8192 words | 1024 words |
| 容量 | 32 KiB | 4 KiB |
| 初始化 | 不使用外部初始化文件，默认内容清零 | 不使用外部初始化文件，默认内容清零 |
| AXI 控制器 ECC | 关闭 | 关闭 |
| AXI 控制器 BRAM 端口数 | 单端口 | 单端口 |

系数 BRAM 的 1024 words 足以容纳当前软件最多 129 taps，并为元数据和后续扩展留出空间。若后续系数格式、通道数或 bank 数发生变化，应先修改共享内存协议，再调整深度。

### 4.2 原生 Port B 导出信号

两个外部 BRAM 接口都应完整导出以下信号，而不是只导出地址和数据：

```text
clk
rst
en
we[3:0]
addr
din[31:0]
dout[31:0]
```

实际 BMG 使用 `Enable_32bit_Address=true` 以匹配 AXI BRAM Controller，因此导出的 `addr[31:0]` 是**字节地址**。协议表中的偏移和 PS 地址同样按 byte 计数；PL package 可以保留 word index 常量，但在驱动原生 BRAM 地址端口时必须执行 `byte_address = word_index << 2`。

Tcl 中优先对 `meas_bram/BRAM_PORTB` 和 `coeff_bram/BRAM_PORTB` 使用 `make_bd_intf_pins_external`，随后将接口分别重命名为 `MEAS_BRAM_PL` 和 `COEFF_BRAM_PL`。顶层普通 RTL 通过一个仓库管理的 HDL top 连接这些接口；不要把业务 RTL作为 module reference 塞回 BD。

Port B 可以使用业务 RTL 自己的时钟，BMG 配置为独立时钟双口模式。若 Port A 与 Port B 不同钟，不能依赖两个时钟域在同一周期观察到相同状态，通信协议必须使用提交顺序和代次号。

### 4.3 访问所有权

为避免双口 RAM 同地址同时写入的不确定行为，固定所有权如下：

| 存储区 | PS | PL |
| --- | --- | --- |
| 测量 BRAM payload | 只读 | 写入 |
| 测量 BRAM header/status | 只读 | 写入 |
| 系数 BRAM payload | 写入 | 只读 |
| 系数 BRAM header/status | 写入 | 只读 |

初版禁止双方同时写同一块 BRAM。若未来确实需要反向确认，不在对方拥有的 header 中回写；应增加独立的确认字区域并明确单写者，或增加单独的小型控制 BRAM。

## 5. PS–PL 共享内存协议

为降低耦合，初版不使用中断，PS 轮询状态字。每块 BRAM 的前 16 个 word（64 bytes）保留为协议头，payload 从偏移 `0x40` 开始。所有字段均为 32-bit little-endian。

所有 `STATUS` 的复位/上电默认值统一为 `BUSY`（编码为零），防止任一端在协议头尚未初始化时误启动。BMG 不加载外部 COE，但 Tcl 必须保证存储器默认填充值为零；PL 测量业务 RTL 复位释放后应主动写入 `STATUS=BUSY`，PS 软件初始化系数 BRAM时也必须先写 `STATUS=BUSY`。接收端不能只检查状态，还必须同时验证 `MAGIC`、`VERSION`、长度/格式和稳定的 `GENERATION`。

主状态使用 `STATUS[1:0]`，并规定为互斥枚举：

| `STATUS[1:0]` | 测量 BRAM | 系数 BRAM |
| ---: | --- | --- |
| `2'b00` | `BUSY`，未完成/不可读取 | `BUSY`，未发布/不可装载 |
| `2'b01` | `DONE`，测量数据有效 | `VALID`，系数有效 |
| `2'b10` | `ERROR` | `ERROR` |
| `2'b11` | 保留，接收端按无效处理 | 保留，接收端按无效处理 |

溢出、截断等附加信息放在 `STATUS[31:8]`，不能改变低两位主状态的含义；`STATUS[7:2]` 暂时保留并置零。这样 BRAM 清零、RTL 复位和 PS 未运行三种情况下都自然表现为 `BUSY`。

### 5.1 测量 BRAM 头部（PL 写、PS 读）

| 偏移 | 字段 | 说明 |
| ---: | --- | --- |
| `0x00` | `MAGIC` | 固定协议标识 |
| `0x04` | `VERSION` | 布局版本 |
| `0x08` | `GENERATION` | 每次完成一批测量后递增 |
| `0x0C` | `STATUS` | 默认 `BUSY=0`；主状态为 `BUSY/DONE/ERROR` |
| `0x10` | `WORD_COUNT` | payload 有效 32-bit word 数 |
| `0x14` | `FORMAT` | IQ/幅相等数据格式编号 |
| `0x18` | `ERROR_CODE` | PL 错误码 |
| `0x1C–0x3C` | reserved | 置零，供后续扩展 |

PL 测量业务 RTL 复位释放和每批测量开始时先写 `STATUS=BUSY`，再写 payload 和长度/格式，最后写新的 `GENERATION` 并将 `STATUS` 更新为 `DONE`。本工程不再提供通用 measurement writer。PS 只有在连续两次读取到相同 `GENERATION` 且状态为 `DONE` 时才消费 payload；读取完成后再次检查 `GENERATION` 和 `STATUS`，任一变化都丢弃本次快照并重读。

### 5.2 系数 BRAM 头部（PS 写、PL 读）

| 偏移 | 字段 | 说明 |
| ---: | --- | --- |
| `0x00` | `MAGIC` | 固定协议标识 |
| `0x04` | `VERSION` | 布局版本 |
| `0x08` | `GENERATION` | 每次发布新系数后递增 |
| `0x0C` | `STATUS` | 默认 `BUSY=0`；主状态为 `BUSY/VALID/ERROR` |
| `0x10` | `TAP_COUNT` | 有效 tap 数 |
| `0x14` | `FORMAT` | 如 Q1.15、Q1.31 或 float32 的编号 |
| `0x18` | `SCALE` | 定点缩放参数或保留字段 |
| `0x1C–0x3C` | reserved | 置零，供后续扩展 |

PS 软件启动和每次发布前先显式写 `STATUS=BUSY`，写 payload 和参数，执行必要的软件内存屏障，再写新的 `GENERATION`，最后写 `STATUS=VALID`。本工程不再提供通用 coefficient loader。PL 业务 RTL 只有发现合法协议头、`VALID` 和新的稳定 `GENERATION` 后才在本地安全边界装载系数；FIR 工作过程中不要直接使用可能被 PS 更新的 BRAM 内容。建议 PL 将一代完整系数复制到 FIR 自己的寄存器/bank 后再切换。读取结束后的 `GENERATION/STATUS` 复查失败时，丢弃 shadow bank 内容且保持当前 FIR 系数不变。

上述协议只定义跨域数据交换，不规定 DDS、扫频状态机或 FIR 内部结构。

## 6. 建议地址映射

| 设备 | 基地址 | 地址窗口 | 说明 |
| --- | ---: | ---: | --- |
| 测量 BRAM | `0x4000_0000` | 32 KiB | 保留现有 BRAM 基地址，降低软件迁移成本 |
| 系数 BRAM | `0x4001_0000` | 4 KiB | 64 KiB 边界分隔，便于识别和扩展 |

地址必须在 Tcl 中显式指定，不依赖 Vivado 自动分配。最终以生成后的 XSA/xparameters 为准，软件不得长期硬编码控制器实例序号；建议新增一个共享协议头文件集中定义基址别名、偏移、状态位、格式和版本。

## 7. Tcl 与工程文件重构方案

### 7.1 新建 BD 重建脚本

新增 `scripts/ps_pl_bram.tcl`，脚本应：

1. 从 `[info script]` 推导仓库根目录，不依赖调用者当前路径。
2. 检查 Vivado 2025.2 和所需 IP VLNV。
3. 使用设计名 `ps_pl_bram`，只管理自己创建的 BD。
4. 支持在空工程中创建 BD；若同名 BD 已存在，则在明确的重建模式下删除并重建，避免重复执行产生重名 cell/port。
5. 创建 PS7，并复用当前工程已经验证过的 DDR、QSPI、SD 和 UART MIO 配置。
6. 开启 `M_AXI_GP0` 和 `FCLK_CLK0=100 MHz`。
7. 创建一个 1×2 AXI Interconnect/SmartConnect、两个 AXI BRAM Controller、两个 BMG 和一个 `proc_sys_reset`。
8. 连接 AXI、时钟和复位，并导出两个 Port B BRAM 接口。
9. 显式配置两块 BRAM 的宽度、深度、独立时钟模式、不使用外部初始化文件且默认内容清零。
10. 显式分配第 6 节中的地址。
11. 执行 `validate_bd_design`、`save_bd_design`，任何关键对象数量不符时立即报错。

脚本中不引用 LED、按键、COE、DDS、FIR 或采集模块。

### 7.2 更新工程重建脚本

修改 `scripts/CircuitSimDevice.tcl`：

- 移除 `LED.v`、`button_debounce.v`、`button_led.xdc`、旧 `system.tcl` 和 `sweep_iq_complete_32.coe` 的强制依赖；
- source `scripts/ps_pl_bram.tcl`；
- 为新 BD 生成 wrapper；
- 后续存在业务 RTL 顶层时，将仓库管理的顶层设为 top，而不是把自动生成的 BD wrapper 直接作为最终 top；
- 所有工程、IP 输出和 wrapper 仍只生成到 `work/`；
- 保持 `src/hdl`、`src/sim`、`src/constrs`、`src/ip` 为版本管理输入。

新设计通过 BD 校验和重复重建后，旧 `scripts/system.tcl` 已删除；仓库现在只有 `ps_pl_bram.tcl` 这一条 BD 重建入口。

### 7.3 顶层 RTL 边界

后续新增仓库管理的普通 RTL top，负责实例化：

- 自动生成的 `ps_pl_bram_wrapper`；
- 直接控制测量 BRAM Port B 的采集/扫频 RTL；
- 直接控制系数 BRAM Port B 的 FIR/配置 RTL；
- DDS、采集控制和 FIR 等业务 RTL。

BD wrapper 的两个 BRAM Port B 直接连接相应的普通业务 RTL。业务 RTL 负责字节地址、写使能、读延迟以及本节定义的 header 协议，但不处理 AXI。

### 7.4 协议代码文件结构

协议实现按以下结构独立于业务 RTL 和应用代码：

```text
src/
├── hdl/
│   └── shared_bram_protocol_pkg.sv
└── sim/

vitis/
└── common/
    ├── shared_bram_protocol.h
    └── shared_bram_protocol.c
```

各文件职责如下：

| 文件 | 职责 |
| --- | --- |
| `shared_bram_protocol_pkg.sv` | PL 侧唯一协议常量定义：word 地址、MAGIC、VERSION、状态枚举、格式和错误码 |
| `shared_bram_protocol.h` | PS 侧 byte offset、常量、结构体、返回码和 API 声明 |
| `shared_bram_protocol.c` | PS 侧 MMIO、内存屏障、测量快照读取和系数发布实现 |

C 与 SystemVerilog 不能直接包含同一个源文件；两份协议常量必须逐项一致，并由业务 RTL testbench/软件测试检查关键常量。通用 writer/loader 已移除，DDS、采集控制和 FIR 按各自需要直接读写 BRAM Port B 并实现提交顺序。

## 8. 实施顺序

### 阶段 A：冻结接口

- 确认统一使用 32-bit BRAM word。
- 确认测量 payload 格式和最大 word 数。
- 确认 FIR 系数格式；建议定点格式，不建议 PL 直接消费 float32。
- 固化 `MAGIC`、协议版本和状态定义；确认两块 BRAM 的零值状态均为 `BUSY`。

### 阶段 B：创建新 BD Tcl

- 实现 `scripts/ps_pl_bram.tcl`。
- 在 `work/` 中新建干净工程并连续执行重建两次，确认可重复性。
- 检查 BD cell、接口和地址表，不修改 `.bd` 文件。

### 阶段 C：重构工程入口

- 更新 `scripts/CircuitSimDevice.tcl` 和顶层选择。
- 从工程入口移除 LED、按键、GPIO、中断和旧 COE。
- 清理不再使用的约束引用，但在新平台验证前不直接删除历史源文件。

### 阶段 D：增加业务 RTL 与仿真

- 按第 7.4 节保留协议 package 和 PS 侧 `.h/.c`。
- 由采集/扫频 RTL 直接写测量 BRAM Port B，由 FIR/配置 RTL 直接读系数 BRAM Port B。
- 覆盖复位后保持 BUSY/不误启动、发布中断、generation 变化、长度越界、非法格式和异步时钟情形。

### 阶段 E：硬件和软件联调

- 生成 bitstream 和新 XSA。
- 更新 Vitis platform/BSP。
- 软件先完成 BRAM walking-1/地址边界测试，再测试 header/payload。
- 验证 PS 写 129 个系数后 PL 正确装载；验证 PL 写一批测量结果后 PS 获得一致快照。
- 最后移除旧 `system`、LED/按键工程引用和旧平台产物。

## 9. 验收标准

以下条件全部满足才视为重构完成：

1. 从干净克隆仅用 `scripts/` 可在 `work/` 重建工程和 BD。
2. 同一 Tcl 重建流程至少连续执行两次，结果一致且无重名/残留对象。
3. 新 BD 中不存在 `LED` module reference、AXI GPIO、按键或业务 RTL。
4. 新 BD 恰有两个 AXI BRAM Controller 和两个 True Dual Port BRAM，两个 Port B 均导出。
5. `validate_bd_design` 无 error；所有非预期 warning 均有记录和处理结论。
6. 地址固定为计划表中的窗口，XSA 与软件头文件一致。
7. 测量 BRAM 通过 PL 写/PS 读测试，系数 BRAM 通过 PS 写/PL 读测试。
8. 两个时钟域不发生同地址双写，generation 协议能识别更新中的数据。
9. 两块 BRAM 清零、PL 复位或 PS 尚未初始化时，接收端均保持 BUSY/不启动；只有完整合法提交才进入 DONE/VALID。
10. 综合、实现和仿真生成物全部位于 `work/`，仓库根目录无 `.log`、`.jou`、`.pb`、`xsim.dir` 等遗留文件。

## 10. 实施前需最终确认的参数

以下项目不会阻止先搭建 BD，但在编写业务 RTL 适配层前必须冻结：

- 测量 BRAM 每条记录的确切 32-bit word 排布；
- 测量最大点数是否仍为 2991，以及是否需要 ping-pong 双缓冲；
- FIR 系数采用 Q1.15、Q1.31 还是其他格式；
- PL 侧测量和 FIR 时钟频率，以及是否与 100 MHz `FCLK_CLK0` 同源；
- 是否接受初版 PS 轮询；如确需中断，应将其作为独立、可选的通知路径，不能替代 BRAM 中的状态和 generation 校验。

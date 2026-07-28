# PS–AXI–三 BRAM 通信子系统

## 1. 设计定位

`ps_bram_subsystem_bd` 将 Zynq PS、AXI 互连和三块双口 BRAM 封装为稳定的软硬件边界。PS 只通过 AXI 映射的 BRAM 与业务 PL 交换数据；ADC、DDS、扫频、IQ 解调和 FIR 模块可以在边界外独立演进。

可重复构建设计的源文件是 `fpga/scripts/build_ps_bram_subsystem.tcl`。Vivado 自动生成的 BD、IP 输出产品、标准 wrapper、报告和 XSA 均位于 `work/ps_bram_subsystem/`，不纳入版本管理。供最终 PL 顶层例化且带接口说明的稳定 wrapper 为 `fpga/src/hdl/ps_bram_subsystem_wrapper.sv`。

## 2. 已确认的工程条件

- FPGA：Xilinx Zynq-7000 `xc7z020clg400-2`。
- 开发板手册标注 PS 时钟为 33.333333 MHz、DDR3 为 1 GiB/32 bit，由两片 `MT41J256M16 RE-125` 组成。
- 当前 Vivado 2022.2 安装中没有 Mizar Z7 board part/preset，因此脚本显式配置器件、DDR 型号/宽度/频率，但无法从仓库资料确认 PCB DDR 走线延时参数。
- 现有 PL 数据通路使用 `clock_tree` 从板载 50 MHz 产生 100 MHz 和 30 MHz；ADC–FIR–DAC 业务接口当前工作在 30 MHz。
- 仓库没有可复用的主工程或既有 Block Design，因此本子系统用 Tcl 从零、可重复创建，不修改现有业务 RTL。

## 3. 结构与地址映射

```text
PS7 M_AXI_GP0
      |
AXI Interconnect (1 SI / 3 MI)
      +-- AXI BRAM Controller -- IQ TDP BRAM ---- PL写端口
      +-- AXI BRAM Controller -- FIR TDP BRAM --- PL读端口
      +-- AXI BRAM Controller -- 参数TDP BRAM -- PL读端口
```

Address Editor 的固定结果如下。所有数据均为 32 bit，地址按 byte 编址。

| 用途 | AXI 地址范围 | 容量 | 深度 | PS 角色 | PL 角色 |
| --- | --- | ---: | ---: | --- | --- |
| IQ 数据 | `0x4000_0000`–`0x4000_7FFF` | 32 KiB | 8192 × 32 bit | 只读 | 只写 |
| FIR 系数 | `0x4001_0000`–`0x4001_0FFF` | 4 KiB | 1024 × 32 bit | 只写 | 只读 |
| 参数 | `0x4002_0000`–`0x4002_0FFF` | 4 KiB | 1024 × 32 bit | 只写 | 只读 |

AXI BRAM Controller 本身支持 AXI 读写，所以上表中的 PS 方向是必须由 Vitis 软件执行的接口契约；PL 侧通过只导出角色所需信号来施加结构性限制。三段基地址按独立的 64 KiB 区域分隔，给各窗口保留扩展空间。改变基地址或物理窗口大小会改变 Vitis 硬件描述，应视为接口破坏性变更。

## 4. PL 侧接口

三组 `addr` 都是本 BRAM 窗口内的 32 位 byte offset，不是 AXI 绝对地址。地址必须 4-byte 对齐，第 `n` 个 32-bit word 的地址为 `n << 2`。

### 4.1 IQ BRAM：PL 写、PS 读

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `iq_pl_clk` | 输入 | BRAM Port B 写时钟；当前 BD 元数据为 30 MHz |
| `iq_pl_rst` | 输入 | 高有效端口复位；不清空 BRAM 内容 |
| `iq_pl_en` | 输入 | Port B 使能 |
| `iq_pl_addr[31:0]` | 输入 | `0x0000`–`0x7FFC` 的对齐 byte offset |
| `iq_pl_we[3:0]` | 输入 | byte write enable；完整 word 写为 `4'b1111` |
| `iq_pl_wdata[31:0]` | 输入 | 写数据 |

写操作在 `iq_pl_clk` 上升沿、`iq_pl_en=1` 且至少一个 `iq_pl_we` 位为 1 时发生。超出物理窗口的高地址位不会产生新的存储空间，业务模块必须先做范围检查。

### 4.2 FIR 系数 BRAM：PS 写、PL 读

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `fir_pl_clk` | 输入 | BRAM Port B 读时钟；当前 BD 元数据为 30 MHz |
| `fir_pl_rst` | 输入 | 高有效端口复位；不清空 BRAM 内容 |
| `fir_pl_en` | 输入 | 同步读使能 |
| `fir_pl_addr[31:0]` | 输入 | `0x000`–`0xFFC` 的对齐 byte offset |
| `fir_pl_rdata[31:0]` | 输出 | 同步读数据，在采入地址的上升沿之后更新 |

当前共享 BRAM 协议已经规定 FIR payload 为 32-bit Q1.31 系数，详细 header、`STATUS`、`GENERATION` 和发布顺序见《PS端共享BRAM访问与STATUS通知协议》。FIR 加载模块应在下一拍采样 `rdata`。

### 4.3 参数 BRAM：PS 写、PL 读

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `param_pl_clk` | 输入 | BRAM Port B 读时钟；当前 BD 元数据为 30 MHz |
| `param_pl_rst` | 输入 | 高有效端口复位；不清空 BRAM 内容 |
| `param_pl_en` | 输入 | 同步读使能 |
| `param_pl_addr[31:0]` | 输入 | `0x000`–`0xFFC` 的对齐 byte offset |
| `param_pl_rdata[31:0]` | 输出 | 同步读数据，在采入地址的上升沿之后更新 |

参数 BRAM 的 4 KiB 物理窗口已固定，但字段布局尚未定义。参数读取模块实现前必须冻结第 7 节列出的协议。

## 5. 时钟、复位与跨时钟域

- PS 的 `FCLK_CLK0` 配置为 100 MHz，统一驱动 `M_AXI_GP0`、AXI Interconnect、三个 AXI BRAM Controller 和三块 BRAM 的 Port A。
- `FCLK_RESET0_N` 经 `proc_sys_reset` 同步处理后，分别驱动互连和 AXI 外设的低有效复位。
- 三个 Port B 使用各自的 `*_pl_clk` 和高有效 `*_pl_rst`。BMG 配置为 True Dual Port、独立时钟，因此 Port A 与 Port B 不要求同相或同频。
- 独立时钟 BRAM只解决电气意义上的双端口访问，不自动保证一批多 word 数据的一致快照。生产者必须最后发布 `STATUS=DONE/VALID`，消费者必须前后校验稳定的 `GENERATION`。
- 不允许 PS 和 PL 同时写同一块 BRAM，也应避免一侧读取另一侧正在改写的同一地址。若将来需要双向确认，应另设单写者 ACK 字段或独立控制寄存器。
- 当前独立 wrapper 只有 BD 时钟频率元数据，没有最终板级输入延时约束。集成到完整顶层后，必须让 `*_pl_clk` 连接真实全局业务时钟，并在顶层 XDC 中保持对应时序定义。

## 6. 构建、验证和 XSA

必须从仓库 `work/` 目录、使用 Conda 环境 `vivado2022` 中的 Vivado 2022.2 执行：

```powershell
conda run -n vivado2022 F:\vivado2022\Vivado\2022.2\bin\vivado.bat `
  -mode batch -source ..\fpga\scripts\build_ps_bram_subsystem.tcl -notrace
```

脚本依次执行 BD Validate、输出产品生成、Vivado wrapper 生成、顶层综合、利用率/CDC 报告和 fixed XSA 导出。主要产物：

- 自动 wrapper：`work/ps_bram_subsystem/ps_bram_subsystem.gen/sources_1/bd/ps_bram_subsystem_bd/hdl/ps_bram_subsystem_bd_wrapper.v`
- 地址报告：`work/ps_bram_subsystem/reports/address_map.rpt`
- 综合利用率：`work/ps_bram_subsystem/reports/post_synth_utilization.rpt`
- CDC 报告：`work/ps_bram_subsystem/reports/post_synth_cdc.rpt`
- fixed XSA：`work/ps_bram_subsystem/exports/ps_bram_subsystem.xsa`

当前 fixed XSA 不包含 bitstream，可以用于先建立稳定的 Vitis Platform 地址和硬件描述。正式上板导出含 bitstream 的 XSA 前，仍需把 wrapper 集成到完整 PL 顶层、连接真实 PL 时钟/复位、加入板级 XDC、完成实现并确认 Mizar Z7 的 PS DDR/MIO preset 参数。

## 7. 尚待冻结的协议

1. 参数 BRAM 的 `MAGIC`、版本、`GENERATION`、`STATUS`、有效 word 数和 payload 起始偏移。
2. 起始频率、终止频率、步长、采样率等字段的顺序、单位、signed/unsigned、范围和非法组合错误码。
3. 参数是一次性快照还是允许运行中更新；PL 何时锁存一代参数，以及是否需要独立 ACK。
4. IQ 协议中频率轴目前仍依赖固定起点/步长；后续应决定由参数 BRAM、IQ header 或双方配置版本绑定。
5. PS 软件的 MMIO cache 属性、内存屏障位置和三块 BRAM 的单写者访问封装。
6. Mizar Z7 DDR PCB 走线延时、MIO 电气参数和可验证的官方 board preset；缺少这些信息时，当前 XSA只能视为接口/软件开发基线，不能作为 DDR 上板签核依据。


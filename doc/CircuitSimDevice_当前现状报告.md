# CircuitSimDevice 当前现状报告

更新日期：2026-07-25  
工程目录：`E:/FPGA_PJ/Prepare/CircuitSimDevice`

## 1. 项目目标

本工程为后续 Vitis 软件开发准备最小 Zynq 硬件平台。

PL 端在 FPGA 配置时将 MATLAB 生成的双路扫频原始 ADC 数据初始化到片上 BRAM。用户按下 Mizar Z7 的 `PL_KEY1` 后，PL 产生消抖后的按键状态和中断；PS 在 Vitis 软件中响应中断，然后通过 AXI 读取 BRAM 数据并完成后续算法处理。

RMS、频响计算和其他信号处理不在 PL 中实现，由后续 Vitis 软件负责。

## 2. 当前硬件结构

```text
Mizar Z7 PL_KEY1（button_0，低有效）
        │
        ▼
LED_0
  - 双触发器同步
  - 20 ms 消抖
  - button_pressed（高有效）
  - 按下时点亮 PL_LED1
        │
        ▼
axi_gpio_0 ── ip2intc_irpt ──► Zynq PS IRQ_F2P[0]
        │
        └── PS 可读取 GPIO 输入状态

Zynq PS M_AXI_GP0 ──► AXI SmartConnect ──► AXI BRAM Controller
                                                   │
                                                   ▼
                                    Block Memory Generator，64-bit × 4096
                                    已由 sweep_iq_complete.coe 初始化
```

PL 时钟由 PS 的 `FCLK_CLK0` 提供，频率为 **100 MHz**。AXI SmartConnect、AXI BRAM Controller、AXI GPIO 和按键消抖逻辑均使用该时钟及 `rst_ps7_0_100M/peripheral_aresetn` 同步复位。

## 3. 扫频数据与 BRAM

MATLAB 数据生成脚本：

```text
matlab/generate_dual_channel_sweep_coe.m
```

BRAM 初始化文件：

```text
doc/sweep_iq_complete.coe
```

数据配置如下：

| 项目 | 值 |
| --- | --- |
| 扫频范围 | 200 Hz 至 60 kHz |
| 频率步长 | 20 Hz |
| 有效频点数 | 2991 |
| BRAM 深度 | 4096 个 64-bit word |
| 有效索引 | 0 至 2990 |
| 预留索引 | 2991 至 4095，初始化为 `0x0000000000000000` |

每个 64-bit BRAM word 的位域为：

```text
[63:48]  I_filtered，int16 Q1.15，二补码
[47:32]  Q_filtered，int16 Q1.15，二补码
[31:16]  I_direct，int16 Q1.15，二补码
[15:0]   Q_direct，int16 Q1.15，二补码
```

第 `i` 个有效 word 对应频率：

```text
frequency_hz = 200 + 20 × i
```

因此软件不需要在 BRAM 中另存频率表；通过索引即可还原频率。

## 4. PS 侧硬件地址与中断

| 外设 | 地址范围 | 用途 |
| --- | --- | --- |
| `axi_bram_ctrl_0` | `0x4000_0000 – 0x4000_7FFF` | 读取 4096 个 64-bit 扫频数据 word |
| `axi_gpio_0` | `0x4120_0000 – 0x4120_FFFF` | 读取按键状态、确认/清除 GPIO 中断 |
| `IRQ_F2P[0]` | PL 到 PS 中断线 | 接收 `axi_gpio_0/ip2intc_irpt` |

PS 读取第 `i` 个扫频数据时使用：

```c
uintptr_t address = 0x40000000U + 8U * i;
uint32_t low  = *(volatile uint32_t *)(address);
uint32_t high = *(volatile uint32_t *)(address + 4U);

int16_t q_direct   = (int16_t)(low & 0xFFFFU);
int16_t i_direct   = (int16_t)(low >> 16);
int16_t q_filtered = (int16_t)(high & 0xFFFFU);
int16_t i_filtered = (int16_t)(high >> 16);
```

有效读取范围为 `i = 0 ... 2990`。

## 5. 已修改的版本管理源文件

| 文件 | 作用 |
| --- | --- |
| `src/hdl/LED.v` | 按键前端模块；输出消抖状态和事件，控制 LED |
| `src/hdl/button_debounce.v` | 按键同步与 20 ms 消抖逻辑 |
| `src/constrs/button_led.xdc` | `button_0` 绑定 PL_KEY1（R19），`led_0` 绑定 PL_LED1（G14） |
| `src/README.md` | RTL 模块与 Block Design 连接说明 |

当前 `work/` 工程中也已同步更新上述 RTL/XDC 的导入副本。`work/` 是本机生成目录，不应作为长期版本管理的唯一来源。

## 6. 已知警告与结论

Block Design 验证中仅保留以下警告：

```text
[BD 41-237] Bus Interface property MASTER_TYPE does not match between
/blk_mem_gen_0/BRAM_PORTA(OTHER) and
/axi_bram_ctrl_0/BRAM_PORTA(BRAM_CTRL)
```

该警告由手工连接、且需要载入 COE 的 Stand Alone BMG 引起，属于 Block Design 接口元数据不一致。实际数据路径的时钟、地址、数据、使能和写使能信号均已连接。当前 BMG 参数为 64-bit × 4096，AXI 地址段为 32 KiB，匹配正确。

该警告仍应在后续 bitstream 上板后通过 PS 读取 BRAM 首项、中间项和末项并与 COE 数据比较来验证。

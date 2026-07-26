# PS 端 IQ → FIR →共享 BRAM 完整流程

该 Vitis 应用持续轮询测量 BRAM，复制一代稳定 IQ 快照，拟合实系数 FIR，量化为 Q1.31，再发布到系数 BRAM。运行过程不依赖按钮和中断。

## 测量 payload 格式

测量头部使用 `vitis/common/shared_bram_protocol.h` 定义的 64-byte 协议头。`FORMAT=SHARED_BRAM_MEAS_FORMAT_IQ_INT16_X4` 时，每个扫频点占两个 32-bit word：

```text
word[2*n+0] = {I_direct[15:0],   Q_direct[15:0]}
word[2*n+1] = {I_filtered[15:0], Q_filtered[15:0]}
```

因此 `WORD_COUNT` 必须是大于零的偶数，扫频点数为 `WORD_COUNT/2`。当前协议头没有保存扫频起点、步长和 ADC 采样率，PS 暂时使用 `sweep_iq.h` 中的固定配置：

```text
first_frequency_hz = 200
frequency_step_hz  = 20
adc_sample_rate_hz = 300000
```

PL 提交测量时必须依次写 `BUSY → header/payload → GENERATION → DONE`。

## FIR 生成

每个有效扫频点计算：

```text
X = I_direct + jQ_direct
Y = I_filtered + jQ_filtered
H = Y / X
```

零幅值 `X` 无法计算传递函数，将被跳过。其余复频响样本用于岭正则化最小二乘，拟合 129-tap 一般实系数 FIR：

```text
H(w) = sum(h[n] * exp(-j*w*n))
ridge_factor = 1e-6
```

浮点系数乘以 `2^31` 并四舍五入为 signed Q1.31；超出 Q1.31 范围的值会饱和，并通过 UART 的 `saturated` 计数报告。

## 系数发布

发布成功时，`shared_bram_publish_coefficients_q31()` 按以下顺序写系数 BRAM：

```text
STATUS = BUSY
MAGIC / VERSION / TAP_COUNT / FORMAT / SCALE
129 个 Q1.31 payload
dmb sy
GENERATION = old + 1
dmb sy
STATUS = VALID
```

`VALID` 是最后一次写入，因此 PL 看到 VALID 时才可以读取新一代系数。拟合失败时，PS 发布 `STATUS=ERROR`；此时 `ARG1` 解释为错误码，而不是 SCALE。

| ERROR_CODE | 含义 |
| ---: | --- |
| `0x101` | FIR 拟合初始化失败 |
| `0x102` | IQ 快照读取失败 |
| `0x103` | 有效频响点少于 tap 数 |
| `0x104` | FIR 方程构建或求解失败 |
| `0x105` | 浮点系数量化失败 |

PL 应把系数复制到自己的 shadow bank，复查 `GENERATION/STATUS` 后再在安全边界切换 active bank。

## 主循环

`main.c` 的自动流程为：

```text
启动：系数 STATUS=BUSY
    ↓
轮询测量 STATUS
    ↓ DONE 且 generation 稳定
复制 payload 到 PS DDR 快照
    ↓
跳过已经处理过的 generation
    ↓
计算 H(jw) 并拟合 FIR
    ↓
量化为 Q1.31
    ↓
发布系数并最后写 VALID
    ↓
等待下一代测量
```

关键 UART 输出：

```text
MEASUREMENT_READY,generation=...,words=...,points=...
COEFFICIENT_VALID,measurement_generation=...,coefficient_generation=...,taps=129,fit_points=...,saturated=...
```

## 平台要求

应用使用以下固定映射：

```text
测量 BRAM：0x40000000，32 KiB
系数 BRAM：0x40010000，4 KiB
```

仓库中的旧 Vitis platform/XSA 仍来自重构前硬件。上板运行前必须从新 `ps_pl_bram` 设计导出 XSA，并重新生成 platform/BSP；否则旧硬件只包含一块 BRAM，访问 `0x40010000` 不会得到预期结果。

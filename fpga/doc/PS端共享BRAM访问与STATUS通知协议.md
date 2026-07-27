# PS 端共享 BRAM 访问与 STATUS 通知协议

## 1. 设计边界

本设计使用两块 True Dual Port BRAM 在 Zynq PS 和 PL 之间交换批量数据：

| BRAM | AXI 基地址 | 容量 | 生产者 | 消费者 |
| --- | ---: | ---: | --- | --- |
| 测量 BRAM | `0x4000_0000` | 32 KiB | PL | PS |
| 系数 BRAM | `0x4001_0000` | 4 KiB | PS | PL |

每块 BRAM 的 Port A 连接 AXI BRAM Controller，供 PS 使用；Port B 导出到 BD 外部，供普通 PL RTL 使用。PS 和 PL 不共享业务状态机，只通过 BRAM 中的协议头和 payload 交换数据快照。

本工程不再提供通用 BRAM writer 或 loader。采集、扫频和 FIR RTL 直接控制原生 BRAM Port B；PS 通过 `Xil_In32()` 和 `Xil_Out32()` 访问 AXI 映射地址。

`STATUS` 是轮询通知字，不是中断，也不是请求/应答总线。生产者必须最后写完成状态；消费者只有看到完整且稳定的一代数据后才能使用 payload。

## 2. 存储布局

每块 BRAM 的前 16 个 32-bit word，即 64 bytes，保留为协议头。payload 从偏移 `0x40` 开始。字段均为 32-bit little-endian。

| 字节偏移 | word 下标 | 字段 | 说明 |
| ---: | ---: | --- | --- |
| `0x00` | 0 | `MAGIC` | 区分测量 BRAM 和系数 BRAM |
| `0x04` | 1 | `VERSION` | 协议布局版本 |
| `0x08` | 2 | `GENERATION` | 每次发布新快照时递增 |
| `0x0C` | 3 | `STATUS` | 当前快照的主状态和附加标志 |
| `0x10` | 4 | `ARG0` | 测量为 `WORD_COUNT`，系数为 `TAP_COUNT` |
| `0x14` | 5 | `FORMAT` | payload 数据格式编号 |
| `0x18` | 6 | `ARG1` | 测量为 `ERROR_CODE`，系数为 `SCALE` |
| `0x1C`–`0x3C` | 7–15 | reserved | 写零，留作扩展 |
| `0x40` | 16 | payload[0] | 第一个有效数据 word |

PS 使用字节地址，寄存器地址为 `BRAM_BASE + 字节偏移`。PL 导出的 BMG Port B 也配置为 32-bit 字节地址，访问第 `n` 个 word 时应驱动：

```systemverilog
bram_addr = n << 2;
```

例如 payload[0] 的地址为 `0x40`，payload[1] 为 `0x44`。

## 3. STATUS 编码和通知语义

`STATUS[1:0]` 是互斥主状态：

| `STATUS[1:0]` | 数值 | 测量 BRAM | 系数 BRAM |
| --- | ---: | --- | --- |
| `00` | 0 | `BUSY` | `BUSY` |
| `01` | 1 | `DONE` | `VALID` |
| `10` | 2 | `ERROR` | `ERROR` |
| `11` | 3 | 非法/保留 | 非法/保留 |

所有状态默认值必须是 `BUSY=0`。BRAM 上电清零后自然处于 BUSY，因此不会把未初始化内容误认为有效数据。

状态通知遵循“生产者单写、消费者只读”原则：

- 测量 BRAM 的 header、payload 和 `STATUS` 只能由 PL 写，PS 只读。
- 系数 BRAM 的 header、payload 和 `STATUS` 只能由 PS 写，PL 只读。
- 消费者不得通过改写同一个 `STATUS` 确认已处理，否则会形成双写者竞争。

`DONE/VALID` 只表示生产者已发布一个完整快照，不表示消费者已经处理完成。如果以后需要 ACK，应增加独立寄存器或保留字段，并明确 ACK 只有消费者写、生产者读。

`STATUS[31:8]` 可携带溢出、截断等附加标志。判断主状态时必须使用掩码：

```c
state = status & SHARED_BRAM_STATUS_STATE_MASK;
```

不能直接使用 `status == DONE`，否则附加标志会导致判断失败。

## 4. PS 从测量 BRAM 取数据

### 4.1 测量头部

| 偏移 | 字段 | 期望值或含义 |
| ---: | --- | --- |
| `0x00` | `MAGIC` | `0x4D45_4153`，ASCII `MEAS` |
| `0x04` | `VERSION` | `0x0001_0000` |
| `0x08` | `GENERATION` | PL 每发布一批结果递增一次 |
| `0x0C` | `STATUS` | `BUSY/DONE/ERROR` |
| `0x10` | `WORD_COUNT` | payload 有效 32-bit word 数 |
| `0x14` | `FORMAT` | 测量数据格式编号 |
| `0x18` | `ERROR_CODE` | `STATUS=ERROR` 时的 PL 错误码 |

### 4.2 扫频 IQ payload 的精确格式

当前测量格式编号为：

```text
FORMAT = 1 = SHARED_BRAM_MEAS_FORMAT_IQ_INT16_X4
```

`X4` 表示每个扫频点包含四个 signed 16-bit 二进制补码数：直通通道的 I/Q 和滤波通道的 I/Q。一个扫频点共 64 bits，占两个连续的 32-bit word：

| 点内 word | 相对测量 BRAM 的字节偏移 | `[31:16]` | `[15:0]` |
| ---: | ---: | --- | --- |
| `2*n` | `0x40 + 8*n` | `I_direct` | `Q_direct` |
| `2*n+1` | `0x44 + 8*n` | `I_filtered` | `Q_filtered` |

其中 `n` 从零开始。四个 I/Q 分量均为 signed int16，采用二进制补码，数值范围为 `-32768` 到 `32767`。协议只保存 PL 计算得到的整数结果，不额外规定 ADC 电压或相关累加值的物理缩放；PS 和 PL 必须对该缩放使用相同约定。

PL 侧写入一个点时应组织为：

```systemverilog
direct_word   = {i_direct[15:0],   q_direct[15:0]};
filtered_word = {i_filtered[15:0], q_filtered[15:0]};
```

所有 word 按 little-endian 存储。以 `direct_word = 32'h1234_ABCD` 为例，PS 使用 `Xil_In32()` 读到 `0x1234ABCD`；BRAM 中从低地址到高地址的四个 byte 依次为 `CD AB 34 12`。

`WORD_COUNT` 是 32-bit word 数，不是扫频点数：

```text
WORD_COUNT = POINT_COUNT * 2
POINT_COUNT = WORD_COUNT / 2
```

因此 `WORD_COUNT` 必须大于零且为偶数。32 KiB 测量 BRAM 扣除 64-byte 头部后最多保存 8176 words，即 4088 个这种扫频点。

当前应用使用 2991 个扫频点，因此：

```text
WORD_COUNT       = 5982
payload 字节数   = 23928
point[0]         = 0x4000_0040 / 0x4000_0044
point[2990]      = 0x4000_5DB0 / 0x4000_5DB4
```

当前协议版本没有把扫频频率参数写入 header。PS 软件暂时固定使用：

```text
frequency(n)      = 200 Hz + n * 20 Hz
ADC sample rate   = 300000 Hz
```

当 `POINT_COUNT=2991` 时，最后一个点为 60000 Hz。如果 PL 改变扫频起点、步长或 ADC 采样率，必须同步修改 PS 配置，或者在后续协议版本中给这些参数分配正式字段。

### 4.3 PL 必须遵守的发布顺序

PS 能否安全读取，取决于 PL 是否按以下顺序发布：

1. 写 `STATUS=BUSY`，宣告旧快照正在被替换。
2. 写 `MAGIC`、`VERSION`、`WORD_COUNT`、`FORMAT` 和错误字段。
3. 从 `0x40` 开始写完整 payload。
4. 写新的 `GENERATION = old_generation + 1`。
5. 最后写 `STATUS=DONE`。

发生失败时，PL 应写 `ERROR_CODE`、递增 `GENERATION`，最后写 `STATUS=ERROR`。`STATUS` 必须最后写，因为它相当于通知信号。

### 4.4 PS 轮询流程

PS 保存本地变量 `last_consumed_generation`，用于避免重复处理同一批数据。一次读取流程如下：

1. 读取 `STATUS`；若为 BUSY，延时后继续轮询。
2. 若为 ERROR，读取 `ERROR_CODE` 并处理错误。
3. 若不是 DONE，视为尚未就绪或协议错误。
4. 读取 `GENERATION` 两次，并确认两次之间 `STATUS` 仍为 DONE。
5. 若 generation 与 `last_consumed_generation` 相同，不重复处理。
6. 检查 `MAGIC`、`VERSION`、`WORD_COUNT` 和 `FORMAT`。
7. 把 payload 复制到 PS 自己的缓冲区。
8. 执行内存屏障，再次读取 `GENERATION` 和 `STATUS`。
9. 只有前后 generation 相同且最终状态仍为 DONE，缓冲区才是有效快照。
10. 处理完成后更新 `last_consumed_generation`；PS 不改写测量 BRAM 的 STATUS。

如果第 4 或第 9 步发现变化，说明 PL 在读取期间开始发布下一批数据。PS 必须丢弃当前缓冲区并从头重读。

### 4.5 PS 读取示例

仓库中的 `vitis/common/shared_bram_protocol.c` 封装了 MMIO 和快照检查。应用程序可以轮询：

```c
#include "shared_bram_protocol.h"

#define MEAS_BRAM_BASE       ((UINTPTR)0x40000000U)
#define MEAS_BRAM_SIZE_BYTES (32U * 1024U)
#define MEAS_PAYLOAD_WORDS \
    ((MEAS_BRAM_SIZE_BYTES - SHARED_BRAM_PAYLOAD_OFFSET) / 4U)

static uint32_t measurement_buffer[MEAS_PAYLOAD_WORDS];
static uint32_t last_consumed_generation;

void poll_measurement_bram(void)
{
    shared_bram_measurement_info_t info;
    shared_bram_result_t result;

    result = shared_bram_read_measurement(
        MEAS_BRAM_BASE,
        MEAS_BRAM_SIZE_BYTES,
        measurement_buffer,
        MEAS_PAYLOAD_WORDS,
        &info);

    if (result == SHARED_BRAM_NOT_READY ||
        result == SHARED_BRAM_RETRY) {
        return;
    }

    if (result != SHARED_BRAM_OK) {
        /* 记录 MAGIC、VERSION、长度、格式或 PL 错误。 */
        return;
    }

    if (info.generation == last_consumed_generation) {
        return;
    }

    /* 消费 measurement_buffer[0 .. info.word_count-1]。 */
    last_consumed_generation = info.generation;
}
```

当前 `IQ_INT16_X4` 格式中，每个扫频点占两个 32-bit word：

```text
word[2*n+0] = {I_direct[15:0],   Q_direct[15:0]}
word[2*n+1] = {I_filtered[15:0], Q_filtered[15:0]}
```

PS 解包方式为：

```c
uint32_t direct = measurement_buffer[2U * index];
uint32_t filtered = measurement_buffer[2U * index + 1U];
int16_t i_direct = (int16_t)(direct >> 16);
int16_t q_direct = (int16_t)(direct & 0xFFFFU);
int16_t i_filtered = (int16_t)(filtered >> 16);
int16_t q_filtered = (int16_t)(filtered & 0xFFFFU);
```

## 5. PS 向系数 BRAM 存数据

### 5.1 系数头部

| 偏移 | 字段 | 期望值或含义 |
| ---: | --- | --- |
| `0x00` | `MAGIC` | `0x434F_4546`，ASCII `COEF` |
| `0x04` | `VERSION` | `0x0001_0000` |
| `0x08` | `GENERATION` | PS 每发布一组配置递增一次 |
| `0x0C` | `STATUS` | `BUSY/VALID/ERROR` |
| `0x10` | `TAP_COUNT` | payload 中的有效系数数量 |
| `0x14` | `FORMAT` | 例如 Q1.31 |
| `0x18` | `SCALE/ERROR_CODE` | VALID 且 Q1.31 时为 31；ERROR 时为 PS 错误码 |

### 5.2 FIR 系数 payload 的精确格式

当前系数格式编号为：

```text
FORMAT = 1 = SHARED_BRAM_COEFF_FORMAT_Q1_31
SCALE  = 31
```

每个 FIR tap 占一个 32-bit word，按 tap 下标连续排列：

| tap | 相对系数 BRAM 的字节偏移 | 绝对地址 |
| ---: | ---: | ---: |
| `h[0]` | `0x40` | `0x4001_0040` |
| `h[1]` | `0x44` | `0x4001_0044` |
| `h[k]` | `0x40 + 4*k` | `0x4001_0040 + 4*k` |
| `h[128]` | `0x240` | `0x4001_0240` |

当前 PS 应用固定生成 129 taps，所以：

```text
TAP_COUNT       = 129
payload word 数 = 129
payload 字节数  = 516
最后一个有效地址 = 0x4001_0240
```

4 KiB 系数 BRAM 扣除 64-byte 头部后理论上最多保存 1008 个 32-bit taps，但 PL 实现和当前拟合算法均按 129 taps 设计。

每个系数是 signed 32-bit 二进制补码 Q1.31：

```text
实数值 = (int32_t)raw / 2^31
raw    = round(实数值 * 2^31)
范围   = -1.0 到 1.0 - 2^-31
```

常见编码示例：

| 实数系数 | Q1.31 raw | BRAM word |
| ---: | ---: | ---: |
| `0.0` | `0` | `0x0000_0000` |
| `0.5` | `1073741824` | `0x4000_0000` |
| `-0.5` | `-1073741824` | `0xC000_0000` |
| `-1.0` | `-2147483648` | `0x8000_0000` |
| 最大正数 | `2147483647` | `0x7FFF_FFFF` |

PS 将浮点拟合结果乘以 `2^31` 后四舍五入。超过 Q1.31 范围的结果饱和到 `INT32_MIN/INT32_MAX`，并在 UART 日志的 `saturated` 字段中报告数量。

PL 必须将 payload 解释为 signed 数。tap 顺序为 `h[0]、h[1]……h[128]`，对应：

```text
y[n] = sum(h[k] * x[n-k]), k = 0..128
```

word 同样按 little-endian 存储；PL 从原生 BRAM Port B 读出的 32-bit word 不需要交换 byte，只需转换为 signed 32-bit。

### 5.3 PS 发布流程

PS 是系数 BRAM 的唯一生产者。每次发布必须执行：

1. 读取当前 `GENERATION`。
2. 写 `STATUS=BUSY`，使 PL 停止接受当前正在更新的内容。
3. 写 `MAGIC`、`VERSION`、`TAP_COUNT`、`FORMAT`、`SCALE` 和 reserved 字段。
4. 从 `0x40` 开始写全部系数 payload。
5. 执行 `dmb sy` 内存屏障，确保前面的 AXI 写入先完成。
6. 写 `GENERATION = old_generation + 1`。
7. 再执行一次内存屏障。
8. 最后写 `STATUS=VALID`，通知 PL 新配置已经发布。
9. 再执行一次内存屏障。

不能先写 VALID 再写 payload，否则 PL 可能读取到一半旧数据、一半新数据。

### 5.4 PS 写入示例

```c
#include "shared_bram_protocol.h"

#define COEFF_BRAM_BASE       ((UINTPTR)0x40010000U)
#define COEFF_BRAM_SIZE_BYTES (4U * 1024U)

static const int32_t coefficients[] = {
    0x01000000,
    0x02000000,
    0x01000000
};

void publish_fir_coefficients(void)
{
    uint32_t generation;
    shared_bram_result_t result;

    result = shared_bram_publish_coefficients_q31(
        COEFF_BRAM_BASE,
        COEFF_BRAM_SIZE_BYTES,
        coefficients,
        sizeof(coefficients) / sizeof(coefficients[0]),
        &generation);

    if (result != SHARED_BRAM_OK) {
        /* 参数、长度或发布错误处理。 */
    }
}
```

PL 端必须自行实现对应的轮询和本地装载逻辑：看到 VALID 和新的稳定 generation 后，把完整 payload 复制到 FIR 的 shadow bank；复制后复查 generation/status；只在安全边界切换 active bank。PL 不应在 FIR 运算过程中直接使用 PS 可能正在改写的共享 BRAM。

## 6. STATUS 通知时序

测量方向：

```text
PL                              PS
| STATUS = BUSY                 |
| 写 header 和测量 payload      | 轮询得到 BUSY，等待
| GENERATION = N                |
| STATUS = DONE --------------- | 轮询得到 DONE
|                               | 检查并复制 generation N
|                               | 复查状态和 generation
```

系数方向：

```text
PS                              PL
| STATUS = BUSY                 |
| 写 header 和系数 payload      | 轮询得到 BUSY，保持旧系数
| 内存屏障                      |
| GENERATION = N                |
| STATUS = VALID -------------- | 轮询得到 VALID
|                               | 复制到 shadow bank
|                               | 在安全边界切换系数 bank
```

`STATUS` 的作用类似门铃：生产者最后按门铃，消费者再去取已经准备好的数据。它不保存消费确认，也不能代替 generation 的一致性检查。

## 7. MMIO、缓存与内存屏障

PS 必须使用 `Xil_In32()`/`Xil_Out32()` 或等价的 `volatile` MMIO 访问，不能让编译器把协议字段访问优化掉。系数发布中的内存屏障用于限制 CPU 和 AXI 写入顺序。

应把 BRAM 地址区域配置为 Device/strongly ordered 或不可缓存。如果软件平台把它配置为可缓存内存，则 PS 读测量结果前需要失效对应 cache，写系数后需要 clean/flush 对应 cache；否则 CPU 可能看到旧数据，PL 也可能看不到仍停留在 cache 中的新数据。优先采用不可缓存 MMIO 映射，避免 cache 一致性复杂度。

## 8. 容量和错误检查

测量 BRAM 最大 payload：

```text
(32 KiB - 64 bytes) / 4 = 8176 words
```

系数 BRAM 最大 payload：

```text
(4 KiB - 64 bytes) / 4 = 1008 words
```

消费者使用 payload 前必须检查：

- `MAGIC` 与 BRAM 角色匹配；
- `VERSION` 是当前支持的布局；
- 主状态正确；
- count 不为零且不超过 BRAM 容量和本地缓冲区；
- `FORMAT` 和 `SCALE` 受支持；
- 读取前后的 `GENERATION` 一致；
- 读取后的主状态仍为 DONE 或 VALID。

违反任一条件时不得使用当前 payload。消费者应保留上一代有效数据，并等待下一次轮询或报告协议错误。

## 9. 单写者规则总结

| 内容 | 写入方 | 读取方 |
| --- | --- | --- |
| 测量 BRAM header、payload、status | PL | PS |
| 系数 BRAM header、payload、status | PS | PL |
| PS 本地 `last_consumed_generation` | PS | PS |
| FIR active/shadow bank | PL | PL |

坚持单写者规则后，PS 与 PL 无需共享状态机，也不需要相互了解 DDS、扫频或 FIR 的内部结构。两端只需遵守“BUSY 开始、payload 完整、generation 更新、完成状态最后发布”的内存协议。

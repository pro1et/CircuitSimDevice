# 双物理通道 I/Q 扫频 COE 数据

运行 `generate_dual_channel_sweep_coe.m` 后，MATLAB 会模拟两条物理采样通道：模拟信号先经 16-bit ADC 量化，再经 FPGA 数字下变频（NCO 正交混频与相干积分）得到 I/Q 数据。

扫频范围为 200 Hz 至 60 kHz，步长 20 Hz，共 2991 点。每频点模拟 4096 个 ADC 样本。直通通道保留输入、谐波与噪声；滤波通道额外经过 129 阶、20 kHz FIR 低通模型。

## 输出文件

脚本将所有 COE 文件直接写入仓库的 `doc/` 目录；CSV、响应曲线等 MATLAB 校验产物仍保存在 `matlab/` 目录。

- `sweep_iq_complete.coe`：完整的四路数据，供一个 `4096 × 64-bit` BRAM 使用。
- `sweep_iq_complete_32.coe`：相同四路数据展平为 `8192 × 32-bit`，供 Zynq PS 的 32-bit GP AXI 端口使用。
- `sweep_iq_direct.coe`：直通通道 I/Q，供一个 `4096 × 32-bit` BRAM 使用。
- `sweep_iq_filtered.coe`：滤波通道 I/Q，供一个 `4096 × 32-bit` BRAM 使用。
- `sweep_frequency_hz.coe`：频率表。
- `sweep_iq_metadata.csv`：十进制校验数据。
- `dual_channel_iq_response.png`：两通道 I/Q 幅值曲线。

64-bit 完整表的前 2991 个 word 有效；32-bit 展平表的前 5982 个 word 有效；其余 word 补零。

```text
sweep_iq_complete.coe  (4096 × 64-bit，推荐后续实际使用)
  [63:48] = I_filtered，int16 Q1.15，二补码
  [47:32] = Q_filtered，int16 Q1.15，二补码
  [31:16] = I_direct，  int16 Q1.15，二补码
  [15:0]  = Q_direct，  int16 Q1.15，二补码

sweep_iq_direct.coe / sweep_iq_filtered.coe  (各 4096 × 32-bit)
  [31:16] = I，int16 Q1.15，二补码
  [15:0]  = Q，int16 Q1.15，二补码
```

`sweep_iq_complete_32.coe` 中，频点 `i` 占用两个相邻 32-bit word：

```text
word[2*i]     = {I_direct, Q_direct}
word[2*i + 1] = {I_filtered, Q_filtered}
```

这里的 `direct` 即“直通”通道。频点索引 `i` 的频率为 `200 + 20 × i` Hz。PS 读取 `sweep_iq_complete.coe` 的第 `i` 个 64 位 word 后，即可直接取得同一频点的滤波 I/Q 与直通 I/Q 四个值。

当前工程加载 `doc/sweep_iq_complete_32.coe`，AXI BRAM Controller 和 BRAM Port A 均配置为 32-bit，避免 PS GP0 到 64-bit 从设备之间的宽度转换。Block Memory Generator 启用 32-bit byte-address 模式并关闭 primitive 输出寄存器，AXI BRAM Controller 的外部 BRAM 读延迟配置为 1，使 AXI 响应对应当前请求地址。PS 读取地址为 `base + 8*i` 和 `base + 8*i + 4`。

## H(jw) 计算与拟合

运行 `fit_transfer_function.m` 可从 CSV 中的完整复数 I/Q 数据计算

```text
X = I_direct + j*Q_direct
Y = I_filtered + j*Q_filtered
H(jw) = Y / X
```

脚本使用复数最小二乘同时拟合幅值和相位。当前参考通道是 129-tap 线性相位 FIR，因此基线模型选用实系数、对称 129-tap FIR。输出包括：

- `transfer_function_fit_samples.csv`：每个频点的实测与拟合复数 H(jw)、幅值、相位和误差。
- `transfer_function_fir_coefficients.csv`：拟合得到的 129 个 FIR 系数。
- `transfer_function_fit.png`：幅频、相频、复数残差及复平面曲线。

相位只在 H 幅值高于 -40 dB 的频点参与相位误差统计，因为深阻带中的量化噪声会使相位失去物理意义。

## 验证 Vitis 输出的 FIR 系数

`validate_vitis_fir_coefficients.m` 内保存了当前 Vitis 串口输出的 129 个浮点系数。运行该脚本可用原始复数 I/Q 扫频逐点验证 FIR，检查实数性、对称性、复数 NRMSE、有效增益区间的相位误差、直流增益和 -3 dB 截止频率。

```matlab
cd('E:\Vivado\FPGA_project\CircuitSimDevice\matlab')
validate_vitis_fir_coefficients
```

脚本输出：

- `vitis_fir_validation.png`：实测 H 与 FIR 的线性幅频、对数幅频、相频及 FIR 冲激响应。
- `vitis_fir_validation_samples.csv`：全部频点的实测响应、FIR 响应和复数误差。
- `vitis_fir_coefficients.csv`：带 tap 索引的浮点系数。

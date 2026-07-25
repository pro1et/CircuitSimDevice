# 双物理通道 I/Q 扫频 COE 数据

运行 `generate_dual_channel_sweep_coe.m` 后，MATLAB 会模拟两条物理采样通道：模拟信号先经 16-bit ADC 量化，再经 FPGA 数字下变频（NCO 正交混频与相干积分）得到 I/Q 数据。

扫频范围为 200 Hz 至 60 kHz，步长 20 Hz，共 2991 点。每频点模拟 4096 个 ADC 样本。直通通道保留输入、谐波与噪声；滤波通道额外经过 129 阶、20 kHz FIR 低通模型。

## 输出文件

脚本将所有 COE 文件直接写入仓库的 `doc/` 目录；CSV、响应曲线等 MATLAB 校验产物仍保存在 `matlab/` 目录。

- `sweep_iq_complete.coe`：完整的四路数据，供一个 `4096 × 64-bit` BRAM 使用。
- `sweep_iq_direct.coe`：直通通道 I/Q，供一个 `4096 × 32-bit` BRAM 使用。
- `sweep_iq_filtered.coe`：滤波通道 I/Q，供一个 `4096 × 32-bit` BRAM 使用。
- `sweep_frequency_hz.coe`：频率表。
- `sweep_iq_metadata.csv`：十进制校验数据。
- `dual_channel_iq_response.png`：两通道 I/Q 幅值曲线。

所有 COE 的前 2991 个 word 有效，剩余 word 补零。

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

这里的 `direct` 即“直通”通道。频点索引 `i` 的频率为 `200 + 20 × i` Hz。PS 读取 `sweep_iq_complete.coe` 的第 `i` 个 64 位 word 后，即可直接取得同一频点的滤波 I/Q 与直通 I/Q 四个值。

当前工程加载 `doc/sweep_iq_complete.coe`，BRAM 配置为 `4096 × 64-bit`，每个地址同时保存同一频点的滤波 I/Q 与直通 I/Q。

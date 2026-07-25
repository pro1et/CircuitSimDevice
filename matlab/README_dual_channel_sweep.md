# 双路扫频 COE 数据

运行 `generate_dual_channel_sweep_coe.m` 后会生成 200 Hz 至 60 kHz、20 Hz 步长的 2991 个频点。脚本使用 250 kSPS、16 位有符号 ADC 模型，并对同一输入信号模拟直通通道和 129 阶 20 kHz 低通 FIR 后的通道。两个 COE 均会自动补零到 4096 个 32-bit word，能直接用于 32-bit × 4096 的 Block Memory Generator。

生成文件：

- `../doc/sweep_frequency_hz.coe`：每个频点一个 32 位无符号 Hz 值；索引 2991 至 4095 为零。
- `../doc/sweep_adc_capture.coe`：`[31:16]` 为滤波后 ADC `int16`，`[15:0]` 为直通 ADC `int16`；均为二补码原始位型。
- `sweep_metadata.csv`：MATLAB 可读的十进制校验表。

每个 COE word 均为 8 个十六进制字符，适合配置为 32-bit 宽、4096 深度的 Vivado Block Memory Generator。BRAM 中仅需初始化 `sweep_adc_capture.coe`；PS 通过索引计算频率：`f = 200 + 20 × index` Hz（有效索引为 0 至 2990）。

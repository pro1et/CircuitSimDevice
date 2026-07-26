# PS 端浮点 FIR 拟合

该功能根据 BRAM 中同一频点的直通与滤波 I/Q 计算复频率响应：

```text
X = I_direct + j*Q_direct
Y = I_filtered + j*Q_filtered
H = Y / X
```

随后以当前扫频配置中的全部 H 样本拟合一个实系数、奇数 tap、Type-I 对称 FIR。当前默认数据为 2991 点，但拟合循环不依赖该固定数量。默认参数为：

```text
adc_sample_rate_hz = 250000
tap_count      = 129
ridge_factor   = 1e-6
```

这里的采样率是 ADC 采样率，即 FIR 将来实际处理输入样本的速率，不是 DAC 激励发生器的采样率。

扫频读取层使用 `sweep_iq_config_t` 保存运行时参数：

```c
sweep_iq_config_t sweep = {
    .point_count = point_count,
    .first_frequency_hz = first_frequency_hz,
    .frequency_step_hz = frequency_step_hz,
    .adc_sample_rate_hz = adc_sample_rate_hz
};
sweep_iq_configure(&sweep);
```

BRAM 读取、频率计算、串口抽样和 FIR 拟合都通过 `sweep_iq_get_config()` 获取这些值。配置函数会检查 BRAM 容量、频率计算溢出和 Nyquist 范围。

利用对称性，129 个 tap 只有 65 个独立未知量。`fir_fit.c` 逐点累计正规方程，使用岭正则与部分主元高斯消元求解，最终展开为 129 个 `float` 系数。拟合工作区静态分配，不使用裸机堆内存，也不会在栈上放置完整矩阵。

## 板上运行

在 Vitis 中下载当前 ELF 和匹配的 bitstream，将 USB 线切换到 UART 并打开串口，然后按 K3。完成 IQ 拆包检查与 H(jw) 输出后，程序执行 FIR 拟合并输出：

```text
Floating FIR fit from measured H(jw)
FIR_FIT_RESULT,points=...,nrmse_ppm=...,phase_rmse_mdeg=...,cutoff_hz=...
tap_index,coefficient_float
0,...
...
128,...
FIR_COEFFICIENTS_END,taps=129
```

`nrmse_ppm / 1e6` 是复频率响应归一化均方根误差。相位误差只统计 `|H| >= 0.01` 的频点，避免深阻带量化噪声导致无意义的相位跳变。

## 主机测试

工程使用同一个 `fir_fit.c` 进行主机测试，不复制算法实现。在仓库根目录执行：

```powershell
New-Item -ItemType Directory -Force work\host_tests | Out-Null
gcc -std=c11 -O2 -Wall -Wextra -Werror `
    -Ivitis/fir_design/src `
    vitis/fir_design/tests/fir_fit_host_test.c `
    vitis/fir_design/src/fir_fit.c -lm `
    -o work/host_tests/fir_fit_host_test.exe
work/host_tests/fir_fit_host_test.exe matlab/sweep_iq_metadata.csv
```

当前参考 CSV 测试验收条件为：2991 个输入点、复数 NRMSE 小于 0.5%、截止频率位于 19.0–19.5 kHz、系数严格对称且中心系数有限。此外还使用两组独立合成扫频验证动态参数：401 点/300 Hz 步长，以及 173 点/700 Hz 步长。

当前默认配置仍由软件提供。若需要 PS 在每次采集后自动识别点数和步长，PL 或 BRAM 数据格式还必须增加元数据头，至少提供有效点数、起始频率、频率步长和 ADC 采样率；不能从阻带中的零 IQ 数据可靠推断有效点数。

## 当前边界

本阶段仅生成浮点 FIR 系数并验证其频率响应，不包含系数量化、溢出分析、PL FIR 实现、系数写入或运行时硬件接口。

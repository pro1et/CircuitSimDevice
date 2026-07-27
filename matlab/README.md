# 电路自动探究装置 MATLAB 算法链路

入口为 `main.m`。在 MATLAB 中切换到本目录后运行：

```matlab
results = main();
```

默认运行全部 2496 个频点。普通频点使用闭式的正弦充分统计量完成等价 IQ 累加，只保存四个 IQ 结果；100 Hz、1 kHz、10 kHz、50 kHz 四个代表点按 32768 点分块走 DDS→DAC→DUT→ADC→IQ 路径，并只保留受限的调试波形。若需让所有点都逐样本分块运行，可使用 `main("streaming")`，耗时会明显增加。

数据边界与 `fpga/doc/PS端共享BRAM访问与STATUS通知协议.md` 一致：测量快照为每点两个 32-bit word（四个 int16 IQ），PL 完成整批后才置 DONE；ARM 解包整批、计算 `H=Y/X`、统一求解 129 个实数非对称 FIR 抽头，并按 Q1.31 发布系数快照。

> 集成注意：当前协议文档中的 PS 示例仍硬编码为 200 Hz～60 kHz、20 Hz 步长且把 ADC 采样率写成 300 kHz；本仿真按本任务采用 100 Hz～50 kHz、30 MHz 学习采样率和 300 kHz FIR 运行采样率。协议头尚未携带扫频参数，因此上板前必须同步更新 PS 固定配置，或升级协议头以传递这些参数。2496 点占 4992 个 payload word，未超过测量 BRAM 的 8176-word 上限。

`results/` 中会生成 MAT 结果、整批频响、FIR/时域对比以及代表频点的阶段调试图。示例 DUT 位于 `models/create_circuit.m`，可替换为其他稳定的连续时间传递函数。

# 仓库操作规范

## 当前目录介绍

当前目录是 `CircuitSimDevice` FPGA 工程的仓库根目录，工程面向 Vivado 开发。目录结构及用途如下：

```text
CircuitSimDevice/
├── fpga/               FPGA/Vivado/Vitis 相关内容的统一一级目录
│   ├── doc/            工程文档、芯片手册、开发板手册及数据文件
│   ├── scripts/        创建或重建 Vivado 工程、Block Design 所需的 Tcl 脚本
│   ├── src/            需要纳入版本管理的设计源文件
│   │   ├── hdl/        Verilog、SystemVerilog、VHDL 等 RTL 源码
│   │   ├── sim/        Testbench、仿真模型及其他仿真代码
│   │   ├── constrs/    XDC 时序约束和管脚约束文件
│   │   └── ip/         自定义 IP、IP 配置文件及 IP 仓库内容
│   ├── vitis/          Vitis 软件工程、平台工程及相关源文件
│   └── work/           Vivado 实际工程、编译结果、缓存及其他生成文件
├── data_generator/     MATLAB等数据、系数和初始化文件生成工具
├── matlab/             系统级 MATLAB 算法与分析代码
├── .gitignore          Git 忽略规则
└── AGENTS.md           本仓库的自动化操作规范
```

- `fpga/doc/`、`fpga/scripts/`、`fpga/src/` 和 `fpga/vitis/` 中需要长期保存的内容应纳入 Git 管理。
- `fpga/work/` 只用于存放本机可重新生成的工程和构建产物，整个目录由 `.gitignore` 忽略。
- 当前 Vivado 工程位于 `fpga/work/`。在源文件正式整理到 `fpga/src/` 之前，对 `fpga/work/` 内文件的修改不会被 Git 记录。
- 从远程仓库克隆工程后，`fpga/work/` 可能不存在，应通过 `fpga/scripts/` 中的 Tcl 脚本重新创建。
- 仓库根目录不得创建 `work/`；该位置属于错误的旧目录结构。
- Block Design `.bd` 及其 output products 只保存在 `fpga/work/` 的对应 Vivado 主工程内，不放入 `fpga/src/`、不纳入版本管理。BD 的长期可重建源是 `fpga/scripts/` 下的 Tcl 脚本。
- `fpga/src/hdl/` 中允许保存稳定 HDL wrapper，但 wrapper 只有在同一 Vivado 工程已经通过 Tcl 重建对应 BD 后才能使用；禁止将缺少 BD/综合网表的 wrapper 单独作为完整设计导入。

## Vivado 和 XSim 生成文件

- 所有 Vivado 和 XSim 生成的工程、日志、缓存、报告和临时文件必须保存在仓库的 `fpga/work/` 目录中；需要纳入版本管理并复用的 IP 核文件除外。
- 运行 `vivado`、`xvlog`、`xelab`、`xsim` 以及相关构建或验证命令时，必须将 `fpga/work/` 设置为当前工作目录。仅把输入文件放在 `fpga/work/` 中，并不会改变这些工具的输出位置。
- Vivado 重建脚本应主动校验当前目录为 `fpga/work/`，目录不符时立即报错，禁止在仓库根目录自动创建新的 `work/`。
- 禁止在仓库根目录运行 Vivado 或 XSim 的构建、编译和验证命令。
- 调用 Vivado 工具时，必须使用名为 `vivado2022` 的 Conda 环境以及该环境中配置的 `VIVADO_HOME`。
- 所有需要长期保存或供后续工程、Block Design、PS/PL 集成复用的 IP 核文件，包括 `.xci`、`.xcix`、初始化文件及 IP 生成的源码/约束，必须放在 `fpga/src/ip/` 下；禁止只把唯一可用的 IP 核留在 `fpga/work/` 中。
- Vivado 自动生成的 BD、BD output products、IP OOC约束、DCP和自动 wrapper均属于构建产物，只能放在 `fpga/work/`；不得把 `.bd`、`.gen/`、`.srcs/` 或 `.runs/` 复制到 `fpga/src/`。
- `xsim.dir/`、`*.log`、`*.jou`、`*.pb`、缓存、报告以及其他生成文件均属于可丢弃的构建产物，不得在 `fpga/work/` 以外创建或提交这些文件。
- 完成 Vivado 或 XSim 相关任务前，必须检查仓库根目录，确认没有误建的根级 `work/` 或其他遗留生成文件。

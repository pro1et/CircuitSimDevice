# 仓库操作规范

## 当前目录介绍

当前目录是 `CircuitSimDevice` FPGA 工程的仓库根目录，工程面向 Vivado 开发。目录结构及用途如下：

```text
CircuitSimDevice/
├── doc/                工程文档、芯片手册、开发板手册及数据文件
├── scripts/            创建或重建 Vivado 工程、Block Design 所需的 Tcl 脚本
├── src/                需要纳入版本管理的设计源文件
│   ├── hdl/            Verilog、SystemVerilog、VHDL 等 RTL 源码
│   ├── sim/            Testbench、仿真模型及其他仿真代码
│   ├── constrs/        XDC 时序约束和管脚约束文件
│   └── ip/             自定义 IP、IP 配置文件及 IP 仓库内容
├── vitis/              Vitis 软件工程、平台工程及相关源文件
├── work/               Vivado 实际工程、编译结果、缓存及其他生成文件
├── .gitignore          Git 忽略规则
└── AGENTS.md           本仓库的自动化操作规范
```

- `doc/`、`scripts/`、`src/` 和 `vitis/` 中需要长期保存的内容应纳入 Git 管理。
- `work/` 只用于存放本机可重新生成的工程和构建产物，整个目录由 `.gitignore` 忽略。
- 当前 Vivado 工程位于 `work/`。在源文件正式整理到 `src/` 之前，对 `work/` 内文件的修改不会被 Git 记录。
- 从远程仓库克隆工程后，`work/` 可能不存在，应通过 `scripts/` 中的 Tcl 脚本重新创建。

## Vivado 和 XSim 生成文件

- 所有 Vivado 和 XSim 生成的文件必须保存在仓库的 `work/` 目录中。
- 运行 `vivado`、`xvlog`、`xelab`、`xsim` 以及相关构建或验证命令时，必须将 `work/` 设置为当前工作目录。仅把输入文件放在 `work/` 中，并不会改变这些工具的输出位置。
- 禁止在仓库根目录运行 Vivado 或 XSim 的构建、编译和验证命令。
- 调用 Vivado 工具时，必须使用名为 `vivado` 的 Conda 环境以及该环境中配置的 `VIVADO_HOME`。
- `xsim.dir/`、`*.log`、`*.jou`、`*.pb`、缓存、报告以及其他生成文件均属于可丢弃的构建产物，不得在 `work/` 以外创建或提交这些文件。
- 完成 Vivado 或 XSim 相关任务前，必须检查仓库根目录，确认没有遗留生成文件。

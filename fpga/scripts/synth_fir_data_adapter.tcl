# fir_data_adapter 独立综合和组合路径检查脚本。
# 必须从仓库 work 目录调用 Vivado，确保全部生成文件位于 work 内。

set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set report_dir [file join [pwd] fir_data_adapter_reports]
file mkdir $report_dir

read_verilog -sv [file join $fpga_dir src hdl fir_data_adapter.sv]
synth_design -top fir_data_adapter -part xc7z020clg400-2

# 模块为纯组合逻辑，以10 ns接口预算检查任意输入到任意输出的最长组合路径。
set_max_delay 10.000 -from [all_inputs] -to [all_outputs]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose \
    -file [file join $report_dir timing_summary.rpt]

set timing_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $timing_paths] == 0} {
    error "fir_data_adapter 未找到可检查的组合路径"
}
set worst_slack [get_property SLACK [lindex $timing_paths 0]]
if {$worst_slack < 0.0} {
    error "fir_data_adapter 组合路径超过10 ns预算：$worst_slack ns"
}

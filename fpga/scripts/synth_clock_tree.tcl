# clock_tree 独立综合与静态检查脚本。
# 必须从仓库 fpga/work 目录调用 Vivado，确保所有生成文件留在 work 内。

set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set report_dir [file join [pwd] clock_tree_reports]
file mkdir $report_dir

read_verilog -sv [file join $fpga_dir src hdl clock_tree.sv]
synth_design -top clock_tree -part xc7z020clg400-2

create_clock -name clk_50m -period 20.000 [get_ports clk_50m]
set_false_path -from [get_ports rst_n]

report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose \
    -file [file join $report_dir timing_summary.rpt]
report_cdc -details -file [file join $report_dir cdc.rpt]

set timing_paths [get_timing_paths -max_paths 1 -nworst 1]
if {[llength $timing_paths] > 0} {
    set worst_slack [get_property SLACK [lindex $timing_paths 0]]
    if {$worst_slack < 0.0} {
        error "clock_tree 存在负时序裕量：$worst_slack ns"
    }
}

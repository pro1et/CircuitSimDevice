# dac_output 集成综合、输出时序与 CDC 检查脚本。
# 必须从仓库 fpga/work 目录调用 Vivado，确保所有生成文件留在 work 内。

set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set report_dir [file join [pwd] dac_output_reports]
file mkdir $report_dir

read_verilog -sv [file join $fpga_dir src hdl clock_tree.sv]
read_verilog -sv [file join $fpga_dir src hdl dac_output.sv]
read_verilog -sv [file join $fpga_dir src sim dac_output_check_top.sv]
synth_design -top dac_output_check_top -part xc7z020clg400-2

create_clock -name clk_50m -period 20.000 [get_ports clk_50m]

# 3PD5651E 在转发时钟上升沿锁存，要求数据建立 2.0 ns、保持 1.5 ns。
create_generated_clock -name dac_clk_a_ext \
    -source [get_pins u_dac_output/u_oddr_clk_a/C] \
    -divide_by 1 [get_ports dac_clk_a]
create_generated_clock -name dac_clk_b_ext \
    -source [get_pins u_dac_output/u_oddr_clk_b/C] \
    -divide_by 1 [get_ports dac_clk_b]
set_output_delay -clock dac_clk_a_ext -max 2.000 [get_ports {dac_data_a[*]}]
set_output_delay -clock dac_clk_a_ext -min -1.500 [get_ports {dac_data_a[*]}]
set_output_delay -clock dac_clk_b_ext -max 2.000 [get_ports {dac_data_b[*]}]
set_output_delay -clock dac_clk_b_ext -min -1.500 [get_ports {dac_data_b[*]}]

set_false_path -from [get_ports rst_n]

report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose \
    -file [file join $report_dir timing_summary.rpt]
report_cdc -details -file [file join $report_dir cdc.rpt]

set critical_cdc [get_cdc_violations -quiet -filter {SEVERITY == Critical}]
if {[llength $critical_cdc] > 0} {
    error "dac_output 存在 CDC Critical：$critical_cdc"
}

foreach delay_type {max min} {
    set timing_paths [get_timing_paths -delay_type $delay_type -max_paths 1 -nworst 1]
    if {[llength $timing_paths] > 0} {
        set worst_slack [get_property SLACK [lindex $timing_paths 0]]
        if {$worst_slack < 0.0} {
            error "dac_output 存在 $delay_type 负时序裕量：$worst_slack ns"
        }
    }
}

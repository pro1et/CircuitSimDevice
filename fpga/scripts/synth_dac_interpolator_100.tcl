# dac_interpolator_100独立综合、时序和CDC检查脚本；必须从fpga/work运行。
if {[version -short] ne "2022.2"} {
    error "dac_interpolator_100必须使用Vivado 2022.2综合"
}

set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set report_dir [file join [pwd] dac_interpolator_100_reports]
file mkdir $report_dir

read_verilog -sv [file join $fpga_dir src hdl dac_interpolator_100.sv]
read_verilog -sv [file join $fpga_dir src sim dac_interpolator_100_check_top.sv]
synth_design -top dac_interpolator_100_check_top -part xc7z020clg400-2

create_clock -name clk -period 33.333 [get_ports clk]
set_false_path -from [get_ports rst_n]
set_output_delay -clock clk -max 2.000 [get_ports {data_out[*] out_valid in_ready overflow}]
set_output_delay -clock clk -min 0.000 [get_ports {data_out[*] out_valid in_ready overflow}]

report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose \
    -file [file join $report_dir timing_summary.rpt]
report_cdc -details -file [file join $report_dir cdc.rpt]

set critical_cdc [get_cdc_violations -quiet -filter {SEVERITY == Critical}]
if {[llength $critical_cdc] > 0} {
    error "dac_interpolator_100存在CDC Critical：$critical_cdc"
}
foreach delay_type {max min} {
    set paths [get_timing_paths -delay_type $delay_type -max_paths 1 -nworst 1]
    if {[llength $paths] == 0} {
        error "dac_interpolator_100没有可检查的$delay_type时序路径"
    }
    set slack [get_property SLACK [lindex $paths 0]]
    if {$slack < 0.0} {
        error "dac_interpolator_100存在$delay_type负时序裕量：$slack ns"
    }
}

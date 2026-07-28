# top_adc_dac_loopback 综合、实现、DRC、CDC 和时序检查脚本。
# 必须从仓库 work 目录调用 Vivado，确保所有生成文件留在 work 内。

set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set report_dir [file join [pwd] top_adc_dac_loopback_reports]
file mkdir $report_dir

read_verilog -sv [file join $fpga_dir src hdl clock_tree.sv]
read_verilog -sv [file join $fpga_dir src hdl adc_capture.sv]
read_verilog -sv [file join $fpga_dir src hdl dac_output.sv]
read_verilog -sv [file join $fpga_dir src testmodule top_adc_dac_loopback.sv]
read_xdc [file join $fpga_dir src constrs top_adc_dac_loopback.xdc]

synth_design -top top_adc_dac_loopback -part xc7z020clg400-2
write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
report_cdc -details -file [file join $report_dir post_synth_cdc.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose \
    -file [file join $report_dir post_synth_timing_summary.rpt]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $report_dir post_route.dcp]

report_io -file [file join $report_dir post_route_io.rpt]
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose \
    -file [file join $report_dir post_route_timing_summary.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
report_methodology -file [file join $report_dir post_route_methodology.rpt]
report_cdc -details -file [file join $report_dir post_route_cdc.rpt]

set critical_cdc [get_cdc_violations -quiet -filter {SEVERITY == Critical}]
if {[llength $critical_cdc] > 0} {
    error "top_adc_dac_loopback 存在 CDC Critical：$critical_cdc"
}

set timing_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $timing_paths] > 0} {
    set worst_slack [get_property SLACK [lindex $timing_paths 0]]
    if {$worst_slack < 0.0} {
        error "top_adc_dac_loopback 存在建立时间负裕量：$worst_slack ns"
    }
}

set hold_paths [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
if {[llength $hold_paths] > 0} {
    set worst_hold_slack [get_property SLACK [lindex $hold_paths 0]]
    if {$worst_hold_slack < 0.0} {
        error "top_adc_dac_loopback 存在保持时间负裕量：$worst_hold_slack ns"
    }
}

write_bitstream -force [file join $report_dir top_adc_dac_loopback.bit]

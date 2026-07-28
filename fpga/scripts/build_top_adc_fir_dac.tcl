# top_adc_fir_dac任务D综合、实现、DRC、CDC、资源和时序检查脚本。
# 必须从仓库work目录并使用vivado2022运行。
if {![string match "2022.2*" [version -short]]} {
    error "top_adc_fir_dac必须使用Vivado 2022.2构建"
}
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set build_dir  [file join [pwd] top_adc_fir_dac_build]
set report_dir [file join [pwd] top_adc_fir_dac_reports]
set xci_file   [file join $fpga_dir src ip coef_bram coef_bram_ip coef_bram_ip.xci]
file mkdir $report_dir

create_project -force top_adc_fir_dac_build $build_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
if {![file exists $xci_file]} {
    error "未找到src/ip下的coef_bram_ip，请先运行generate_coef_bram_ip.tcl"
}
add_files -norecurse $xci_file
generate_target all [get_ips coef_bram_ip]
create_ip_run [get_files $xci_file]
set ip_run [get_runs -quiet coef_bram_ip_synth_1]
if {[llength $ip_run] != 0} {
    launch_runs $ip_run -jobs 2
    wait_on_run $ip_run
    if {[get_property PROGRESS $ip_run] ne "100%"} {
        error "coef_bram_ip OOC综合未完成"
    }
}

set hdl_files [list \
    [file join $fpga_dir src hdl clock_tree.sv] \
    [file join $fpga_dir src hdl adc_capture.sv] \
    [file join $fpga_dir src hdl dac_output.sv] \
    [file join $fpga_dir src hdl fir_data_adapter.sv] \
    [file join $fpga_dir src hdl adc_decimator_100.v] \
    [file join $fpga_dir src hdl fir_filter.v] \
    [file join $fpga_dir src hdl fir_coef_loader.v] \
    [file join $fpga_dir src hdl coef_bram.sv] \
    [file join $fpga_dir src testmodule top_adc_fir_dac.sv]]
add_files -norecurse $hdl_files
set_property file_type SystemVerilog [get_files [list \
    [file join $fpga_dir src hdl fir_filter.v] \
    [file join $fpga_dir src hdl fir_coef_loader.v] \
    [file join $fpga_dir src hdl adc_decimator_100.v]]]
set_property include_dirs [list [file join $fpga_dir src hdl]] [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse \
    [file join $fpga_dir src constrs top_adc_fir_dac.xdc]
set_property top top_adc_fir_dac [current_fileset]

synth_design -top top_adc_fir_dac -part xc7z020clg400-2
write_checkpoint -force [file join $report_dir post_synth.dcp]
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
report_cdc -details -file [file join $report_dir post_synth_cdc.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose \
    -file [file join $report_dir post_synth_timing_summary.rpt]

set dsp_cells [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]
set bram_cells [get_cells -hierarchical -filter {REF_NAME =~ RAMB*}]
if {[llength $dsp_cells] > 32} {
    error "任务D DSP数量异常：实际[llength $dsp_cells]，期望不超过32"
}
if {[llength $bram_cells] == 0} {
    error "任务D综合后未发现系数Block RAM"
}
puts "TASK_D_POST_SYNTH_DSP_COUNT=[llength $dsp_cells]"
puts "TASK_D_POST_SYNTH_BRAM_COUNT=[llength $bram_cells]"

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
    error "top_adc_fir_dac存在CDC Critical：$critical_cdc"
}
set setup_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {([llength $setup_paths] == 0) || ([get_property SLACK $setup_paths] < 0.0)} {
    error "top_adc_fir_dac存在建立时间违例或没有可检查路径"
}
set hold_paths [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
if {([llength $hold_paths] != 0) && ([get_property SLACK $hold_paths] < 0.0)} {
    error "top_adc_fir_dac存在保持时间违例"
}

puts "TASK_D_WORST_SETUP_SLACK=[get_property SLACK $setup_paths]"
if {[llength $hold_paths] != 0} {
    puts "TASK_D_WORST_HOLD_SLACK=[get_property SLACK $hold_paths]"
}
write_bitstream -force [file join $report_dir top_adc_fir_dac.bit]
close_project

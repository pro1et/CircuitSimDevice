# top_ps_dds完整构建：BD、DDS IP、综合、实现、bitstream和固定XSA。
if {![string match "2022.2*" [version -short]]} {
    error "top_ps_dds必须使用Vivado 2022.2构建"
}

set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set expected_work_dir [file normalize [file join $fpga_dir work]]
if {[file normalize [pwd]] ne $expected_work_dir} {
    error "必须从$expected_work_dir运行；当前目录为[file normalize [pwd]]"
}

set project_dir [file join [pwd] top_ps_dds]
set report_dir  [file join $project_dir reports]
set export_dir  [file join $project_dir exports]
set bd_file     [file join $fpga_dir work CircuitSimDevice CircuitSimDevice.srcs sources_1 bd ps_bram_subsystem_bd ps_bram_subsystem_bd.bd]
set dds_xci     [file join $fpga_dir src ip dds dds_compiler_0 dds_compiler_0.xci]
set top_name    top_ps_dds

if {![file exists $bd_file]} {
    error "缺少BD源文件：$bd_file"
}
if {![file exists $dds_xci]} {
    error "缺少DDS IP：请先运行generate_dds_ip.tcl"
}

file mkdir $report_dir
file mkdir $export_dir
create_project -force top_ps_dds $project_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]

# BD本体来自src；导入一份工程副本，相当于GUI中的“Copy sources into project”。
# output products因此自然位于fpga/work，不会回写或污染版本管理中的权威BD。
import_files -fileset sources_1 -norecurse $bd_file
set bd_obj [get_files -quiet */ps_bram_subsystem_bd.bd]
if {[llength $bd_obj] != 1} {
    error "导入BD后没有得到唯一工程副本：$bd_obj"
}
generate_target all $bd_obj

add_files -norecurse $dds_xci
generate_target all [get_ips dds_compiler_0]

set rtl_files [list \
    [file join $fpga_dir src hdl clock_tree.sv] \
    [file join $fpga_dir src hdl dac_output.sv] \
    [file join $fpga_dir src hdl dds_param_reader.sv] \
    [file join $fpga_dir src hdl dds_freq_ctrl.v] \
    [file join $fpga_dir src hdl dds_wrapper.v] \
    [file join $fpga_dir src hdl ps_bram_subsystem_wrapper.sv] \
    [file join $fpga_dir src testmodule top_ps_dds.sv]]
add_files -norecurse $rtl_files
set_property file_type SystemVerilog [get_files [list \
    [file join $fpga_dir src hdl clock_tree.sv] \
    [file join $fpga_dir src hdl dac_output.sv] \
    [file join $fpga_dir src hdl dds_param_reader.sv] \
    [file join $fpga_dir src hdl ps_bram_subsystem_wrapper.sv] \
    [file join $fpga_dir src testmodule top_ps_dds.sv]]]
set_property include_dirs [list [file join $fpga_dir src hdl]] [get_filesets sources_1]

set xdc_file [file join $fpga_dir src constrs top_ps_dds.xdc]
add_files -fileset constrs_1 -norecurse $xdc_file
set_property top $top_name [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%" ||
    ![string match "synth_design Complete*" [get_property STATUS [get_runs synth_1]]]} {
    error "top_ps_dds综合失败：[get_property STATUS [get_runs synth_1]]"
}
open_run synth_1
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
report_io -file [file join $report_dir post_synth_io.rpt]
report_cdc -details -file [file join $report_dir post_synth_cdc.rpt]
check_timing -verbose -file [file join $report_dir post_synth_check_timing.rpt]
close_design

launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%" ||
    ![string match "write_bitstream Complete*" [get_property STATUS [get_runs impl_1]]]} {
    error "top_ps_dds实现失败：[get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_io -file [file join $report_dir post_route_io.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
report_cdc -details -file [file join $report_dir post_route_cdc.rpt]
report_timing_summary -file [file join $report_dir post_route_timing_summary.rpt]
write_hw_platform -fixed -include_bit -force \
    -file [file join $export_dir top_ps_dds.xsa]

puts "TOP_PS_DDS_BUILD=PASSED"
puts "TOP_PS_DDS_BIT=[get_property DIRECTORY [get_runs impl_1]]/$top_name.bit"
puts "TOP_PS_DDS_XSA=[file join $export_dir top_ps_dds.xsa]"
close_project

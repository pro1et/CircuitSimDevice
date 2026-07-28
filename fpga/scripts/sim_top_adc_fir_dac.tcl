# top_adc_fir_dac任务D集成行为仿真脚本。
# 必须从仓库work目录并使用vivado2022运行。
if {![string match "2022.2*" [version -short]]} {
    error "top_adc_fir_dac必须使用Vivado 2022.2仿真"
}
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set work_dir   [file join [pwd] top_adc_fir_dac_sim]
set xci_file   [file join $fpga_dir src ip coef_bram coef_bram_ip coef_bram_ip.xci]

create_project -force top_adc_fir_dac_sim $work_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
if {![file exists $xci_file]} {
    error "未找到src/ip下的coef_bram_ip，请先运行generate_coef_bram_ip.tcl"
}
add_files -norecurse $xci_file

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

add_files -fileset sim_1 -norecurse [file join $fpga_dir src sim top_adc_fir_dac_tb.sv]
set_property top top_adc_fir_dac_tb [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
set test_passed [get_value -radix bin /top_adc_fir_dac_tb/test_passed]
if {$test_passed ne "1"} {
    error "top_adc_fir_dac自检未通过"
}
close_sim -force
close_project

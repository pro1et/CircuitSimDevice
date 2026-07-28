# fir_filter分时MAC实现的独立行为仿真脚本。
# 必须从仓库work目录并使用vivado2022运行，确保生成文件不离开work。
if {![string match "2022.2*" [version -short]]} {
    error "fir_filter必须使用Vivado 2022.2仿真"
}
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set work_dir   [file join [pwd] fir_filter_sim]

create_project -force fir_filter_sim $work_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
add_files -norecurse [file join $fpga_dir src hdl params.vh]
add_files -norecurse [file join $fpga_dir src hdl fir_filter.v]
set_property file_type SystemVerilog [get_files [file join $fpga_dir src hdl fir_filter.v]]
add_files -fileset sim_1 -norecurse [file join $fpga_dir src sim fir_filter_tb.sv]
set_property top fir_filter_tb [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
run all
set test_passed [get_value -radix bin /fir_filter_tb/test_passed]
if {$test_passed ne "1"} {
    error "fir_filter自检未通过"
}
close_sim -force
close_project

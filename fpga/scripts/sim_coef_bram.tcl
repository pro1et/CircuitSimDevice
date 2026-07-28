# coef_bram独立行为仿真脚本，必须从仓库work目录调用。
if {![string match "2022.2*" [version -short]]} {
    error "coef_bram必须使用Vivado 2022.2仿真"
}
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set work_dir   [file join [pwd] coef_bram_sim]
set xci_file   [file join $fpga_dir src ip coef_bram coef_bram_ip coef_bram_ip.xci]

create_project -force coef_bram_sim $work_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]

if {![file exists $xci_file]} {
    error "未找到src/ip下的coef_bram_ip，请先运行generate_coef_bram_ip.tcl"
}
add_files -norecurse $xci_file

add_files -norecurse [file join $fpga_dir src hdl coef_bram.sv]
add_files -norecurse [file join $fpga_dir src hdl fir_coef_loader.v]
add_files -fileset sim_1 -norecurse [file join $fpga_dir src sim coef_bram_tb.sv]
set_property top coef_bram_tb [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
run all
set test_passed [get_value -radix bin /coef_bram_tb/test_passed]
if {$test_passed ne "1"} {
    error "coef_bram自检未通过"
}
close_sim -force
close_project

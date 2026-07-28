if {![string match "2022.2*" [version -short]]} {
    error "dds_param_reader必须使用Vivado 2022.2仿真"
}

set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set expected_work_dir [file normalize [file join $fpga_dir work]]
if {[file normalize [pwd]] ne $expected_work_dir} {
    error "必须从$expected_work_dir运行；当前目录为[file normalize [pwd]]"
}

set project_dir [file join [pwd] dds_param_reader_sim]
create_project -force dds_param_reader_sim $project_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]

add_files -norecurse [file join $fpga_dir src hdl dds_param_reader.sv]
add_files -fileset sim_1 -norecurse [file join $fpga_dir src sim dds_param_reader_tb.sv]
set_property include_dirs [list [file join $fpga_dir src hdl]] [get_filesets sources_1]
set_property include_dirs [list [file join $fpga_dir src hdl]] [get_filesets sim_1]
set_property top dds_param_reader_tb [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
run all
set passed [get_value -radix bin /dds_param_reader_tb/test_passed]
if {$passed ne "1"} {
    error "dds_param_reader自检未通过"
}
puts "DDS_PARAM_READER_SIM=PASSED"
close_sim
close_project

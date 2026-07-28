# dac_interpolator_100独立行为仿真脚本；必须从fpga/work运行。
if {[version -short] ne "2022.2"} {
    error "dac_interpolator_100必须使用Vivado 2022.2仿真"
}

set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set work_dir   [file join [pwd] dac_interpolator_100_sim]

create_project -force dac_interpolator_100_sim $work_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
add_files -norecurse [file join $fpga_dir src hdl dac_interpolator_100.sv]
add_files -fileset sim_1 -norecurse [file join $fpga_dir src sim dac_interpolator_100_tb.sv]
set_property top dac_interpolator_100_tb [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
run 50 us
set test_passed [get_value -radix bin /dac_interpolator_100_tb/test_passed]
if {$test_passed ne "1"} {
    error "dac_interpolator_100自检未通过"
}
close_sim -force
close_project

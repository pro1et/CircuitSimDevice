# dac_output 独立仿真脚本。
# 必须从仓库 fpga/work 目录调用 Vivado，确保所有生成文件留在 work 内。

set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set work_dir   [file join [pwd] dac_output_sim]

create_project -force dac_output_sim $work_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]

add_files -norecurse [file join $fpga_dir src hdl dac_output.sv]
add_files -fileset sim_1 -norecurse [file join $fpga_dir src sim dac_output_tb.sv]
set_property top dac_output_tb [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
run 1 us
set test_passed [get_value -radix bin /dac_output_tb/test_passed]
if {$test_passed ne "1"} {
    error "dac_output 自检未通过"
}
close_sim -force
close_project

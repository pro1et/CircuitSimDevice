# fir_data_adapter 独立行为仿真脚本。
# 必须从仓库 work 目录调用 Vivado，确保全部生成文件位于 work 内。

set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set work_dir  [file join [pwd] fir_data_adapter_sim]

create_project -force fir_data_adapter_sim $work_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]

add_files -norecurse [file join $fpga_dir src hdl fir_data_adapter.sv]
add_files -fileset sim_1 -norecurse [file join $fpga_dir src sim fir_data_adapter_tb.sv]
set_property top fir_data_adapter_tb [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
run all
set test_passed [get_value -radix bin /fir_data_adapter_tb/test_passed]
if {$test_passed ne "1"} {
    error "fir_data_adapter 自检未通过"
}
close_sim -force
close_project

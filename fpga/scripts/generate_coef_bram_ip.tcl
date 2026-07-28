# 使用仓库规定的Vivado版本重新生成coef_bram_ip。
# 必须从仓库work目录运行；IP核保存到fpga/src/ip，其余工程产物保存在work。
if {![string match "2022.2*" [version -short]]} {
    error "coef_bram_ip必须使用Vivado 2022.2生成"
}
set script_dir  [file dirname [file normalize [info script]]]
set fpga_dir    [file dirname $script_dir]
set project_dir [file join [pwd] coef_bram_ip_gen]
set core_dir    [file join $fpga_dir src ip coef_bram]
set ip_dir      [file join $core_dir coef_bram_ip]
set coe_file    [file join $core_dir fir_bandpass_10k_25k.coe]

if {[file exists $ip_dir]} {
    file delete -force $ip_dir
}

create_project -force coef_bram_ip_gen $project_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
source [file join $script_dir create_coef_bram_ip.tcl]
create_coef_bram_ip $core_dir $coe_file
set ip_summary_log [file join $ip_dir summary.log]
if {[file exists $ip_summary_log]} {
    file delete -force $ip_summary_log
}
close_project

# coef_bram独立综合、时序、CDC和资源检查脚本，必须从仓库work目录调用。
if {![string match "2022.2*" [version -short]]} {
    error "coef_bram必须使用Vivado 2022.2综合"
}
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set build_dir  [file join [pwd] coef_bram_synth]
set report_dir [file join [pwd] coef_bram_reports]
set xci_file   [file join $fpga_dir src ip coef_bram coef_bram_ip coef_bram_ip.xci]
file mkdir $report_dir

create_project -force coef_bram_synth $build_dir -part xc7z020clg400-2
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
}
add_files -norecurse [file join $fpga_dir src hdl coef_bram.sv]
set_property top coef_bram [current_fileset]

synth_design -top coef_bram -part xc7z020clg400-2 -mode out_of_context
create_clock -name clka -period 10.000 [get_ports clka]
create_clock -name clkb -period 14.000 [get_ports clkb]
set_clock_groups -asynchronous -group [get_clocks clka] -group [get_clocks clkb]
set_input_delay  -max 1.000 -clock clka [get_ports {rsta ena wea[*] addra[*] dina[*]}]
set_input_delay  -min 0.000 -clock clka [get_ports {rsta ena wea[*] addra[*] dina[*]}]
set_output_delay -max 1.000 -clock clka [get_ports {douta[*] addra_error}]
set_output_delay -min 0.000 -clock clka [get_ports {douta[*] addra_error}]
set_input_delay  -max 1.000 -clock clkb [get_ports {rstb enb web[*] addrb[*] dinb[*]}]
set_input_delay  -min 0.000 -clock clkb [get_ports {rstb enb web[*] addrb[*] dinb[*]}]
set_output_delay -max 1.000 -clock clkb [get_ports {doutb[*] addrb_error}]
set_output_delay -min 0.000 -clock clkb [get_ports {doutb[*] addrb_error}]
# OOC综合无法知道最终顶层在模块边界提供的最小延迟；仅屏蔽边界hold检查，
# RAM内部时序仍正常检查。最终hold必须在完整顶层布局布线后复核。
set_false_path -hold -from [get_ports {rsta ena wea[*] addra[*] dina[*]}]
set_false_path -hold -from [get_ports {rstb enb web[*] addrb[*] dinb[*]}]
set_false_path -hold -to [get_ports {douta[*] addra_error doutb[*] addrb_error}]

report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose \
    -file [file join $report_dir timing_summary.rpt]
report_cdc -details -file [file join $report_dir cdc.rpt]

if {[llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB*}]] == 0} {
    error "coef_bram综合后未发现RAMB原语"
}
set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_path  [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
if {([llength $setup_path] == 0) || ([get_property SLACK $setup_path] < 0.0)} {
    error "coef_bram存在setup时序违例或没有可检查的setup路径"
}
if {([llength $hold_path] != 0) && ([get_property SLACK $hold_path] < 0.0)} {
    error "coef_bram存在setup或hold时序违例"
}
close_project

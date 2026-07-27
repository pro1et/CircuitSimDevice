# adc_capture 独立综合与静态检查脚本。
# 必须从仓库 fpga/work 目录调用 Vivado，确保所有生成文件留在 work 内。

set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set report_dir [file join [pwd] adc_capture_reports]
file mkdir $report_dir

read_verilog -sv [file join $fpga_dir src hdl clock_tree.sv]
read_verilog -sv [file join $fpga_dir src hdl adc_capture.sv]
read_verilog -sv [file join $fpga_dir src sim adc_capture_check_top.sv]
synth_design -top adc_capture_check_top -part xc7z020clg400-2

create_clock -name clk_50m -period 20.000 [get_ports clk_50m]
set adc_launch_pin [get_pins -hier -filter {REF_PIN_NAME == CLKOUT2}]
set adc_launch_clock [get_clocks -of_objects $adc_launch_pin]
if {[llength $adc_launch_clock] != 1} {
    error "无法唯一确定 ADC 驱动时钟：$adc_launch_clock"
}
set_input_delay -clock $adc_launch_clock -min 0.000 \
    [get_ports {adc_data_a[*] adc_data_b[*]}]
set_input_delay -clock $adc_launch_clock -max 25.000 \
    [get_ports {adc_data_a[*] adc_data_b[*]}]
set_false_path -from [get_ports rst_n]

report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose \
    -file [file join $report_dir timing_summary.rpt]
report_cdc -details -file [file join $report_dir cdc.rpt]

set critical_cdc [get_cdc_violations -quiet -filter {SEVERITY == Critical}]
if {[llength $critical_cdc] > 0} {
    error "adc_capture 存在 CDC Critical：$critical_cdc"
}

foreach delay_type {max min} {
    set timing_paths [get_timing_paths -delay_type $delay_type -max_paths 1 -nworst 1]
    if {[llength $timing_paths] > 0} {
        set worst_slack [get_property SLACK [lindex $timing_paths 0]]
        if {$worst_slack < 0.0} {
            error "adc_capture 存在 $delay_type 负时序裕量：$worst_slack ns"
        }
    }
}

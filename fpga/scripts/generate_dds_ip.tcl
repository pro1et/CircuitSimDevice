# 使用Vivado 2022.2生成top_ps_dds所需DDS Compiler IP。
if {![string match "2022.2*" [version -short]]} {
    error "DDS IP必须使用Vivado 2022.2生成"
}

set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set expected_work_dir [file normalize [file join $fpga_dir work]]
if {[file normalize [pwd]] ne $expected_work_dir} {
    error "必须从$expected_work_dir运行；当前目录为[file normalize [pwd]]"
}

set project_dir [file join [pwd] dds_ip_gen]
set ip_root     [file join $fpga_dir src ip dds]
set xci_file    [file join $ip_root dds_compiler_0 dds_compiler_0.xci]

create_project -force dds_ip_gen $project_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
file mkdir $ip_root

if {[file exists $xci_file]} {
    add_files -norecurse $xci_file
    set ip [get_ips dds_compiler_0]
} else {
    create_ip -name dds_compiler -vendor xilinx.com -library ip -version 6.0 \
        -module_name dds_compiler_0 -dir $ip_root
    set ip [get_ips dds_compiler_0]
}

# 与工程宏一致：30 MHz时钟、27位相位累加器、8位正弦/余弦、可编程PINC。
set_property -dict [list \
    CONFIG.PartsPresent {Phase_Generator_and_SIN_COS_LUT} \
    CONFIG.DDS_Clock_Rate {30} \
    CONFIG.Channels {1} \
    CONFIG.Mode_of_Operation {Standard} \
    CONFIG.Parameter_Entry {System_Parameters} \
    CONFIG.Spurious_Free_Dynamic_Range {45} \
    CONFIG.Frequency_Resolution {0.4} \
    CONFIG.Noise_Shaping {Auto} \
    CONFIG.Phase_Width {27} \
    CONFIG.Output_Width {8} \
    CONFIG.Phase_Increment {Programmable} \
    CONFIG.Phase_offset {Fixed} \
    CONFIG.Output_Selection {Sine_and_Cosine} \
    CONFIG.OUTPUT_FORM {Twos_Complement} \
    CONFIG.Has_Phase_Out {true} \
    CONFIG.Has_TREADY {false} \
    CONFIG.Has_ARESETn {false} \
    CONFIG.Has_ACLKEN {false}] $ip

generate_target all $ip
export_ip_user_files -of_objects $ip -no_script -sync -force -quiet
puts "DDS_IP_XCI=$xci_file"
close_project

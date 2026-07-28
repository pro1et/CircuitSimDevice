# 创建供coef_bram封装使用的Vivado Block Memory Generator IP。
# 调用者必须先创建或打开工程，并把生成目录放在仓库work目录内。

proc create_coef_bram_ip {output_dir coe_file} {
    file mkdir $output_dir

    if {[llength [get_ips -quiet coef_bram_ip]] != 0} {
        delete_ip [get_ips coef_bram_ip]
    }

    create_ip -name blk_mem_gen -vendor xilinx.com -library ip \
        -module_name coef_bram_ip -dir $output_dir

    set ip [get_ips coef_bram_ip]
    set_property -dict [list \
        CONFIG.Memory_Type {True_Dual_Port_RAM} \
        CONFIG.Write_Width_A {32} \
        CONFIG.Read_Width_A {32} \
        CONFIG.Write_Depth_A {1024} \
        CONFIG.Write_Width_B {32} \
        CONFIG.Read_Width_B {32} \
        CONFIG.Use_Byte_Write_Enable {true} \
        CONFIG.Byte_Size {8} \
        CONFIG.Operating_Mode_A {READ_FIRST} \
        CONFIG.Operating_Mode_B {READ_FIRST} \
        CONFIG.Enable_A {Use_ENA_Pin} \
        CONFIG.Enable_B {Use_ENB_Pin} \
        CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
        CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
        CONFIG.Use_RSTA_Pin {true} \
        CONFIG.Use_RSTB_Pin {true} \
        CONFIG.EN_SAFETY_CKT {false} \
        CONFIG.Assume_Synchronous_Clk {false} \
        CONFIG.Load_Init_File {true} \
        CONFIG.Coe_File [file normalize $coe_file] \
        CONFIG.Fill_Remaining_Memory_Locations {true} \
        CONFIG.Remaining_Memory_Locations {0}] $ip

    generate_target all $ip
    return $ip
}

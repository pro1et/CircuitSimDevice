# ============================================================================
# PS-AXI-三BRAM通信子系统创建、校验、wrapper生成、综合与XSA导出脚本
#
# 使用方法：
#   必须从仓库work目录，在conda环境vivado2022中运行：
#   vivado -mode batch -source ../fpga/scripts/build_ps_bram_subsystem.tcl
#
# 设计边界：
#   PS7 M_AXI_GP0 -> AXI Interconnect -> 三个AXI BRAM Controller -> 三块TDP BRAM。
#   Port A属于100 MHz AXI时钟域；Port B以角色受限的独立HDL端口导出给PL。
#   IQ端只导出写接口，FIR/参数端只导出读接口，从结构上减少双写者误用。
#
# 生成位置：
#   工程、BD、自动wrapper、综合结果、地址报告和XSA全部位于work目录。
#   本Tcl脚本是可重复创建BD的长期源文件，不依赖work中已有工程。
# ============================================================================
if {![string match "2022.2*" [version -short]]} {
    error "PS-BRAM子系统必须使用Vivado 2022.2构建"
}

set script_dir  [file dirname [file normalize [info script]]]
set fpga_dir    [file dirname $script_dir]
set project_dir [file join [pwd] ps_bram_subsystem]
set export_dir  [file join $project_dir exports]
set report_dir  [file join $project_dir reports]
set part_name   xc7z020clg400-2
set bd_name     ps_bram_subsystem_bd

file mkdir $export_dir
file mkdir $report_dir
create_project -force ps_bram_subsystem $project_dir -part $part_name
set_property target_language Verilog [current_project]
create_bd_design $bd_name

# ----------------------------------------------------------------------------
# 固定地址和容量。地址按64 KiB边界分隔，便于长期扩展且避免相互重叠。
# ----------------------------------------------------------------------------
set IQ_BASE     0x40000000
set IQ_RANGE    32K
set FIR_BASE    0x40010000
set FIR_RANGE   4K
set PARAM_BASE  0x40020000
set PARAM_RANGE 4K
set BRAM_DATA_WIDTH  32
set IQ_DEPTH_WORDS    8192
set FIR_DEPTH_WORDS   1024
set PARAM_DEPTH_WORDS 1024

# ----------------------------------------------------------------------------
# Processing System 7
# 手册确认Mizar Z7020为33.333333 MHz PS时钟、1 GB/32-bit DDR3，器件为两片
# MT41J256M16RE-125。Vivado本机没有Mizar board preset，因此这里只设置能够从
# 手册确认的器件、宽度和频率；DDR PCB走线时延仍需厂商preset或实测确认。
# ----------------------------------------------------------------------------
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:* ps7]
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_UIPARAM_DDR_ENABLE {1} \
    CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J256M16 RE-125} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333}] $ps7

make_bd_intf_pins_external [get_bd_intf_pins $ps7/DDR]
set_property name DDR [get_bd_intf_ports DDR_0]
make_bd_intf_pins_external [get_bd_intf_pins $ps7/FIXED_IO]
set_property name FIXED_IO [get_bd_intf_ports FIXED_IO_0]

# ----------------------------------------------------------------------------
# AXI互连、统一时钟和复位
# ----------------------------------------------------------------------------
set axi_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:* axi_interconnect_0]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {3}] $axi_ic

set ps_reset [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst_ps7_0_100M]
set const_zero_1 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* const_zero_1]
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] $const_zero_1

connect_bd_intf_net [get_bd_intf_pins $ps7/M_AXI_GP0] [get_bd_intf_pins $axi_ic/S00_AXI]
connect_bd_net [get_bd_pins $ps7/FCLK_CLK0] \
    [get_bd_pins $ps7/M_AXI_GP0_ACLK] \
    [get_bd_pins $axi_ic/ACLK] \
    [get_bd_pins $axi_ic/S00_ACLK] \
    [get_bd_pins $axi_ic/M00_ACLK] \
    [get_bd_pins $axi_ic/M01_ACLK] \
    [get_bd_pins $axi_ic/M02_ACLK] \
    [get_bd_pins $ps_reset/slowest_sync_clk]
connect_bd_net [get_bd_pins $ps7/FCLK_RESET0_N] [get_bd_pins $ps_reset/ext_reset_in]
connect_bd_net [get_bd_pins $const_zero_1/dout] \
    [get_bd_pins $ps_reset/aux_reset_in] \
    [get_bd_pins $ps_reset/mb_debug_sys_rst]
connect_bd_net [get_bd_pins $ps_reset/interconnect_aresetn] [get_bd_pins $axi_ic/ARESETN]
connect_bd_net [get_bd_pins $ps_reset/peripheral_aresetn] \
    [get_bd_pins $axi_ic/S00_ARESETN] \
    [get_bd_pins $axi_ic/M00_ARESETN] \
    [get_bd_pins $axi_ic/M01_ARESETN] \
    [get_bd_pins $axi_ic/M02_ARESETN]

# ----------------------------------------------------------------------------
# 创建一组AXI BRAM Controller + True Dual Port BRAM，并连接AXI Port A。
# ----------------------------------------------------------------------------
proc create_axi_bram_pair {role data_width depth axi_master_pin} {
    set ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:* axi_bram_ctrl_$role]
    set_property -dict [list \
        CONFIG.DATA_WIDTH $data_width \
        CONFIG.SINGLE_PORT_BRAM {1} \
        CONFIG.ECC_TYPE {0}] $ctrl

    set mem [create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:* bram_$role]
    set_property -dict [list \
        CONFIG.Memory_Type {True_Dual_Port_RAM} \
        CONFIG.Write_Width_A $data_width \
        CONFIG.Read_Width_A $data_width \
        CONFIG.Write_Depth_A $depth \
        CONFIG.Write_Width_B $data_width \
        CONFIG.Read_Width_B $data_width \
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
        CONFIG.Assume_Synchronous_Clk {false} \
        CONFIG.Load_Init_File {false}] $mem

    connect_bd_intf_net [get_bd_intf_pins $axi_master_pin] [get_bd_intf_pins $ctrl/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins $ctrl/BRAM_PORTA] [get_bd_intf_pins $mem/BRAM_PORTA]
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins $ctrl/s_axi_aclk]
    connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] [get_bd_pins $ctrl/s_axi_aresetn]
}

create_axi_bram_pair iq    $BRAM_DATA_WIDTH $IQ_DEPTH_WORDS    axi_interconnect_0/M00_AXI
create_axi_bram_pair fir   $BRAM_DATA_WIDTH $FIR_DEPTH_WORDS   axi_interconnect_0/M01_AXI
create_axi_bram_pair param $BRAM_DATA_WIDTH $PARAM_DEPTH_WORDS axi_interconnect_0/M02_AXI

# ----------------------------------------------------------------------------
# PL侧固定HDL接口。
# 地址统一为BRAM窗口内的32位字节偏移。BMG接入BRAM Controller后，原生端口
# 同样采用字节地址约定，因此PL地址直接连接，禁止再次右移或去掉低2位。
# IQ只导出写端；FIR和参数只导出读端，从硬件结构上执行PL侧方向约束。
# ----------------------------------------------------------------------------
proc create_common_pl_ports {role} {
    # 当前数据通路为30 MHz；此处的频率是BD时序元数据。最终上层若改用其他
    # Port-B时钟，必须同步修改该元数据和顶层时序约束。
    set clk_port  [create_bd_port -dir I -type clk -freq_hz 30000000 ${role}_pl_clk]
    set rst_port  [create_bd_port -dir I -type rst ${role}_pl_rst]
    set_property CONFIG.POLARITY {ACTIVE_HIGH} $rst_port
    create_bd_port -dir I ${role}_pl_en
    create_bd_port -dir I -from 31 -to 0 ${role}_pl_addr
}

create_common_pl_ports iq
create_bd_port -dir I -from 3 -to 0 iq_pl_we
create_bd_port -dir I -from 31 -to 0 iq_pl_wdata
connect_bd_net [get_bd_ports iq_pl_clk]   [get_bd_pins bram_iq/clkb]
connect_bd_net [get_bd_ports iq_pl_rst]   [get_bd_pins bram_iq/rstb]
connect_bd_net [get_bd_ports iq_pl_en]    [get_bd_pins bram_iq/enb]
connect_bd_net [get_bd_ports iq_pl_we]    [get_bd_pins bram_iq/web]
connect_bd_net [get_bd_ports iq_pl_wdata] [get_bd_pins bram_iq/dinb]
connect_bd_net [get_bd_ports iq_pl_addr]  [get_bd_pins bram_iq/addrb]

set const_zero_4 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* const_zero_4]
set_property -dict [list CONFIG.CONST_WIDTH {4} CONFIG.CONST_VAL {0}] $const_zero_4
set const_zero_32 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* const_zero_32]
set_property -dict [list CONFIG.CONST_WIDTH {32} CONFIG.CONST_VAL {0}] $const_zero_32

proc connect_pl_read_port {role} {
    create_common_pl_ports $role
    create_bd_port -dir O -from 31 -to 0 ${role}_pl_rdata
    connect_bd_net [get_bd_ports ${role}_pl_clk] [get_bd_pins bram_${role}/clkb]
    connect_bd_net [get_bd_ports ${role}_pl_rst] [get_bd_pins bram_${role}/rstb]
    connect_bd_net [get_bd_ports ${role}_pl_en]  [get_bd_pins bram_${role}/enb]
    connect_bd_net [get_bd_ports ${role}_pl_addr] [get_bd_pins bram_${role}/addrb]
    connect_bd_net [get_bd_pins const_zero_4/dout] [get_bd_pins bram_${role}/web]
    connect_bd_net [get_bd_pins const_zero_32/dout] [get_bd_pins bram_${role}/dinb]
    connect_bd_net [get_bd_pins bram_${role}/doutb] [get_bd_ports ${role}_pl_rdata]
}

connect_pl_read_port fir
connect_pl_read_port param

# ----------------------------------------------------------------------------
# 固定Address Editor映射。
# ----------------------------------------------------------------------------
assign_bd_address -offset $IQ_BASE -range $IQ_RANGE \
    -target_address_space [get_bd_addr_spaces ps7/Data] \
    [get_bd_addr_segs axi_bram_ctrl_iq/S_AXI/Mem0] -force
assign_bd_address -offset $FIR_BASE -range $FIR_RANGE \
    -target_address_space [get_bd_addr_spaces ps7/Data] \
    [get_bd_addr_segs axi_bram_ctrl_fir/S_AXI/Mem0] -force
assign_bd_address -offset $PARAM_BASE -range $PARAM_RANGE \
    -target_address_space [get_bd_addr_spaces ps7/Data] \
    [get_bd_addr_segs axi_bram_ctrl_param/S_AXI/Mem0] -force

validate_bd_design
save_bd_design

# Vivado 2022.2没有report_bd_address命令，直接从Address Editor对象读取并记录
# 工具实际接受的OFFSET/RANGE，避免报告只是重复脚本常量。
set addr_report [open [file join $report_dir address_map.rpt] w]
puts $addr_report "PS7 Data Address Space"
puts $addr_report "role,segment,offset,range"
foreach {role seg_name} [list \
    IQ    ps7/Data/SEG_axi_bram_ctrl_iq_Mem0 \
    FIR   ps7/Data/SEG_axi_bram_ctrl_fir_Mem0 \
    PARAM ps7/Data/SEG_axi_bram_ctrl_param_Mem0] {
    set seg [get_bd_addr_segs $seg_name]
    puts $addr_report [format "%s,%s,%s,%s" \
        $role $seg_name [get_property OFFSET $seg] [get_property RANGE $seg]]
}
close $addr_report

set bd_file [get_files [file join $project_dir ps_bram_subsystem.srcs sources_1 bd $bd_name $bd_name.bd]]
generate_target all $bd_file
set wrapper_files [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper_files
set stable_wrapper [file join $fpga_dir src hdl ps_bram_subsystem_wrapper.sv]
if {![file exists $stable_wrapper]} {
    error "缺少稳定HDL wrapper：$stable_wrapper"
}
add_files -norecurse $stable_wrapper
set_property file_type SystemVerilog [get_files $stable_wrapper]
set wrapper_name ps_bram_subsystem_wrapper
set_property top $wrapper_name [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 2
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {[get_property PROGRESS [get_runs synth_1]] ne "100%" ||
    ![string match "synth_design Complete*" $synth_status]} {
    error "PS-BRAM子系统综合失败：$synth_status"
}
open_run synth_1
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
report_cdc -details -file [file join $report_dir post_synth_cdc.rpt]
check_timing -verbose -file [file join $report_dir post_synth_check_timing.rpt]
report_timing_summary -file [file join $report_dir post_synth_timing_summary.rpt]
close_design

write_hw_platform -fixed -force -file [file join $export_dir ps_bram_subsystem.xsa]

puts "PS_BRAM_SUBSYSTEM_BD_VALIDATE=PASSED"
puts "PS_BRAM_SUBSYSTEM_ADDRESS_IQ=$IQ_BASE/$IQ_RANGE"
puts "PS_BRAM_SUBSYSTEM_ADDRESS_FIR=$FIR_BASE/$FIR_RANGE"
puts "PS_BRAM_SUBSYSTEM_ADDRESS_PARAM=$PARAM_BASE/$PARAM_RANGE"
puts "PS_BRAM_SUBSYSTEM_WRAPPER=$wrapper_files"
puts "PS_BRAM_SUBSYSTEM_STABLE_WRAPPER=$stable_wrapper"
puts "PS_BRAM_SUBSYSTEM_XSA=[file join $export_dir ps_bram_subsystem.xsa]"
close_project

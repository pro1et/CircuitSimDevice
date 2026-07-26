# Rebuild the PS-PL shared-BRAM Block Design.
# This script is repository-managed; generated BD/IP files remain under work/.

namespace eval ps_pl_bram_tcl {
proc script_dir {} {
    return [file dirname [file normalize [info script]]]
}

proc require_single {description objects} {
    if {[llength $objects] != 1} {
        error "Expected exactly one $description, found [llength $objects]"
    }
    return [lindex $objects 0]
}

proc clear_design {} {
    # Remove nets first so Vivado does not retain dangling, auto-numbered nets
    # when the same design is rebuilt in place.
    set interface_nets [get_bd_intf_nets -quiet]
    if {[llength $interface_nets] != 0} {
        delete_bd_objs $interface_nets
    }
    set scalar_nets [get_bd_nets -quiet]
    if {[llength $scalar_nets] != 0} {
        delete_bd_objs $scalar_nets
    }
    # Interface ports own scalar member ports. Delete them first, then query
    # the remaining objects again so members are not passed twice.
    set interface_ports [get_bd_intf_ports -quiet]
    if {[llength $interface_ports] != 0} {
        delete_bd_objs $interface_ports
    }
    set scalar_ports [get_bd_ports -quiet]
    if {[llength $scalar_ports] != 0} {
        delete_bd_objs $scalar_ports
    }
    set cells [get_bd_cells -quiet]
    if {[llength $cells] != 0} {
        delete_bd_objs $cells
    }
}
}

set script_dir [ps_pl_bram_tcl::script_dir]
set project_root_dir [file normalize "$script_dir/.."]
set expected_vivado_version 2025.2
set design_name ps_pl_bram

if {[string first $expected_vivado_version [version -short]] == -1} {
    error "Expected Vivado $expected_vivado_version, found [version -short]"
}

if {[llength [get_projects -quiet]] == 0} {
    set managed_xpr [file normalize \
        "$project_root_dir/work/CircuitSimDevice/CircuitSimDevice.xpr"]
    set legacy_xpr [file normalize \
        "$project_root_dir/work/CircuitSimDevice.xpr"]
    if {[file isfile $managed_xpr]} {
        open_project $managed_xpr
    } elseif {[file isfile $legacy_xpr]} {
        open_project $legacy_xpr
    } else {
        create_project CircuitSimDevice \
            [file normalize "$project_root_dir/work/CircuitSimDevice"] \
            -part xc7z020clg400-2
    }
}

if {[get_property PART [current_project]] ne "xc7z020clg400-2"} {
    error "The shared-BRAM design requires xc7z020clg400-2"
}

set required_ips [list \
    xilinx.com:ip:processing_system7:5.5 \
    xilinx.com:ip:smartconnect:1.0 \
    xilinx.com:ip:axi_bram_ctrl:4.1 \
    xilinx.com:ip:blk_mem_gen:8.4 \
    xilinx.com:ip:proc_sys_reset:5.0]

foreach vlnv $required_ips {
    if {[llength [get_ipdefs -all -quiet $vlnv]] == 0} {
        error "Required IP is not available: $vlnv"
    }
}

set existing_bd [get_files -quiet -norecurse ${design_name}.bd]
if {[llength $existing_bd] > 1} {
    error "More than one ${design_name}.bd is registered in the project"
} elseif {[llength $existing_bd] == 1} {
    open_bd_design [lindex $existing_bd 0]
    current_bd_design $design_name
    ps_pl_bram_tcl::clear_design
} else {
    create_bd_design $design_name
    current_bd_design $design_name
}

# External PS interfaces.
set DDR [create_bd_intf_port \
    -mode Master \
    -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR]
set FIXED_IO [create_bd_intf_port \
    -mode Master \
    -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO]

# Processing system. Retain the board's existing DDR/QSPI/SD/UART settings,
# expose only M_AXI_GP0, and deliberately disable the PL interrupt interface.
set ps7 [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
set_property -dict [list \
    CONFIG.PCW_DDR_RAM_HIGHADDR {0x3FFFFFFF} \
    CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_CLK0_FREQ {100000000} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_GP0 {0} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {0} \
    CONFIG.PCW_IRQ_F2P_INTR {0} \
    CONFIG.PCW_EN_GPIO {0} \
    CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {0} \
    CONFIG.PCW_EN_QSPI {1} \
    CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_QSPI_PERIPHERAL_FREQMHZ {200} \
    CONFIG.PCW_QSPI_QSPI_IO {MIO 1 .. 6} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_IO {MIO 1 .. 6} \
    CONFIG.PCW_SINGLE_QSPI_DATA_MODE {x4} \
    CONFIG.PCW_EN_SDIO0 {1} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
    CONFIG.PCW_SDIO_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_SDIO_PERIPHERAL_VALID {1} \
    CONFIG.PCW_EN_UART0 {0} \
    CONFIG.PCW_EN_UART1 {1} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
    CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_UART_PERIPHERAL_VALID {1} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ {533.333374} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J256M16 RE-125}] $ps7

set axi_mem_interconnect [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:smartconnect:1.0 axi_mem_interconnect]
set_property -dict [list \
    CONFIG.NUM_SI {1} \
    CONFIG.NUM_MI {2}] $axi_mem_interconnect

set meas_bram_ctrl [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 meas_bram_ctrl]
set_property -dict [list \
    CONFIG.DATA_WIDTH {32} \
    CONFIG.SINGLE_PORT_BRAM {1} \
    CONFIG.READ_LATENCY {1} \
    CONFIG.ECC_TYPE {0}] $meas_bram_ctrl

set coeff_bram_ctrl [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 coeff_bram_ctrl]
set_property -dict [list \
    CONFIG.DATA_WIDTH {32} \
    CONFIG.SINGLE_PORT_BRAM {1} \
    CONFIG.READ_LATENCY {1} \
    CONFIG.ECC_TYPE {0}] $coeff_bram_ctrl

set meas_bram [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:blk_mem_gen:8.4 meas_bram]
set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Assume_Synchronous_Clk {false} \
    CONFIG.Enable_32bit_Address {true} \
    CONFIG.Write_Width_A {32} \
    CONFIG.Read_Width_A {32} \
    CONFIG.Write_Width_B {32} \
    CONFIG.Read_Width_B {32} \
    CONFIG.Write_Depth_A {8192} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File {false} \
    CONFIG.use_bram_block {BRAM_Controller}] $meas_bram

set coeff_bram [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:blk_mem_gen:8.4 coeff_bram]
set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Assume_Synchronous_Clk {false} \
    CONFIG.Enable_32bit_Address {true} \
    CONFIG.Write_Width_A {32} \
    CONFIG.Read_Width_A {32} \
    CONFIG.Write_Width_B {32} \
    CONFIG.Read_Width_B {32} \
    CONFIG.Write_Depth_A {1024} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File {false} \
    CONFIG.use_bram_block {BRAM_Controller}] $coeff_bram

set rst_ps7_fclk0 [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_fclk0]

# AXI and BRAM Port A connections.
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] \
    [get_bd_intf_pins axi_mem_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_mem_interconnect/M00_AXI] \
    [get_bd_intf_pins meas_bram_ctrl/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_mem_interconnect/M01_AXI] \
    [get_bd_intf_pins coeff_bram_ctrl/S_AXI]
connect_bd_intf_net [get_bd_intf_pins meas_bram_ctrl/BRAM_PORTA] \
    [get_bd_intf_pins meas_bram/BRAM_PORTA]
connect_bd_intf_net [get_bd_intf_pins coeff_bram_ctrl/BRAM_PORTA] \
    [get_bd_intf_pins coeff_bram/BRAM_PORTA]
connect_bd_intf_net [get_bd_intf_ports DDR] [get_bd_intf_pins ps7/DDR]
connect_bd_intf_net [get_bd_intf_ports FIXED_IO] [get_bd_intf_pins ps7/FIXED_IO]

# Port B remains a native BRAM interface outside the BD. Create explicitly
# named ports because make_bd_intf_pins_external does not return an object in
# all supported Vivado releases.
set meas_pl_port [create_bd_intf_port \
    -mode Slave \
    -vlnv xilinx.com:interface:bram_rtl:1.0 MEAS_BRAM_PL]
set_property CONFIG.MASTER_TYPE {BRAM_CTRL} $meas_pl_port
connect_bd_intf_net $meas_pl_port [get_bd_intf_pins meas_bram/BRAM_PORTB]
set coeff_pl_port [create_bd_intf_port \
    -mode Slave \
    -vlnv xilinx.com:interface:bram_rtl:1.0 COEFF_BRAM_PL]
set_property CONFIG.MASTER_TYPE {BRAM_CTRL} $coeff_pl_port
connect_bd_intf_net $coeff_pl_port [get_bd_intf_pins coeff_bram/BRAM_PORTB]

# One 100 MHz AXI clock domain. Native Port B clocks are supplied by PL RTL.
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] \
    [get_bd_pins ps7/M_AXI_GP0_ACLK] \
    [get_bd_pins axi_mem_interconnect/aclk] \
    [get_bd_pins meas_bram_ctrl/s_axi_aclk] \
    [get_bd_pins coeff_bram_ctrl/s_axi_aclk] \
    [get_bd_pins rst_ps7_fclk0/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] \
    [get_bd_pins rst_ps7_fclk0/ext_reset_in]
connect_bd_net [get_bd_pins rst_ps7_fclk0/peripheral_aresetn] \
    [get_bd_pins axi_mem_interconnect/aresetn] \
    [get_bd_pins meas_bram_ctrl/s_axi_aresetn] \
    [get_bd_pins coeff_bram_ctrl/s_axi_aresetn]

# Stable, explicit PS address map.
assign_bd_address \
    -offset 0x40000000 \
    -range 0x00008000 \
    -target_address_space [get_bd_addr_spaces ps7/Data] \
    [get_bd_addr_segs meas_bram_ctrl/S_AXI/Mem0] \
    -force
assign_bd_address \
    -offset 0x40010000 \
    -range 0x00001000 \
    -target_address_space [get_bd_addr_spaces ps7/Data] \
    [get_bd_addr_segs coeff_bram_ctrl/S_AXI/Mem0] \
    -force

validate_bd_design
save_bd_design

ps_pl_bram_tcl::require_single \
    "measurement AXI BRAM controller" \
    [get_bd_cells -quiet meas_bram_ctrl]
ps_pl_bram_tcl::require_single \
    "coefficient AXI BRAM controller" \
    [get_bd_cells -quiet coeff_bram_ctrl]
ps_pl_bram_tcl::require_single \
    "measurement native PL interface" \
    [get_bd_intf_ports -quiet MEAS_BRAM_PL]
ps_pl_bram_tcl::require_single \
    "coefficient native PL interface" \
    [get_bd_intf_ports -quiet COEFF_BRAM_PL]

puts "Created/updated $design_name successfully."
return 0

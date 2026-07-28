# ============================================================================
# top_ps_dds 板级管脚与时序约束
# 目标器件：Mizar Z7020，xc7z020clg400-2
# 依据：Mizar Z7用户手册、已验证top_adc_dac_loopback.xdc及用户确认的T10/T11接线。
# ============================================================================

# PL板载时钟和独立人工复位。
set_property PACKAGE_PIN H16      [get_ports clk_50m]
set_property IOSTANDARD LVCMOS33 [get_ports clk_50m]
set_property PACKAGE_PIN R19      [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]
create_clock -name clk_50m -period 20.000 -waveform {0.000 10.000} [get_ports clk_50m]
set_false_path -from [get_ports rst_n]

# PS UART1 EMIO：屏幕TX -> T10/RX，屏幕RX <- T11/TX；3.3 V TTL、115200 8N1。
set_property PACKAGE_PIN T10      [get_ports hmi_uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports hmi_uart_rx]
set_property PACKAGE_PIN T11      [get_ports hmi_uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports hmi_uart_tx]
set_property DRIVE 8             [get_ports hmi_uart_tx]
set_property SLEW SLOW           [get_ports hmi_uart_tx]
set_false_path -from [get_ports hmi_uart_rx]

# DA转接板位于JP1/GPIO1，Bank 34必须在上板前确认配置为3.3 V。
set_property PACKAGE_PIN N18 [get_ports dac_clk_a]
set_property PACKAGE_PIN P19 [get_ports {dac_data_a[9]}]
set_property PACKAGE_PIN N17 [get_ports {dac_data_a[8]}]
set_property PACKAGE_PIN P18 [get_ports {dac_data_a[7]}]
set_property PACKAGE_PIN N20 [get_ports {dac_data_a[6]}]
set_property PACKAGE_PIN P20 [get_ports {dac_data_a[5]}]
set_property PACKAGE_PIN T17 [get_ports {dac_data_a[4]}]
set_property PACKAGE_PIN R18 [get_ports {dac_data_a[3]}]
set_property PACKAGE_PIN T20 [get_ports {dac_data_a[2]}]
set_property PACKAGE_PIN U20 [get_ports {dac_data_a[1]}]
set_property PACKAGE_PIN V20 [get_ports {dac_data_a[0]}]
set_property PACKAGE_PIN W20 [get_ports dac_clk_b]
set_property PACKAGE_PIN Y18 [get_ports {dac_data_b[9]}]
set_property PACKAGE_PIN Y19 [get_ports {dac_data_b[8]}]
set_property PACKAGE_PIN Y16 [get_ports {dac_data_b[7]}]
set_property PACKAGE_PIN Y17 [get_ports {dac_data_b[6]}]
set_property PACKAGE_PIN W18 [get_ports {dac_data_b[5]}]
set_property PACKAGE_PIN W19 [get_ports {dac_data_b[4]}]
set_property PACKAGE_PIN U18 [get_ports {dac_data_b[3]}]
set_property PACKAGE_PIN U19 [get_ports {dac_data_b[2]}]
set_property PACKAGE_PIN V16 [get_ports {dac_data_b[1]}]
set_property PACKAGE_PIN W16 [get_ports {dac_data_b[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_data_a[*] dac_data_b[*] dac_clk_a dac_clk_b}]
set_property DRIVE 8 [get_ports {dac_data_a[*] dac_data_b[*] dac_clk_a dac_clk_b}]
set_property SLEW FAST [get_ports {dac_data_a[*] dac_data_b[*] dac_clk_a dac_clk_b}]

# 3PD5651E在转发时钟上升沿锁存；沿用已有2.0 ns建立、1.5 ns保持模型。
create_generated_clock -name dac_clk_a_ext \
    -source [get_pins u_dac_output/u_oddr_clk_a/C] \
    -divide_by 1 [get_ports dac_clk_a]
create_generated_clock -name dac_clk_b_ext \
    -source [get_pins u_dac_output/u_oddr_clk_b/C] \
    -divide_by 1 [get_ports dac_clk_b]
set_output_delay -clock dac_clk_a_ext -max 2.000  [get_ports {dac_data_a[*]}]
set_output_delay -clock dac_clk_a_ext -min -1.500 [get_ports {dac_data_a[*]}]
set_output_delay -clock dac_clk_b_ext -max 2.000  [get_ports {dac_data_b[*]}]
set_output_delay -clock dac_clk_b_ext -min -1.500 [get_ports {dac_data_b[*]}]

# ============================================================================
# top_adc_dac_loopback 管脚与时序约束
# 目标器件：Mizar Z7020，xc7z020clg400-2
#
# 映射依据：
#   1. 用户提供的 AD/DA 转接板照片丝印确定功能信号到 JP2/JP1 针位。
#   2. 《Mizar Z7 用户手册 V1.1》Table 3-2、3-18、3-19 确定针位到封装管脚。
#   3. 手册 3.7.8 说明 JP1/Bank 34 出厂默认由 R208 配置为 3.3 V。
#
# 上板前必须确认：R208 已贴装，R209/R210 未贴装；两块转换板数字接口为 3.3 V。
# ============================================================================

# 板载时钟与人工复位。选择独立 PL_KEY1/K4 作为低有效复位，避免占用 PS_POR_B。
set_property PACKAGE_PIN H16      [get_ports clk_50m]
set_property IOSTANDARD LVCMOS33 [get_ports clk_50m]
set_property PACKAGE_PIN R19      [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]
create_clock -name clk_50m -period 20.000 -waveform {0.000 10.000} [get_ports clk_50m]
set_false_path -from [get_ports rst_n]

# AD 转接板位于 JP2/GPIO2。JP2 的 GPIO2_[0..11] 全部属于固定 3.3 V 的 Bank 35。
# JP2 1~10：通道 1 D0_1~D9_1。
set_property PACKAGE_PIN J18 [get_ports {adc_data_a[0]}] ; # JP2-1  GPIO2_0P -> D0_1
set_property PACKAGE_PIN H18 [get_ports {adc_data_a[1]}] ; # JP2-2  GPIO2_0N -> D1_1
set_property PACKAGE_PIN G17 [get_ports {adc_data_a[2]}] ; # JP2-3  GPIO2_1P -> D2_1
set_property PACKAGE_PIN G18 [get_ports {adc_data_a[3]}] ; # JP2-4  GPIO2_1N -> D3_1
set_property PACKAGE_PIN K14 [get_ports {adc_data_a[4]}] ; # JP2-5  GPIO2_2P -> D4_1
set_property PACKAGE_PIN J14 [get_ports {adc_data_a[5]}] ; # JP2-6  GPIO2_2N -> D5_1
set_property PACKAGE_PIN H15 [get_ports {adc_data_a[6]}] ; # JP2-7  GPIO2_3P -> D6_1
set_property PACKAGE_PIN G15 [get_ports {adc_data_a[7]}] ; # JP2-8  GPIO2_3N -> D7_1
set_property PACKAGE_PIN J20 [get_ports {adc_data_a[8]}] ; # JP2-9  GPIO2_4P -> D8_1
set_property PACKAGE_PIN H20 [get_ports {adc_data_a[9]}] ; # JP2-10 GPIO2_4N -> D9_1

# JP2-11/12 为 5 V/GND，不是 FPGA I/O；JP2 13/14 为通道 1 CLK_1/OE_1。
set_property PACKAGE_PIN L14 [get_ports adc_clk_a] ; # JP2-13 GPIO2_5P -> CLK_1
set_property PACKAGE_PIN L15 [get_ports adc_oe_a]  ; # JP2-14 GPIO2_5N -> OE_1

# JP2 15~24：通道 2 D0_2~D9_2；JP2 25/26：通道 2 CLK_2/OE_2。
set_property PACKAGE_PIN K19 [get_ports {adc_data_b[0]}] ; # JP2-15 GPIO2_6P  -> D0_2
set_property PACKAGE_PIN J19 [get_ports {adc_data_b[1]}] ; # JP2-16 GPIO2_6N  -> D1_2
set_property PACKAGE_PIN K16 [get_ports {adc_data_b[2]}] ; # JP2-17 GPIO2_7P  -> D2_2
set_property PACKAGE_PIN J16 [get_ports {adc_data_b[3]}] ; # JP2-18 GPIO2_7N  -> D3_2
set_property PACKAGE_PIN L19 [get_ports {adc_data_b[4]}] ; # JP2-19 GPIO2_8P  -> D4_2
set_property PACKAGE_PIN L20 [get_ports {adc_data_b[5]}] ; # JP2-20 GPIO2_8N  -> D5_2
set_property PACKAGE_PIN L16 [get_ports {adc_data_b[6]}] ; # JP2-21 GPIO2_9P  -> D6_2
set_property PACKAGE_PIN L17 [get_ports {adc_data_b[7]}] ; # JP2-22 GPIO2_9N  -> D7_2
set_property PACKAGE_PIN M14 [get_ports {adc_data_b[8]}] ; # JP2-23 GPIO2_10P -> D8_2
set_property PACKAGE_PIN M15 [get_ports {adc_data_b[9]}] ; # JP2-24 GPIO2_10N -> D9_2
set_property PACKAGE_PIN N15 [get_ports adc_clk_b]        ; # JP2-25 GPIO2_11P -> CLK_2
set_property PACKAGE_PIN N16 [get_ports adc_oe_b]         ; # JP2-26 GPIO2_11N -> OE_2

set_property IOSTANDARD LVCMOS33 [get_ports {adc_data_a[*] adc_data_b[*] adc_clk_a adc_clk_b adc_oe_a adc_oe_b}]
set_property DRIVE 8 [get_ports {adc_clk_a adc_clk_b adc_oe_a adc_oe_b}]
set_property SLEW FAST [get_ports {adc_clk_a adc_clk_b}]
set_property SLEW SLOW [get_ports {adc_oe_a adc_oe_b}]

# DA 转接板位于 JP1/GPIO1。JP1 全部属于可调 Bank 34，本约束要求实板为 3.3 V。
# JP1 1：CLK1；JP1 2~10：通道 1 D9_1~D1_1；JP1 13：D0_1；JP1 14：CLK2。
set_property PACKAGE_PIN N18 [get_ports dac_clk_a]        ; # JP1-1  GPIO1_0P -> CLK1
set_property PACKAGE_PIN P19 [get_ports {dac_data_a[9]}] ; # JP1-2  GPIO1_0N -> D9_1
set_property PACKAGE_PIN N17 [get_ports {dac_data_a[8]}] ; # JP1-3  GPIO1_1P -> D8_1
set_property PACKAGE_PIN P18 [get_ports {dac_data_a[7]}] ; # JP1-4  GPIO1_1N -> D7_1
set_property PACKAGE_PIN N20 [get_ports {dac_data_a[6]}] ; # JP1-5  GPIO1_2P -> D6_1
set_property PACKAGE_PIN P20 [get_ports {dac_data_a[5]}] ; # JP1-6  GPIO1_2N -> D5_1
set_property PACKAGE_PIN T17 [get_ports {dac_data_a[4]}] ; # JP1-7  GPIO1_3P -> D4_1
set_property PACKAGE_PIN R18 [get_ports {dac_data_a[3]}] ; # JP1-8  GPIO1_3N -> D3_1
set_property PACKAGE_PIN T20 [get_ports {dac_data_a[2]}] ; # JP1-9  GPIO1_4P -> D2_1
set_property PACKAGE_PIN U20 [get_ports {dac_data_a[1]}] ; # JP1-10 GPIO1_4N -> D1_1
set_property PACKAGE_PIN V20 [get_ports {dac_data_a[0]}] ; # JP1-13 GPIO1_5P -> D0_1
set_property PACKAGE_PIN W20 [get_ports dac_clk_b]        ; # JP1-14 GPIO1_5N -> CLK2

# JP1 15~24：通道 2 D9_2~D0_2。JP1-11/12 为 5 V/GND，不是 FPGA I/O。
set_property PACKAGE_PIN Y18 [get_ports {dac_data_b[9]}] ; # JP1-15 GPIO1_6P  -> D9_2
set_property PACKAGE_PIN Y19 [get_ports {dac_data_b[8]}] ; # JP1-16 GPIO1_6N  -> D8_2
set_property PACKAGE_PIN Y16 [get_ports {dac_data_b[7]}] ; # JP1-17 GPIO1_7P  -> D7_2
set_property PACKAGE_PIN Y17 [get_ports {dac_data_b[6]}] ; # JP1-18 GPIO1_7N  -> D6_2
set_property PACKAGE_PIN W18 [get_ports {dac_data_b[5]}] ; # JP1-19 GPIO1_8P  -> D5_2
set_property PACKAGE_PIN W19 [get_ports {dac_data_b[4]}] ; # JP1-20 GPIO1_8N  -> D4_2
set_property PACKAGE_PIN U18 [get_ports {dac_data_b[3]}] ; # JP1-21 GPIO1_9P  -> D3_2
set_property PACKAGE_PIN U19 [get_ports {dac_data_b[2]}] ; # JP1-22 GPIO1_9N  -> D2_2
set_property PACKAGE_PIN V16 [get_ports {dac_data_b[1]}] ; # JP1-23 GPIO1_10P -> D1_2
set_property PACKAGE_PIN W16 [get_ports {dac_data_b[0]}] ; # JP1-24 GPIO1_10N -> D0_2

set_property IOSTANDARD LVCMOS33 [get_ports {dac_data_a[*] dac_data_b[*] dac_clk_a dac_clk_b}]
set_property DRIVE 8 [get_ports {dac_data_a[*] dac_data_b[*] dac_clk_a dac_clk_b}]
set_property SLEW FAST [get_ports {dac_data_a[*] dac_data_b[*] dac_clk_a dac_clk_b}]

# ADC 在转发时钟上升沿启动转换，现有模块资料给出的最大时钟到输出延迟为 25 ns。
create_generated_clock -name adc_clk_a_ext \
    -source [get_pins u_adc_capture/u_oddr_clk_a/C] \
    -divide_by 1 [get_ports adc_clk_a]
create_generated_clock -name adc_clk_b_ext \
    -source [get_pins u_adc_capture/u_oddr_clk_b/C] \
    -divide_by 1 [get_ports adc_clk_b]
set_input_delay -clock adc_clk_a_ext -min 0.000  [get_ports {adc_data_a[*]}]
set_input_delay -clock adc_clk_a_ext -max 25.000 [get_ports {adc_data_a[*]}]
set_input_delay -clock adc_clk_b_ext -min 0.000  [get_ports {adc_data_b[*]}]
set_input_delay -clock adc_clk_b_ext -max 25.000 [get_ports {adc_data_b[*]}]

# 3PD5651E 在转发时钟上升沿锁存；按现有模块资料约束 2.0 ns 建立、1.5 ns 保持。
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

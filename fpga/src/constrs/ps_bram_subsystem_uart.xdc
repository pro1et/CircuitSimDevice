# ============================================================================
# PS UART1 EMIO到串口屏的固定管脚约束
#
# 串口屏：5 V供电，UART电平为3.3 V TTL，115200 bit/s，8N1。
# 接线方向：串口屏TX -> FPGA T10；串口屏RX <- FPGA T11；双方必须共地。
# UART是异步串行接口，不在RX端创建虚假的同步输入时钟。
# ============================================================================

set_property PACKAGE_PIN T10 [get_ports hmi_uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports hmi_uart_rx]

set_property PACKAGE_PIN T11 [get_ports hmi_uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports hmi_uart_tx]
set_property DRIVE 8 [get_ports hmi_uart_tx]
set_property SLEW SLOW [get_ports hmi_uart_tx]

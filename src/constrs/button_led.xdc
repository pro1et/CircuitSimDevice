# Mizar Z7 PL user button K4 (PL_KEY1).
# The board provides an external pull-up; pressing the button drives this input low.
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33} [get_ports button]

# Mizar Z7 PL user LED D6 (PL_LED1).
# The LED is active-low: driving this output low turns the LED on.
set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS33} [get_ports led]

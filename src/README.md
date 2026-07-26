# PL source interface

`hdl/LED.v` and `hdl/button_debounce.v` form the physical PL-button front end. Add `LED` to the Vivado Block Design with **Add Module** / **Add Module Reference**; do not set it as the standalone project top.

| `LED` port | Block Design connection |
| --- | --- |
| `clk` | `processing_system7_0/FCLK_CLK0` (100 MHz) |
| `resetn` | `rst_ps7_0_100M/peripheral_aresetn` |
| `button` | Make External; constrained to Mizar Z7 `PL_KEY1` by `constrs/button_led.xdc` |
| `led` | Make External; constrained to `PL_LED1` |
| `button_pressed` | `axi_gpio_0/gpio_io_i`; use for PS polling or interrupt |
| `button_event` | Optional debug signal; one 100 MHz cycle per confirmed press |

The initialized `blk_mem_gen_0` is added separately as a Block Design IP. Its 32-bit byte-addressed `BRAM_PORTA` connects to `axi_bram_ctrl_0/BRAM_PORTA`, letting PS software read 8192 words without a GP0 width conversion. The AXI BRAM controller read latency is 1 and the Block Memory primitive output registers are disabled, so an AXI response contains the word selected by the current request rather than the preceding request. Two adjacent words form one 64-bit IQ point. `BRAM_PORTB` is reserved for future PL data-producer logic.

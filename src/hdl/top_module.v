`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/07/25 10:20:08
// Design Name: 
// Module Name: top_module
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// Add this module to the Vivado Block Design as a Module Reference:
//   clk            <- processing_system7_0/FCLK_CLK0 (100 MHz)
//   resetn         <- proc_sys_reset/peripheral_aresetn
//   button         <- Mizar Z7 PL_KEY1 (active low)
//   button_pressed -> AXI GPIO input, for PS polling or GPIO interrupt
//
// The BRAM is deliberately not instantiated here. Its Port A is owned by
// axi_bram_ctrl_0 inside the Block Design; add the BMG to that same design.
module top_module #(
    parameter integer CLOCK_HZ    = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
) (
    input  wire clk,
    input  wire resetn,
    input  wire button,
    output wire led,
    output wire button_pressed,
    output wire button_event
);

    button_debounce #(
        .CLOCK_HZ(CLOCK_HZ),
        .DEBOUNCE_MS(DEBOUNCE_MS)
    ) u_button_debounce (
        .clk            (clk),
        .resetn         (resetn),
        .button_n_async (button),
        .pressed        (button_pressed),
        .press_event    (button_event)
    );

    // Mizar Z7's PL LED is active low: illuminate after a confirmed press.
    assign led = ~button_pressed;

endmodule

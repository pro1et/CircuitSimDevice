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


module top_module (
    input  wire button,
    output wire led
);

    // Both the Mizar Z7 PL button and PL LED are active-low.
    // Released button: button = 1 -> led = 1 -> LED off.
    // Pressed button:  button = 0 -> led = 0 -> LED on.
    assign led = button;

endmodule

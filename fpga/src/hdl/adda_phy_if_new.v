`timescale 1ns / 1ps

`include "params.vh"

module adda_phy_if_new #(
    parameter integer DATA_W            = `BOARD_DATA_W,
    parameter         ADC_OFFSET_BINARY = 1'b1,
    parameter         DAC_OFFSET_BINARY = 1'b1
) (
    input  wire      sample_clk,
    input  wire      sample_rst_n,

    // Board-level ADC parallel inputs and control pins.
    input  wire [DATA_W-1:0] ad_data_1,
    input  wire      ad_otr_1,
    output wire      ad_clk_1,
    output wire      ad_oe_1,
    input  wire [DATA_W-1:0] ad_data_2,
    input  wire      ad_otr_2,
    output wire      ad_clk_2,
    output wire      ad_oe_2,

    // Board-level DAC parallel outputs.
    output wire      da_clk_1,
    output reg [DATA_W-1:0] da_data_1,
    output wire      da_clk_2,
    output reg [DATA_W-1:0] da_data_2,

    // Internal signed sample stream used by PL processing modules.
    output reg signed [DATA_W-1:0] adc0_data,
    output reg signed [DATA_W-1:0] adc1_data,
    output reg       adc_valid,
    input  wire signed [DATA_W-1:0] dac0_data,
    input  wire signed [DATA_W-1:0] dac1_data,
    input  wire      dac_valid,
    output wire [1:0] adc_otr_status
);

    localparam [DATA_W-1:0] MID_SCALE = {1'b1, {(DATA_W-1){1'b0}}};

    // Convert ADC offset-binary samples into internal two's-complement samples.
    function [DATA_W-1:0] offset_to_twos;
        input [DATA_W-1:0] value;
        begin
            if (ADC_OFFSET_BINARY)
                offset_to_twos = value ^ MID_SCALE;
            else
                offset_to_twos = value;
        end
    endfunction

    // Convert internal two's-complement samples back to the DAC coding format.
    function [DATA_W-1:0] twos_to_offset;
        input [DATA_W-1:0] value;
        begin
            if (DAC_OFFSET_BINARY)
                twos_to_offset = value ^ MID_SCALE;
            else
                twos_to_offset = value;
        end
    endfunction

    // ADCs are driven continuously by the shared sample clock.
    assign ad_clk_1 = sample_clk;
    assign ad_clk_2 = sample_clk;
    assign ad_oe_1  = 1'b0;
    assign ad_oe_2  = 1'b0;

    // DAC uses the inverted edge to relax board-level timing.
    assign da_clk_1 = ~sample_clk;
    assign da_clk_2 = ~sample_clk;

    assign adc_otr_status = {ad_otr_2, ad_otr_1};

    // Register external ADC data every sample and expose it as signed PL data.
    always @(posedge sample_clk or negedge sample_rst_n) begin
        if (!sample_rst_n) begin
            adc0_data <= {DATA_W{1'b0}};
            adc1_data <= {DATA_W{1'b0}};
            adc_valid <= 1'b0;
        end else begin
            adc0_data <= $signed(offset_to_twos(ad_data_1));
            adc1_data <= $signed(offset_to_twos(ad_data_2));
            adc_valid <= 1'b1;
        end
    end

    // Only drive DAC with valid PL data; otherwise park both channels at mid-scale.
    always @(posedge sample_clk or negedge sample_rst_n) begin
        if (!sample_rst_n) begin
            da_data_1 <= MID_SCALE;
            da_data_2 <= MID_SCALE;
        end else if (dac_valid) begin
            da_data_1 <= twos_to_offset(dac0_data);
            da_data_2 <= twos_to_offset(dac1_data);
        end else begin
            da_data_1 <= MID_SCALE;
            da_data_2 <= MID_SCALE;
        end
    end

endmodule

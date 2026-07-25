`timescale 1ns / 1ps
// Synchronizes and debounces the active-low Mizar Z7 PL_KEY1 input.
module button_debounce #(
    parameter integer CLOCK_HZ    = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
) (
    input  wire clk,
    input  wire resetn,
    input  wire button_n_async,
    output reg  pressed,
    output reg  press_event
);

    localparam integer DEBOUNCE_COUNT = (CLOCK_HZ / 1000) * DEBOUNCE_MS;
    localparam integer COUNTER_WIDTH = $clog2(DEBOUNCE_COUNT + 1);

    reg button_sync_1;
    reg button_sync_2;
    reg [COUNTER_WIDTH-1:0] debounce_counter;

    always @(posedge clk) begin
        if (!resetn) begin
            button_sync_1    <= 1'b0;
            button_sync_2    <= 1'b0;
            debounce_counter <= {COUNTER_WIDTH{1'b0}};
            pressed          <= 1'b0;
            press_event      <= 1'b0;
        end else begin
            // Convert the physical active-low button to active-high and pass
            // it through a two-flop synchronizer before debouncing.
            button_sync_1 <= ~button_n_async;
            button_sync_2 <= button_sync_1;
            press_event   <= 1'b0;

            if (button_sync_2 == pressed) begin
                debounce_counter <= {COUNTER_WIDTH{1'b0}};
            end else if (debounce_counter == DEBOUNCE_COUNT - 1) begin
                debounce_counter <= {COUNTER_WIDTH{1'b0}};
                pressed <= button_sync_2;
                // One FCLK cycle, emitted only on the debounced press.
                if (button_sync_2) begin
                    press_event <= 1'b1;
                end
            end else begin
                debounce_counter <= debounce_counter + 1'b1;
            end
        end
    end

endmodule

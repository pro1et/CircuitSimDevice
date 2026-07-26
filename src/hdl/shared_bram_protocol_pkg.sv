`timescale 1ns/1ps

package shared_bram_protocol_pkg;

    localparam logic [31:0] MEAS_MAGIC       = 32'h4D45_4153; // "MEAS"
    localparam logic [31:0] COEFF_MAGIC      = 32'h434F_4546; // "COEF"
    localparam logic [31:0] PROTOCOL_VERSION = 32'h0001_0000;

    // Native BRAM Port B addresses are 32-bit word addresses.
    localparam int unsigned HDR_MAGIC_WORD      = 0;
    localparam int unsigned HDR_VERSION_WORD    = 1;
    localparam int unsigned HDR_GENERATION_WORD = 2;
    localparam int unsigned HDR_STATUS_WORD     = 3;
    localparam int unsigned HDR_ARG0_WORD       = 4;
    localparam int unsigned HDR_FORMAT_WORD     = 5;
    localparam int unsigned HDR_ARG1_WORD       = 6;
    localparam int unsigned HEADER_WORDS         = 16;
    localparam int unsigned PAYLOAD_BASE_WORD    = HEADER_WORDS;

    // Zero is deliberately BUSY so a cleared BRAM can never look valid.
    localparam logic [31:0] STATUS_STATE_MASK = 32'h0000_0003;
    localparam logic [31:0] STATUS_BUSY       = 32'h0000_0000;
    localparam logic [31:0] MEAS_STATUS_DONE  = 32'h0000_0001;
    localparam logic [31:0] COEFF_STATUS_VALID = 32'h0000_0001;
    localparam logic [31:0] STATUS_ERROR      = 32'h0000_0002;

    localparam logic [31:0] MEAS_STATUS_OVERFLOW  = 32'h0000_0100;
    localparam logic [31:0] MEAS_STATUS_TRUNCATED = 32'h0000_0200;

    // Each sweep point occupies two words: direct {I,Q}, then filtered {I,Q}.
    localparam logic [31:0] MEAS_FORMAT_IQ_INT16_X4 = 32'd1;
    localparam logic [31:0] COEFF_FORMAT_Q1_31      = 32'd1;

    localparam logic [31:0] MEAS_ERROR_NONE           = 32'd0;
    localparam logic [31:0] MEAS_ERROR_INVALID_LENGTH = 32'd1;
    localparam logic [31:0] MEAS_ERROR_ABORTED        = 32'd2;

    localparam logic [31:0] COEFF_ERROR_FIR_INITIALIZE = 32'h0000_0101;
    localparam logic [31:0] COEFF_ERROR_IQ_READ        = 32'h0000_0102;
    localparam logic [31:0] COEFF_ERROR_TOO_FEW_POINTS = 32'h0000_0103;
    localparam logic [31:0] COEFF_ERROR_FIR_SOLVE      = 32'h0000_0104;
    localparam logic [31:0] COEFF_ERROR_QUANTIZE       = 32'h0000_0105;

endpackage

//=============================================================================
// Module: wptr_full
// Description: Write pointer, Gray code generation, write-domain CDC status,
//              and full / almost-full condition logic.
//=============================================================================

`timescale 1ns / 1ps

module wptr_full #(
    parameter int ADDR_WIDTH         = 4,
    parameter int ALMOST_FULL_THRESH = 1
) (
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  winc,
    input  logic [ADDR_WIDTH:0]   rptr_gray_sync,
    output logic                  wfull,
    output logic                  walmost_full,
    output logic [ADDR_WIDTH-1:0] waddr,
    output logic [ADDR_WIDTH:0]   wptr_gray,
    output logic [ADDR_WIDTH:0]   wlevel
);

    localparam int PTR_WIDTH = ADDR_WIDTH + 1;
    localparam int DEPTH     = 1 << ADDR_WIDTH;

    logic [PTR_WIDTH-1:0] wptr_bin;
    logic [PTR_WIDTH-1:0] wptr_bin_next;
    logic [PTR_WIDTH-1:0] wptr_gray_next;
    logic                 wfull_val;
    logic [PTR_WIDTH-1:0] rptr_bin_sync;

    // Increment binary pointer when write is enabled and FIFO is not full
    assign wptr_bin_next = wptr_bin + (winc & ~wfull);

    // Binary to Gray conversion
    assign wptr_gray_next = (wptr_bin_next >> 1) ^ wptr_bin_next;

    // Memory write address is lower ADDR_WIDTH bits of binary pointer
    assign waddr = wptr_bin[ADDR_WIDTH-1:0];

    // Standard Cummings Full Condition:
    // MSB and 2nd MSB inverted, remaining bits identical
    assign wfull_val = (wptr_gray_next == {~rptr_gray_sync[PTR_WIDTH-1:PTR_WIDTH-2], 
                                           rptr_gray_sync[PTR_WIDTH-3:0]});

    // Gray-to-Binary conversion function for occupancy level computation
    function automatic [PTR_WIDTH-1:0] gray2bin(input [PTR_WIDTH-1:0] gray);
        logic [PTR_WIDTH-1:0] bin;
        bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
        for (int i = PTR_WIDTH-2; i >= 0; i--) begin
            bin[i] = bin[i+1] ^ gray[i];
        end
        return bin;
    endfunction

    assign rptr_bin_sync = gray2bin(rptr_gray_sync);
    assign wlevel        = wptr_bin - rptr_bin_sync;

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wptr_bin     <= '0;
            wptr_gray    <= '0;
            wfull        <= 1'b0;
            walmost_full <= 1'b0;
        end else begin
            wptr_bin     <= wptr_bin_next;
            wptr_gray    <= wptr_gray_next;
            wfull        <= wfull_val;
            walmost_full <= (wlevel >= (DEPTH - ALMOST_FULL_THRESH));
        end
    end

endmodule

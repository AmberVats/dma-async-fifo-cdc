//=============================================================================
// Module: rptr_empty
// Description: Read pointer, Gray code generation, read-domain CDC status,
//              and empty / almost-empty condition logic.
//=============================================================================

`timescale 1ns / 1ps

module rptr_empty #(
    parameter int ADDR_WIDTH          = 4,
    parameter int ALMOST_EMPTY_THRESH = 1
) (
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  rinc,
    input  logic [ADDR_WIDTH:0]   wptr_gray_sync,
    output logic                  rempty,
    output logic                  ralmost_empty,
    output logic [ADDR_WIDTH-1:0] raddr,
    output logic [ADDR_WIDTH:0]   rptr_gray,
    output logic [ADDR_WIDTH:0]   rlevel
);

    localparam int PTR_WIDTH = ADDR_WIDTH + 1;

    logic [PTR_WIDTH-1:0] rptr_bin;
    logic [PTR_WIDTH-1:0] rptr_bin_next;
    logic [PTR_WIDTH-1:0] rptr_gray_next;
    logic                 rempty_val;
    logic [PTR_WIDTH-1:0] wptr_bin_sync;

    // Increment binary pointer when read is enabled and FIFO is not empty
    assign rptr_bin_next = rptr_bin + (rinc & ~rempty);

    // Binary to Gray conversion
    assign rptr_gray_next = (rptr_bin_next >> 1) ^ rptr_bin_next;

    // Memory read address is lower ADDR_WIDTH bits of binary pointer
    assign raddr = rptr_bin[ADDR_WIDTH-1:0];

    // Standard Cummings Empty Condition:
    // Read pointer and synchronized write pointer are completely identical
    assign rempty_val = (rptr_gray_next == wptr_gray_sync);

    // Gray-to-Binary conversion function for occupancy level computation
    function automatic [PTR_WIDTH-1:0] gray2bin(input [PTR_WIDTH-1:0] gray);
        logic [PTR_WIDTH-1:0] bin;
        bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
        for (int i = PTR_WIDTH-2; i >= 0; i--) begin
            bin[i] = bin[i+1] ^ gray[i];
        end
        return bin;
    endfunction

    assign wptr_bin_sync = gray2bin(wptr_gray_sync);
    assign rlevel        = wptr_bin_sync - rptr_bin;

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rptr_bin      <= '0;
            rptr_gray     <= '0;
            rempty        <= 1'b1; // FIFO starts empty upon reset
            ralmost_empty <= 1'b1;
        end else begin
            rptr_bin      <= rptr_bin_next;
            rptr_gray     <= rptr_gray_next;
            rempty        <= rempty_val;
            ralmost_empty <= (rlevel <= ALMOST_EMPTY_THRESH);
        end
    end

endmodule

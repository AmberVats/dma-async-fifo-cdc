//=============================================================================
// Module: fifo_mem
// Description: Dual-port FIFO memory storage array.
//              Write port synchronous to write clock (wclk).
//              Read port accessed via read pointer in read clock domain (rclk).
//=============================================================================

`timescale 1ns / 1ps

module fifo_mem #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 4
) (
    input  logic                  wclk,
    input  logic                  wclken,
    input  logic [ADDR_WIDTH-1:0] waddr,
    input  logic [DATA_WIDTH-1:0] wdata,
    input  logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] rdata
);

    localparam int DEPTH = 1 << ADDR_WIDTH;

    // Memory array
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Synchronous write
    always_ff @(posedge wclk) begin
        if (wclken) begin
            mem[waddr] <= wdata;
        end
    end

    // Combinational read out based on current read pointer
    assign rdata = mem[raddr];

endmodule

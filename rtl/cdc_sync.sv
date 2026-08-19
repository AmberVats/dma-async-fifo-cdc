//=============================================================================
// Module: cdc_sync
// Description: Multi-stage Clock Domain Crossing (CDC) synchronizer for bus 
//              signals (e.g. Gray-coded pointers).
//              Includes ASYNC_REG synthesis attributes to instruct EDA tools
//              to place flip-flops in close proximity to maximize MTBF.
//=============================================================================

`timescale 1ns / 1ps

module cdc_sync #(
    parameter int WIDTH  = 4,
    parameter int STAGES = 2
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] din,
    output logic [WIDTH-1:0] dout
);

    // Ensure at least 2 stages for metastability protection
    initial begin
        if (STAGES < 2) begin
            $error("cdc_sync: STAGES must be at least 2 for safe CDC!");
        end
    end

    // Synthesis attributes to prevent optimization and enforce co-location
    (* ASYNC_REG = "TRUE", DONT_TOUCH = "TRUE" *)
    logic [WIDTH-1:0] sync_regs [STAGES-1:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < STAGES; i++) begin
                sync_regs[i] <= '0;
            end
        end else begin
            sync_regs[0] <= din;
            for (int i = 1; i < STAGES; i++) begin
                sync_regs[i] <= sync_regs[i-1];
            end
        end
    end

    assign dout = sync_regs[STAGES-1];

endmodule

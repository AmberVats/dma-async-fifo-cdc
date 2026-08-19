//=============================================================================
// Module: dma_arbiter
// Description: Multi-Channel DMA Arbiter supporting Fixed Priority and 
//              Round-Robin scheduling schemes across 4 channels.
//=============================================================================

`timescale 1ns / 1ps

module dma_arbiter #(
    parameter int NUM_CHANNELS = 4
) (
    input  logic                                  clk,
    input  logic                                  rst_n,

    // Channel Requests and Priorities
    input  logic [NUM_CHANNELS-1:0]               req,
    input  logic [NUM_CHANNELS-1:0][1:0]          ch_priority,
    input  logic [NUM_CHANNELS-1:0]               ch_busy,

    // Channel Grants
    output logic [NUM_CHANNELS-1:0]               grant,
    output logic [$clog2(NUM_CHANNELS)-1:0]       grant_id,
    output logic                                  grant_valid
);

    localparam int ID_WIDTH = $clog2(NUM_CHANNELS);

    logic [NUM_CHANNELS-1:0] active_grant;
    logic [ID_WIDTH-1:0]     active_id;
    logic                    active_valid;
    logic [ID_WIDTH-1:0]     last_rr_grant;

    // Find highest priority request
    logic [NUM_CHANNELS-1:0] highest_pri_req;
    logic [1:0]              max_pri;

    always_comb begin
        max_pri = 2'b00;
        for (int i = 0; i < NUM_CHANNELS; i++) begin
            if (req[i] && (ch_priority[i] > max_pri)) begin
                max_pri = ch_priority[i];
            end
        end

        for (int i = 0; i < NUM_CHANNELS; i++) begin
            highest_pri_req[i] = req[i] && (ch_priority[i] == max_pri);
        end
    end

    // Round-robin selection among candidates of highest priority
    logic [NUM_CHANNELS-1:0] rr_grant_comb;
    logic [ID_WIDTH-1:0]     rr_id_comb;
    logic                    rr_valid_comb;

    always_comb begin
        rr_grant_comb = '0;
        rr_id_comb    = '0;
        rr_valid_comb = 1'b0;

        // Check channels starting from (last_rr_grant + 1)
        for (int i = 1; i <= NUM_CHANNELS; i++) begin
            int idx;
            idx = (last_rr_grant + i) % NUM_CHANNELS;
            if (highest_pri_req[idx] && !rr_valid_comb) begin
                rr_grant_comb[idx] = 1'b1;
                rr_id_comb         = idx[ID_WIDTH-1:0];
                rr_valid_comb      = 1'b1;
            end
        end
    end

    // Grant latching: Maintain grant if current active channel is busy
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_grant  <= '0;
            active_id     <= '0;
            active_valid  <= 1'b0;
            last_rr_grant <= '0;
        end else begin
            if (active_valid && ch_busy[active_id]) begin
                // Channel is still actively executing; retain grant
                active_grant <= active_grant;
            end else begin
                // Arbitrate new channel
                active_grant  <= rr_grant_comb;
                active_id     <= rr_id_comb;
                active_valid  <= rr_valid_comb;
                if (rr_valid_comb) begin
                    last_rr_grant <= rr_id_comb;
                end
            end
        end
    end

    assign grant       = active_grant;
    assign grant_id    = active_id;
    assign grant_valid = active_valid;

endmodule

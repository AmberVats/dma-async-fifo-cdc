//=============================================================================
// Module: dma_channel
// Description: Individual DMA Channel Execution Controller.
//              Manages address calculation, burst sizing, read/write triggering,
//              and progress reporting.
//=============================================================================

`timescale 1ns / 1ps

module dma_channel #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Channel Configuration from CSR
    input  logic                  ch_enable,
    input  logic                  ch_abort,
    input  logic [7:0]            ch_burst_len, // Beats per burst (e.g. 16)
    input  logic [ADDR_WIDTH-1:0] ch_src_addr,
    input  logic [ADDR_WIDTH-1:0] ch_dst_addr,
    input  logic [31:0]           ch_xfer_len,

    // Channel Status to CSR
    output logic                  ch_busy,
    output logic                  ch_done,
    output logic                  ch_error,
    output logic [31:0]           ch_transferred_bytes,

    // Arbiter Interface
    output logic                  arb_req,
    input  logic                  arb_grant,

    // AXI Read Master Command Interface
    output logic                  rd_cmd_valid,
    input  logic                  rd_cmd_ready,
    output logic [ADDR_WIDTH-1:0] rd_cmd_addr,
    output logic [7:0]            rd_cmd_len,
    input  logic                  rd_cmd_done,
    input  logic                  rd_cmd_err,

    // AXI Write Master Command Interface
    output logic                  wr_cmd_valid,
    input  logic                  wr_cmd_ready,
    output logic [ADDR_WIDTH-1:0] wr_cmd_addr,
    output logic [7:0]            wr_cmd_len,
    input  logic                  wr_cmd_done,
    input  logic                  wr_cmd_err
);

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;

    typedef enum logic [2:0] {
        ST_IDLE       = 3'b000,
        ST_WAIT_GRANT = 3'b001,
        ST_READ_BURST = 3'b010,
        ST_WRITE_BURST= 3'b011,
        ST_UPDATE_XFER= 3'b100,
        ST_DONE       = 3'b101,
        ST_ERROR      = 3'b110
    } state_t;

    state_t state, next_state;

    logic [ADDR_WIDTH-1:0] curr_src_addr;
    logic [ADDR_WIDTH-1:0] curr_dst_addr;
    logic [31:0]           bytes_remaining;
    logic [31:0]           transferred_count;
    logic [7:0]            current_burst_beats;

    // Calculate maximum burst beats possible for remaining bytes
    always_comb begin
        if (bytes_remaining >= (ch_burst_len * BYTES_PER_BEAT)) begin
            current_burst_beats = ch_burst_len;
        end else begin
            current_burst_beats = (bytes_remaining + BYTES_PER_BEAT - 1) / BYTES_PER_BEAT;
        end
    end

    // FSM State Transition
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else if (ch_abort) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Next State Logic
    always_comb begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                if (ch_enable && (ch_xfer_len > 0)) begin
                    next_state = ST_WAIT_GRANT;
                end
            end

            ST_WAIT_GRANT: begin
                if (arb_grant) begin
                    next_state = ST_READ_BURST;
                end
            end

            ST_READ_BURST: begin
                if (rd_cmd_err) begin
                    next_state = ST_ERROR;
                end else if (rd_cmd_done) begin
                    next_state = ST_WRITE_BURST;
                end
            end

            ST_WRITE_BURST: begin
                if (wr_cmd_err) begin
                    next_state = ST_ERROR;
                end else if (wr_cmd_done) begin
                    next_state = ST_UPDATE_XFER;
                end
            end

            ST_UPDATE_XFER: begin
                if (bytes_remaining == 0) begin
                    next_state = ST_DONE;
                end else begin
                    next_state = ST_WAIT_GRANT; // Re-arbitrate for next burst
                end
            end

            ST_DONE: begin
                if (!ch_enable) begin
                    next_state = ST_IDLE;
                end
            end

            ST_ERROR: begin
                if (!ch_enable) begin
                    next_state = ST_IDLE;
                end
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // Datapath Registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_src_addr     <= '0;
            curr_dst_addr     <= '0;
            bytes_remaining   <= '0;
            transferred_count <= '0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (ch_enable) begin
                        curr_src_addr     <= ch_src_addr;
                        curr_dst_addr     <= ch_dst_addr;
                        bytes_remaining   <= ch_xfer_len;
                        transferred_count <= '0;
                    end
                end

                ST_UPDATE_XFER: begin
                    logic [31:0] burst_bytes;
                    burst_bytes = current_burst_beats * BYTES_PER_BEAT;
                    if (bytes_remaining > burst_bytes) begin
                        bytes_remaining   <= bytes_remaining - burst_bytes;
                        transferred_count <= transferred_count + burst_bytes;
                    end else begin
                        transferred_count <= transferred_count + bytes_remaining;
                        bytes_remaining   <= 0;
                    end
                    curr_src_addr <= curr_src_addr + burst_bytes;
                    curr_dst_addr <= curr_dst_addr + burst_bytes;
                end

                default: ;
            endcase
        end
    end

    // Outputs
    assign arb_req              = (state == ST_WAIT_GRANT);
    assign ch_busy              = (state != ST_IDLE) && (state != ST_DONE) && (state != ST_ERROR);
    assign ch_done              = (state == ST_DONE);
    assign ch_error             = (state == ST_ERROR);
    assign ch_transferred_bytes = transferred_count;

    // Read Master Commands
    assign rd_cmd_valid = (state == ST_READ_BURST);
    assign rd_cmd_addr  = curr_src_addr;
    assign rd_cmd_len   = current_burst_beats - 1; // AXI4 len = beats - 1

    // Write Master Commands
    assign wr_cmd_valid = (state == ST_WRITE_BURST);
    assign wr_cmd_addr  = curr_dst_addr;
    assign wr_cmd_len   = current_burst_beats - 1;

endmodule

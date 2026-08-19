//=============================================================================
// Module: axi_master_rd
// Description: AXI4 Master Read Engine.
//              Generates AXI4 AR read address requests and streams read data beats
//              directly into the CDC FIFO write port.
//=============================================================================

`timescale 1ns / 1ps

module axi_master_rd #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int AXI_ID_WIDTH   = 4
) (
    input  logic                      aclk,
    input  logic                      aresetn,

    // Command Interface from Channel Controller
    input  logic                      cmd_valid,
    output logic                      cmd_ready,
    input  logic [AXI_ADDR_WIDTH-1:0] cmd_addr,
    input  logic [7:0]                cmd_len, // Burst length (0 = 1 beat, 15 = 16 beats)
    output logic                      cmd_done,
    output logic                      cmd_err,

    // AXI4 Read Address Channel (AR)
    output logic [AXI_ID_WIDTH-1:0]   m_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,

    // AXI4 Read Data Channel (R)
    input  logic [AXI_ID_WIDTH-1:0]   m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  logic [1:0]                m_axi_rresp,
    input  logic                      m_axi_rlast,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready,

    // FIFO Write Interface (Data ingested from AXI)
    output logic                      fifo_winc,
    output logic [AXI_DATA_WIDTH-1:0] fifo_wdata,
    input  logic                      fifo_wfull
);

    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        SEND_AR = 2'b01,
        RECV_R  = 2'b10,
        DONE    = 2'b11
    } state_t;

    state_t state;

    logic [7:0] beats_remaining;
    logic       error_detected;

    // AXI Constant Configurations (INCR burst, 4-byte size for 32-bit bus)
    assign m_axi_arid    = '0;
    assign m_axi_arsize  = 3'b010; // 4 bytes (32-bit)
    assign m_axi_arburst = 2'b01;  // INCR burst

    // AR Channel
    assign m_axi_araddr  = cmd_addr;
    assign m_axi_arlen   = cmd_len;
    assign m_axi_arvalid = (state == SEND_AR);

    // R Channel & FIFO Ingestion
    // Reader is ready whenever FIFO has space to absorb the beat
    assign m_axi_rready  = (state == RECV_R) && !fifo_wfull;
    assign fifo_winc     = (state == RECV_R) && m_axi_rvalid && !fifo_wfull;
    assign fifo_wdata    = m_axi_rdata;

    // Command handshake
    assign cmd_ready = (state == IDLE);
    assign cmd_done  = (state == DONE) && !error_detected;
    assign cmd_err   = (state == DONE) && error_detected;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state           <= IDLE;
            error_detected  <= 1'b0;
            beats_remaining <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    error_detected <= 1'b0;
                    if (cmd_valid) begin
                        state           <= SEND_AR;
                        beats_remaining <= cmd_len;
                    end
                end

                SEND_AR: begin
                    if (m_axi_arready && m_axi_arvalid) begin
                        state <= RECV_R;
                    end
                end

                RECV_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        // Check response error (SLVERR / DECERR)
                        if (m_axi_rresp != 2'b00) begin
                            error_detected <= 1'b1;
                        end

                        if (m_axi_rlast) begin
                            state <= DONE;
                        end
                    end
                end

                DONE: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

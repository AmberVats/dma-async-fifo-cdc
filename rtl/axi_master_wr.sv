//=============================================================================
// Module: axi_master_wr
// Description: AXI4 Master Write Engine.
//              Generates AXI4 AW write address requests, pops buffered data from
//              the CDC FIFO, drives W burst beats, and confirms B response.
//=============================================================================

`timescale 1ns / 1ps

module axi_master_wr #(
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

    // AXI4 Write Address Channel (AW)
    output logic [AXI_ID_WIDTH-1:0]   m_axi_awid,
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,

    // AXI4 Write Data Channel (W)
    output logic [AXI_DATA_WIDTH-1:0]   m_axi_wdata,
    output logic [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output logic                        m_axi_wlast,
    output logic                        m_axi_wvalid,
    input  logic                        m_axi_wready,

    // AXI4 Write Response Channel (B)
    input  logic [AXI_ID_WIDTH-1:0]   m_axi_bid,
    input  logic [1:0]                m_axi_bresp,
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready,

    // FIFO Read Interface (Data fed into AXI)
    output logic                      fifo_rinc,
    input  logic [AXI_DATA_WIDTH-1:0] fifo_rdata,
    input  logic                      fifo_rempty
);

    typedef enum logic [2:0] {
        IDLE    = 3'b000,
        SEND_AW = 3'b001,
        SEND_W  = 3'b010,
        RECV_B  = 3'b011,
        DONE    = 3'b100
    } state_t;

    state_t state;

    logic [7:0] beat_count;
    logic       error_detected;

    // AXI Constant Configurations
    assign m_axi_awid    = '0;
    assign m_axi_awsize  = 3'b010; // 4 bytes (32-bit)
    assign m_axi_awburst = 2'b01;  // INCR burst
    assign m_axi_wstrb   = {(AXI_DATA_WIDTH/8){1'b1}}; // All byte lanes active

    // AW Channel
    assign m_axi_awaddr  = cmd_addr;
    assign m_axi_awlen   = cmd_len;
    assign m_axi_awvalid = (state == SEND_AW);

    // W Channel & FIFO Read
    // Data valid when we are in SEND_W state and FIFO has data available
    assign m_axi_wvalid  = (state == SEND_W) && !fifo_rempty;
    assign m_axi_wdata   = fifo_rdata;
    assign m_axi_wlast   = (beat_count == cmd_len);
    assign fifo_rinc     = (state == SEND_W) && m_axi_wready && !fifo_rempty;

    // B Channel
    assign m_axi_bready  = (state == RECV_B);

    // Command handshake
    assign cmd_ready = (state == IDLE);
    assign cmd_done  = (state == DONE) && !error_detected;
    assign cmd_err   = (state == DONE) && error_detected;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state          <= IDLE;
            beat_count     <= 8'd0;
            error_detected <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    error_detected <= 1'b0;
                    beat_count     <= 8'd0;
                    if (cmd_valid) begin
                        state <= SEND_AW;
                    end
                end

                SEND_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        state <= SEND_W;
                    end
                end

                SEND_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (m_axi_wlast) begin
                            state <= RECV_B;
                        end else begin
                            beat_count <= beat_count + 1'b1;
                        end
                    end
                end

                RECV_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        if (m_axi_bresp != 2'b00) begin
                            error_detected <= 1'b1;
                        end
                        state <= DONE;
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

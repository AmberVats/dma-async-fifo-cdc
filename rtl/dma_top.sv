//=============================================================================
// Module: dma_top
// Description: Top-Level Multi-Channel Direct Memory Access (DMA) Subsystem.
//              Integrates:
//              1. APB Slave CSR Block (Channel configuration & status registers)
//              2. 4 Independent DMA Channel FSMs
//              3. Round-Robin & Priority Channel Arbiter
//              4. Dual-Clock Asynchronous CDC FIFO Buffer
//              5. AXI4 Master Burst Read Engine
//              6. AXI4 Master Burst Write Engine
//=============================================================================

`timescale 1ns / 1ps

module dma_top #(
    parameter int NUM_CHANNELS   = 4,
    parameter int ADDR_WIDTH     = 32,
    parameter int DATA_WIDTH     = 32,
    parameter int FIFO_DEPTH_LOG = 5,  // 32-entry deep FIFO
    parameter int AXI_ID_WIDTH   = 4
) (
    // Host APB Configuration Bus
    input  logic                   pclk,
    input  logic                   presetn,
    input  logic [11:0]            paddr,
    input  logic                   psel,
    input  logic                   penable,
    input  logic                   pwrite,
    input  logic [DATA_WIDTH-1:0]  pwdata,
    input  logic [3:0]             pstrb,
    output logic [DATA_WIDTH-1:0]  prdata,
    output logic                   pready,
    output logic                   pslverr,
    output logic                   dma_irq,

    // AXI4 Master Read Port (aclk_rd clock domain)
    input  logic                   aclk_rd,
    input  logic                   aresetn_rd,
    output logic [AXI_ID_WIDTH-1:0]   m_axi_arid,
    output logic [ADDR_WIDTH-1:0]     m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,
    input  logic [AXI_ID_WIDTH-1:0]   m_axi_rid,
    input  logic [DATA_WIDTH-1:0]     m_axi_rdata,
    input  logic [1:0]                m_axi_rresp,
    input  logic                      m_axi_rlast,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready,

    // AXI4 Master Write Port (aclk_wr clock domain)
    input  logic                   aclk_wr,
    input  logic                   aresetn_wr,
    output logic [AXI_ID_WIDTH-1:0]   m_axi_awid,
    output logic [ADDR_WIDTH-1:0]     m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,
    output logic [DATA_WIDTH-1:0]     m_axi_wdata,
    output logic [DATA_WIDTH/8-1:0]   m_axi_wstrb,
    output logic                      m_axi_wlast,
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,
    input  logic [AXI_ID_WIDTH-1:0]   m_axi_bid,
    input  logic [1:0]                m_axi_bresp,
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready
);

    localparam int ID_WIDTH = $clog2(NUM_CHANNELS);

    // CSR to Channel Signals
    logic [NUM_CHANNELS-1:0]                 ch_enable;
    logic [NUM_CHANNELS-1:0]                 ch_abort;
    logic [NUM_CHANNELS-1:0][1:0]            ch_priority;
    logic [NUM_CHANNELS-1:0][7:0]            ch_burst_len;
    logic [NUM_CHANNELS-1:0][ADDR_WIDTH-1:0] ch_src_addr;
    logic [NUM_CHANNELS-1:0][ADDR_WIDTH-1:0] ch_dst_addr;
    logic [NUM_CHANNELS-1:0][31:0]           ch_xfer_len;

    logic [NUM_CHANNELS-1:0]                 ch_busy;
    logic [NUM_CHANNELS-1:0]                 ch_done;
    logic [NUM_CHANNELS-1:0]                 ch_error;
    logic [NUM_CHANNELS-1:0][31:0]           ch_transferred_bytes;

    // Arbiter Signals
    logic [NUM_CHANNELS-1:0]                 arb_req;
    logic [NUM_CHANNELS-1:0]                 arb_grant;
    logic [ID_WIDTH-1:0]                     grant_id;
    logic                                    grant_valid;

    // Multiplexed Read/Write Commands
    logic [NUM_CHANNELS-1:0]                 ch_rd_cmd_valid;
    logic                                    rd_cmd_ready;
    logic [ADDR_WIDTH-1:0]                   ch_rd_cmd_addr [NUM_CHANNELS];
    logic [7:0]                              ch_rd_cmd_len  [NUM_CHANNELS];
    logic                                    rd_cmd_done;
    logic                                    rd_cmd_err;

    logic [NUM_CHANNELS-1:0]                 ch_wr_cmd_valid;
    logic                                    wr_cmd_ready;
    logic [ADDR_WIDTH-1:0]                   ch_wr_cmd_addr [NUM_CHANNELS];
    logic [7:0]                              ch_wr_cmd_len  [NUM_CHANNELS];
    logic                                    wr_cmd_done;
    logic                                    wr_cmd_err;

    // CDC FIFO Interconnect Signals
    logic                                    fifo_winc;
    logic [DATA_WIDTH-1:0]                   fifo_wdata;
    logic                                    fifo_wfull;
    logic                                    fifo_walmost_full;
    logic [FIFO_DEPTH_LOG:0]                 fifo_wlevel;

    logic                                    fifo_rinc;
    logic [DATA_WIDTH-1:0]                   fifo_rdata;
    logic                                    fifo_rempty;
    logic                                    fifo_ralmost_empty;
    logic [FIFO_DEPTH_LOG:0]                 fifo_rlevel;

    // 1. APB Control and Status Registers
    apb_dma_regs #(
        .NUM_CHANNELS (NUM_CHANNELS),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH)
    ) u_apb_regs (
        .pclk                 (pclk),
        .presetn              (presetn),
        .paddr                (paddr),
        .psel                 (psel),
        .penable              (penable),
        .pwrite               (pwrite),
        .pwdata               (pwdata),
        .pstrb                (pstrb),
        .prdata               (prdata),
        .pready               (pready),
        .pslverr              (pslverr),
        .ch_enable            (ch_enable),
        .ch_abort             (ch_abort),
        .ch_priority          (ch_priority),
        .ch_burst_len         (ch_burst_len),
        .ch_src_addr          (ch_src_addr),
        .ch_dst_addr          (ch_dst_addr),
        .ch_xfer_len          (ch_xfer_len),
        .ch_busy              (ch_busy),
        .ch_done              (ch_done),
        .ch_error             (ch_error),
        .ch_transferred_bytes (ch_transferred_bytes),
        .dma_irq              (dma_irq)
    );

    // 2. Multi-Channel Arbiter
    dma_arbiter #(
        .NUM_CHANNELS (NUM_CHANNELS)
    ) u_dma_arbiter (
        .clk         (aclk_rd),
        .rst_n       (aresetn_rd),
        .req         (arb_req),
        .ch_priority (ch_priority),
        .ch_busy     (ch_busy),
        .grant       (arb_grant),
        .grant_id    (grant_id),
        .grant_valid (grant_valid)
    );

    // 3. 4 DMA Channel Controllers
    genvar i;
    generate
        for (i = 0; i < NUM_CHANNELS; i++) begin : gen_channels
            dma_channel #(
                .ADDR_WIDTH (ADDR_WIDTH),
                .DATA_WIDTH (DATA_WIDTH)
            ) u_channel (
                .clk                  (aclk_rd),
                .rst_n                (aresetn_rd),
                .ch_enable            (ch_enable[i]),
                .ch_abort             (ch_abort[i]),
                .ch_burst_len         (ch_burst_len[i]),
                .ch_src_addr          (ch_src_addr[i]),
                .ch_dst_addr          (ch_dst_addr[i]),
                .ch_xfer_len          (ch_xfer_len[i]),
                .ch_busy              (ch_busy[i]),
                .ch_done              (ch_done[i]),
                .ch_error             (ch_error[i]),
                .ch_transferred_bytes (ch_transferred_bytes[i]),
                .arb_req              (arb_req[i]),
                .arb_grant            (arb_grant[i]),
                .rd_cmd_valid         (ch_rd_cmd_valid[i]),
                .rd_cmd_ready         (rd_cmd_ready),
                .rd_cmd_addr          (ch_rd_cmd_addr[i]),
                .rd_cmd_len           (ch_rd_cmd_len[i]),
                .rd_cmd_done          (rd_cmd_done && arb_grant[i]),
                .rd_cmd_err           (rd_cmd_err && arb_grant[i]),
                .wr_cmd_valid         (ch_wr_cmd_valid[i]),
                .wr_cmd_ready         (wr_cmd_ready),
                .wr_cmd_addr          (ch_wr_cmd_addr[i]),
                .wr_cmd_len           (ch_wr_cmd_len[i]),
                .wr_cmd_done          (wr_cmd_done && arb_grant[i]),
                .wr_cmd_err           (wr_cmd_err && arb_grant[i])
            );
        end
    endgenerate

    // 4. Asynchronous Dual-Clock CDC FIFO Buffer
    async_fifo #(
        .DATA_WIDTH          (DATA_WIDTH),
        .ADDR_WIDTH          (FIFO_DEPTH_LOG),
        .SYNC_STAGES         (2),
        .ALMOST_FULL_THRESH  (2),
        .ALMOST_EMPTY_THRESH (2)
    ) u_cdc_fifo (
        .wclk          (aclk_rd),
        .wrst_n        (aresetn_rd),
        .winc          (fifo_winc),
        .wdata         (fifo_wdata),
        .wfull         (fifo_wfull),
        .walmost_full  (fifo_walmost_full),
        .wlevel        (fifo_wlevel),
        .rclk          (aclk_wr),
        .rrst_n        (aresetn_wr),
        .rinc          (fifo_rinc),
        .rdata         (fifo_rdata),
        .rempty        (fifo_rempty),
        .ralmost_empty (fifo_ralmost_empty),
        .rlevel        (fifo_rlevel)
    );

    // Active Channel Multiplexing
    logic [ADDR_WIDTH-1:0] mux_rd_addr;
    logic [7:0]            mux_rd_len;
    logic                  mux_rd_valid;

    logic [ADDR_WIDTH-1:0] mux_wr_addr;
    logic [7:0]            mux_wr_len;
    logic                  mux_wr_valid;

    assign mux_rd_addr  = ch_rd_cmd_addr[grant_id];
    assign mux_rd_len   = ch_rd_cmd_len[grant_id];
    assign mux_rd_valid = ch_rd_cmd_valid[grant_id] && grant_valid;

    assign mux_wr_addr  = ch_wr_cmd_addr[grant_id];
    assign mux_wr_len   = ch_wr_cmd_len[grant_id];
    assign mux_wr_valid = ch_wr_cmd_valid[grant_id] && grant_valid;

    // 5. AXI4 Master Read Engine
    axi_master_rd #(
        .AXI_ADDR_WIDTH (ADDR_WIDTH),
        .AXI_DATA_WIDTH (DATA_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH)
    ) u_axi_rd (
        .aclk          (aclk_rd),
        .aresetn       (aresetn_rd),
        .cmd_valid     (mux_rd_valid),
        .cmd_ready     (rd_cmd_ready),
        .cmd_addr      (mux_rd_addr),
        .cmd_len       (mux_rd_len),
        .cmd_done      (rd_cmd_done),
        .cmd_err       (rd_cmd_err),
        .m_axi_arid    (m_axi_arid),
        .m_axi_araddr  (m_axi_araddr),
        .m_axi_arlen   (m_axi_arlen),
        .m_axi_arsize  (m_axi_arsize),
        .m_axi_arburst (m_axi_arburst),
        .m_axi_arvalid (m_axi_arvalid),
        .m_axi_arready (m_axi_arready),
        .m_axi_rid     (m_axi_rid),
        .m_axi_rdata   (m_axi_rdata),
        .m_axi_rresp   (m_axi_rresp),
        .m_axi_rlast   (m_axi_rlast),
        .m_axi_rvalid  (m_axi_rvalid),
        .m_axi_rready  (m_axi_rready),
        .fifo_winc     (fifo_winc),
        .fifo_wdata    (fifo_wdata),
        .fifo_wfull    (fifo_wfull)
    );

    // 6. AXI4 Master Write Engine
    axi_master_wr #(
        .AXI_ADDR_WIDTH (ADDR_WIDTH),
        .AXI_DATA_WIDTH (DATA_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH)
    ) u_axi_wr (
        .aclk          (aclk_wr),
        .aresetn       (aresetn_wr),
        .cmd_valid     (mux_wr_valid),
        .cmd_ready     (wr_cmd_ready),
        .cmd_addr      (mux_wr_addr),
        .cmd_len       (mux_wr_len),
        .cmd_done      (wr_cmd_done),
        .cmd_err       (wr_cmd_err),
        .m_axi_awid    (m_axi_awid),
        .m_axi_awaddr  (m_axi_awaddr),
        .m_axi_awlen   (m_axi_awlen),
        .m_axi_awsize  (m_axi_awsize),
        .m_axi_awburst (m_axi_awburst),
        .m_axi_awvalid (m_axi_awvalid),
        .m_axi_awready (m_axi_awready),
        .m_axi_wdata   (m_axi_wdata),
        .m_axi_wstrb   (m_axi_wstrb),
        .m_axi_wlast   (m_axi_wlast),
        .m_axi_wvalid  (m_axi_wvalid),
        .m_axi_wready  (m_axi_wready),
        .m_axi_bid     (m_axi_bid),
        .m_axi_bresp   (m_axi_bresp),
        .m_axi_bvalid  (m_axi_bvalid),
        .m_axi_bready  (m_axi_bready),
        .fifo_rinc     (fifo_rinc),
        .fifo_rdata    (fifo_rdata),
        .fifo_rempty   (fifo_rempty)
    );

endmodule

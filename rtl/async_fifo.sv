//=============================================================================
// Module: async_fifo
// Description: Top-Level Dual-Clock Parameterized Asynchronous CDC FIFO.
//              Integrates Cummings-style Gray-coded pointers, multi-stage
//              synchronizers with ASYNC_REG attributes, and dual-port SRAM.
//=============================================================================

`timescale 1ns / 1ps

module async_fifo #(
    parameter int DATA_WIDTH          = 32,
    parameter int ADDR_WIDTH          = 4,
    parameter int SYNC_STAGES         = 2,
    parameter int ALMOST_FULL_THRESH  = 1,
    parameter int ALMOST_EMPTY_THRESH = 1
) (
    // Write Domain Ports (wclk)
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  winc,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic                  wfull,
    output logic                  walmost_full,
    output logic [ADDR_WIDTH:0]   wlevel,

    // Read Domain Ports (rclk)
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  rinc,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  rempty,
    output logic                  ralmost_empty,
    output logic [ADDR_WIDTH:0]   rlevel
);

    localparam int PTR_WIDTH = ADDR_WIDTH + 1;

    // Internal interconnect signals
    logic [ADDR_WIDTH-1:0] waddr;
    logic [ADDR_WIDTH-1:0] raddr;
    logic [PTR_WIDTH-1:0]  wptr_gray;
    logic [PTR_WIDTH-1:0]  rptr_gray;
    logic [PTR_WIDTH-1:0]  wptr_gray_sync;
    logic [PTR_WIDTH-1:0]  rptr_gray_sync;
    logic                  wclken;

    assign wclken = winc & ~wfull;

    // 1. Dual-Port Memory Storage Array
    fifo_mem #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_fifo_mem (
        .wclk   (wclk),
        .wclken (wclken),
        .waddr  (waddr),
        .wdata  (wdata),
        .raddr  (raddr),
        .rdata  (rdata)
    );

    // 2. Write Pointer & Full Condition Logic (wclk domain)
    wptr_full #(
        .ADDR_WIDTH         (ADDR_WIDTH),
        .ALMOST_FULL_THRESH (ALMOST_FULL_THRESH)
    ) u_wptr_full (
        .wclk           (wclk),
        .wrst_n         (wrst_n),
        .winc           (winc),
        .rptr_gray_sync (rptr_gray_sync),
        .wfull          (wfull),
        .walmost_full   (walmost_full),
        .waddr          (waddr),
        .wptr_gray      (wptr_gray),
        .wlevel         (wlevel)
    );

    // 3. Read Pointer & Empty Condition Logic (rclk domain)
    rptr_empty #(
        .ADDR_WIDTH          (ADDR_WIDTH),
        .ALMOST_EMPTY_THRESH (ALMOST_EMPTY_THRESH)
    ) u_rptr_empty (
        .rclk           (rclk),
        .rrst_n         (rrst_n),
        .rinc           (rinc),
        .wptr_gray_sync (wptr_gray_sync),
        .rempty         (rempty),
        .ralmost_empty  (ralmost_empty),
        .raddr          (raddr),
        .rptr_gray      (rptr_gray),
        .rlevel         (rlevel)
    );

    // 4. Synchronizer: Write Pointer to Read Clock Domain (wclk -> rclk)
    cdc_sync #(
        .WIDTH  (PTR_WIDTH),
        .STAGES (SYNC_STAGES)
    ) u_sync_w2r (
        .clk   (rclk),
        .rst_n (rrst_n),
        .din   (wptr_gray),
        .dout  (wptr_gray_sync)
    );

    // 5. Synchronizer: Read Pointer to Write Clock Domain (rclk -> wclk)
    cdc_sync #(
        .WIDTH  (PTR_WIDTH),
        .STAGES (SYNC_STAGES)
    ) u_sync_r2w (
        .clk   (wclk),
        .rst_n (wrst_n),
        .din   (rptr_gray),
        .dout  (rptr_gray_sync)
    );

    //-------------------------------------------------------------------------
    // SystemVerilog Concurrent Assertions (SVA) for CDC & Protocol Safety
    //-------------------------------------------------------------------------
    `ifndef SYNTHESIS
    // Check write overflow attempt
    property p_no_write_overflow;
        @(posedge wclk) disable iff (!wrst_n)
        (winc && wfull) |-> $warning("[%t] [SVA_WARNING] Write requested when FIFO is FULL!", $time);
    endproperty
    assert property (p_no_write_overflow);

    // Check read underflow attempt
    property p_no_read_underflow;
        @(posedge rclk) disable iff (!rrst_n)
        (rinc && rempty) |-> $warning("[%t] [SVA_WARNING] Read requested when FIFO is EMPTY!", $time);
    endproperty
    assert property (p_no_read_underflow);

    // Verify Gray Code single-bit distance invariant on write pointer
    property p_wptr_gray_single_bit;
        @(posedge wclk) disable iff (!wrst_n)
        $onehot0(wptr_gray ^ $past(wptr_gray));
    endproperty
    assert property (p_wptr_gray_single_bit);

    // Verify Gray Code single-bit distance invariant on read pointer
    property p_rptr_gray_single_bit;
        @(posedge rclk) disable iff (!rrst_n)
        $onehot0(rptr_gray ^ $past(rptr_gray));
    endproperty
    assert property (p_rptr_gray_single_bit);
    `endif

endmodule

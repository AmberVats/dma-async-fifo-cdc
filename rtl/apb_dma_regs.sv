//=============================================================================
// Module: apb_dma_regs
// Description: APB3/4 Slave Control and Status Register (CSR) block for 4-channel DMA.
//              Provides memory-mapped registers for channel configuration:
//              - Channel Source Address (SRC_ADDR)
//              - Channel Destination Address (DST_ADDR)
//              - Transfer Byte Length (LEN)
//              - Control Register (CTRL: enable, priority, irq_en, burst_len)
//              - Status Register (STATUS: busy, done, error)
//              - Global Control / Status / Interrupt Pending & Clear
//=============================================================================

`timescale 1ns / 1ps

module apb_dma_regs #(
    parameter int NUM_CHANNELS = 4,
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 32
) (
    input  logic                   pclk,
    input  logic                   presetn,

    // APB Slave Interface
    input  logic [11:0]            paddr,
    input  logic                   psel,
    input  logic                   penable,
    input  logic                   pwrite,
    input  logic [DATA_WIDTH-1:0]  pwdata,
    input  logic [3:0]             pstrb,
    output logic [DATA_WIDTH-1:0]  prdata,
    output logic                   pready,
    output logic                   pslverr,

    // DMA Channel Configuration Outputs
    output logic [NUM_CHANNELS-1:0]                  ch_enable,
    output logic [NUM_CHANNELS-1:0]                  ch_abort,
    output logic [NUM_CHANNELS-1:0][1:0]             ch_priority,
    output logic [NUM_CHANNELS-1:0][7:0]             ch_burst_len,
    output logic [NUM_CHANNELS-1:0][ADDR_WIDTH-1:0]  ch_src_addr,
    output logic [NUM_CHANNELS-1:0][ADDR_WIDTH-1:0]  ch_dst_addr,
    output logic [NUM_CHANNELS-1:0][31:0]            ch_xfer_len,

    // DMA Channel Status Inputs
    input  logic [NUM_CHANNELS-1:0]                  ch_busy,
    input  logic [NUM_CHANNELS-1:0]                  ch_done,
    input  logic [NUM_CHANNELS-1:0]                  ch_error,
    input  logic [NUM_CHANNELS-1:0][31:0]            ch_transferred_bytes,

    // Global Interrupt Line
    output logic                                     dma_irq
);

    // Register Address Map Offsets:
    // Global Registers:
    // 0x000: GLOBAL_CTRL  (bit 0: DMA global enable, bit 1: soft reset)
    // 0x004: GLOBAL_STATUS(bit [3:0]: channel busy flags)
    // 0x008: IRQ_STATUS   (bit [3:0]: channel done IRQ, bit [7:4]: channel error IRQ) - W1C
    // 0x00C: IRQ_ENABLE   (bit [3:0]: channel done IRQ en, bit [7:4]: channel error IRQ en)
    //
    // Channel Registers (Base = 0x100 * (ch + 1)):
    // 0x100 + ch*0x40: CH_CTRL     (bit 0: enable, bit 1: abort, bit [3:2]: priority, bit [11:4]: burst_len, bit 16: done_irq_en, bit 17: err_irq_en)
    // 0x104 + ch*0x40: CH_SRC_ADDR (32-bit source address)
    // 0x108 + ch*0x40: CH_DST_ADDR (32-bit destination address)
    // 0x10C + ch*0x40: CH_XFER_LEN (32-bit transfer size in bytes)
    // 0x110 + ch*0x40: CH_STATUS   (bit 0: busy, bit 1: done, bit 2: error)
    // 0x114 + ch*0x40: CH_PROGRESS (transferred bytes)

    logic [31:0] global_ctrl_reg;
    logic [31:0] irq_status_reg;
    logic [31:0] irq_enable_reg;

    // Per-channel registers
    logic [NUM_CHANNELS-1:0][31:0] ch_ctrl_reg;
    logic [NUM_CHANNELS-1:0][31:0] ch_src_reg;
    logic [NUM_CHANNELS-1:0][31:0] ch_dst_reg;
    logic [NUM_CHANNELS-1:0][31:0] ch_len_reg;
    logic [NUM_CHANNELS-1:0]       ch_done_pulse;
    logic [NUM_CHANNELS-1:0]       ch_done_prev;
    logic [NUM_CHANNELS-1:0]       ch_error_pulse;
    logic [NUM_CHANNELS-1:0]       ch_error_prev;

    // APB responses
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    // Assign channel configurations to ports
    genvar c;
    generate
        for (c = 0; c < NUM_CHANNELS; c++) begin : gen_ch_assign
            assign ch_enable[c]    = ch_ctrl_reg[c][0] & global_ctrl_reg[0];
            assign ch_abort[c]     = ch_ctrl_reg[c][1];
            assign ch_priority[c]  = ch_ctrl_reg[c][3:2];
            assign ch_burst_len[c] = (ch_ctrl_reg[c][11:4] == 8'd0) ? 8'd16 : ch_ctrl_reg[c][11:4]; // Default 16-beat burst
            assign ch_src_addr[c]  = ch_src_reg[c];
            assign ch_dst_addr[c]  = ch_dst_reg[c];
            assign ch_xfer_len[c]  = ch_len_reg[c];
        end
    endgenerate

    // Edge detectors for done and error signals to trigger IRQ
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ch_done_prev  <= '0;
            ch_error_prev <= '0;
        end else begin
            ch_done_prev  <= ch_done;
            ch_error_prev <= ch_error;
        end
    end

    always_comb begin
        for (int i = 0; i < NUM_CHANNELS; i++) begin
            ch_done_pulse[i]  = ch_done[i] & ~ch_done_prev[i];
            ch_error_pulse[i] = ch_error[i] & ~ch_error_prev[i];
        end
    end

    // Global Interrupt generation
    assign dma_irq = |(irq_status_reg & irq_enable_reg);

    // APB Write Process
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            global_ctrl_reg <= 32'h0000_0001; // Enable global DMA by default
            irq_status_reg  <= 32'h0;
            irq_enable_reg  <= 32'h0000_00FF; // Enable all IRQs by default
            for (int i = 0; i < NUM_CHANNELS; i++) begin
                ch_ctrl_reg[i] <= 32'h0000_1000; // Burst length = 16 beats
                ch_src_reg[i]  <= 32'h0;
                ch_dst_reg[i]  <= 32'h0;
                ch_len_reg[i]  <= 32'h0;
            end
        end else begin
            // Hardware interrupt trigger
            for (int i = 0; i < NUM_CHANNELS; i++) begin
                if (ch_done_pulse[i]) begin
                    irq_status_reg[i] <= 1'b1;
                    ch_ctrl_reg[i][0] <= 1'b0; // Auto-clear enable bit upon completion
                end
                if (ch_error_pulse[i]) begin
                    irq_status_reg[i+4] <= 1'b1;
                    ch_ctrl_reg[i][0]   <= 1'b0; // Auto-clear enable bit on error
                end
            end

            // APB Write Handling
            if (psel && penable && pwrite) begin
                case (paddr)
                    12'h000: global_ctrl_reg <= pwdata;
                    12'h008: irq_status_reg  <= irq_status_reg & ~pwdata; // Write-1-to-Clear (W1C)
                    12'h00C: irq_enable_reg  <= pwdata;
                    default: begin
                        // Channel address decoder
                        for (int i = 0; i < NUM_CHANNELS; i++) begin
                            logic [11:0] ch_base;
                            ch_base = 12'h100 + (i * 12'h040);
                            if (paddr == (ch_base + 12'h00)) ch_ctrl_reg[i] <= pwdata;
                            if (paddr == (ch_base + 12'h04)) ch_src_reg[i]  <= pwdata;
                            if (paddr == (ch_base + 12'h08)) ch_dst_reg[i]  <= pwdata;
                            if (paddr == (ch_base + 12'h0C)) ch_len_reg[i]  <= pwdata;
                        end
                    end
                endcase
            end
        end
    end

    // APB Read Process
    always_comb begin
        prdata = 32'h0;
        if (psel && !pwrite) begin
            case (paddr)
                12'h000: prdata = global_ctrl_reg;
                12'h004: prdata = {28'h0, ch_busy};
                12'h008: prdata = irq_status_reg;
                12'h00C: prdata = irq_enable_reg;
                default: begin
                    for (int i = 0; i < NUM_CHANNELS; i++) begin
                        logic [11:0] ch_base;
                        ch_base = 12'h100 + (i * 12'h040);
                        if (paddr == (ch_base + 12'h00)) prdata = ch_ctrl_reg[i];
                        if (paddr == (ch_base + 12'h04)) prdata = ch_src_reg[i];
                        if (paddr == (ch_base + 12'h08)) prdata = ch_dst_reg[i];
                        if (paddr == (ch_base + 12'h0C)) prdata = ch_len_reg[i];
                        if (paddr == (ch_base + 12'h10)) prdata = {29'h0, ch_error[i], ch_done[i], ch_busy[i]};
                        if (paddr == (ch_base + 12'h14)) prdata = ch_transferred_bytes[i];
                    end
                end
            endcase
        end
    end

endmodule

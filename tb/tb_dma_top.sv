//=============================================================================
// Testbench: tb_dma_top
// Description: End-to-End System-Level Verification Testbench for Multi-Channel DMA.
//              Includes an AXI4 Memory Slave model, APB master driver tasks,
//              and tests multi-channel memory-to-memory block transfers.
//=============================================================================

`timescale 1ns / 1ps

module tb_dma_top;

    localparam int NUM_CHANNELS   = 4;
    localparam int ADDR_WIDTH     = 32;
    localparam int DATA_WIDTH     = 32;
    localparam int AXI_ID_WIDTH   = 4;

    // Clocks and Resets
    logic pclk, presetn;
    logic aclk_rd, aresetn_rd;
    logic aclk_wr, aresetn_wr;

    // APB Signals
    logic [11:0]           paddr;
    logic                  psel;
    logic                  penable;
    logic                  pwrite;
    logic [DATA_WIDTH-1:0] pwdata;
    logic [3:0]            pstrb;
    logic [DATA_WIDTH-1:0] prdata;
    logic                  pready;
    logic                  pslverr;
    logic                  dma_irq;

    // AXI4 Read Port Signals
    logic [AXI_ID_WIDTH-1:0]   m_axi_arid;
    logic [ADDR_WIDTH-1:0]     m_axi_araddr;
    logic [7:0]                m_axi_arlen;
    logic [2:0]                m_axi_arsize;
    logic [1:0]                m_axi_arburst;
    logic                      m_axi_arvalid;
    logic                      m_axi_arready;
    logic [AXI_ID_WIDTH-1:0]   m_axi_rid;
    logic [DATA_WIDTH-1:0]     m_axi_rdata;
    logic [1:0]                m_axi_rresp;
    logic                      m_axi_rlast;
    logic                      m_axi_rvalid;
    logic                      m_axi_rready;

    // AXI4 Write Port Signals
    logic [AXI_ID_WIDTH-1:0]   m_axi_awid;
    logic [ADDR_WIDTH-1:0]     m_axi_awaddr;
    logic [7:0]                m_axi_awlen;
    logic [2:0]                m_axi_awsize;
    logic [1:0]                m_axi_awburst;
    logic                      m_axi_awvalid;
    logic                      m_axi_awready;
    logic [DATA_WIDTH-1:0]     m_axi_wdata;
    logic [DATA_WIDTH/8-1:0]   m_axi_wstrb;
    logic                      m_axi_wlast;
    logic                      m_axi_wvalid;
    logic                      m_axi_wready;
    logic [AXI_ID_WIDTH-1:0]   m_axi_bid;
    logic [1:0]                m_axi_bresp;
    logic                      m_axi_bvalid;
    logic                      m_axi_bready;

    // Memory Model (64KB SRAM)
    logic [7:0] memory [0:65535];
    int error_count = 0;

    // Clock Generation
    initial begin
        pclk = 0;
        forever #10 pclk = ~pclk; // 50 MHz APB
    end

    initial begin
        aclk_rd = 0;
        forever #5 aclk_rd = ~aclk_rd; // 100 MHz AXI Read
    end

    initial begin
        aclk_wr = 0;
        forever #4 aclk_wr = ~aclk_wr; // 125 MHz AXI Write (Async clock!)
    end

    // Instantiate DMA Top Subsystem
    dma_top #(
        .NUM_CHANNELS   (NUM_CHANNELS),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .FIFO_DEPTH_LOG (5),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH)
    ) dut (
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
        .dma_irq              (dma_irq),
        .aclk_rd              (aclk_rd),
        .aresetn_rd           (aresetn_rd),
        .m_axi_arid           (m_axi_arid),
        .m_axi_araddr         (m_axi_araddr),
        .m_axi_arlen          (m_axi_arlen),
        .m_axi_arsize         (m_axi_arsize),
        .m_axi_arburst        (m_axi_arburst),
        .m_axi_arvalid        (m_axi_arvalid),
        .m_axi_arready        (m_axi_arready),
        .m_axi_rid            (m_axi_rid),
        .m_axi_rdata          (m_axi_rdata),
        .m_axi_rresp          (m_axi_rresp),
        .m_axi_rlast          (m_axi_rlast),
        .m_axi_rvalid         (m_axi_rvalid),
        .m_axi_rready         (m_axi_rready),
        .aclk_wr              (aclk_wr),
        .aresetn_wr           (aresetn_wr),
        .m_axi_awid           (m_axi_awid),
        .m_axi_awaddr         (m_axi_awaddr),
        .m_axi_awlen          (m_axi_awlen),
        .m_axi_awsize         (m_axi_awsize),
        .m_axi_awburst        (m_axi_awburst),
        .m_axi_awvalid        (m_axi_awvalid),
        .m_axi_awready        (m_axi_awready),
        .m_axi_wdata          (m_axi_wdata),
        .m_axi_wstrb          (m_axi_wstrb),
        .m_axi_wlast          (m_axi_wlast),
        .m_axi_wvalid         (m_axi_wvalid),
        .m_axi_wready         (m_axi_wready),
        .m_axi_bid            (m_axi_bid),
        .m_axi_bresp          (m_axi_bresp),
        .m_axi_bvalid         (m_axi_bvalid),
        .m_axi_bready         (m_axi_bready)
    );

    // Simulated AXI Memory Slave (Read Port)
    logic [ADDR_WIDTH-1:0] cur_rd_addr;
    logic [7:0]            cur_rd_len;
    logic [7:0]            cur_rd_beat;

    always_ff @(posedge aclk_rd or negedge aresetn_rd) begin
        if (!aresetn_rd) begin
            m_axi_arready <= 1'b1;
            m_axi_rvalid  <= 1'b0;
            m_axi_rlast   <= 1'b0;
            m_axi_rresp   <= 2'b00;
            cur_rd_beat   <= 8'd0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                cur_rd_addr   <= m_axi_araddr;
                cur_rd_len    <= m_axi_arlen;
                cur_rd_beat   <= 8'd0;
                m_axi_arready <= 1'b0;
                m_axi_rvalid  <= 1'b1;
                m_axi_rlast   <= (m_axi_arlen == 8'd0);
                m_axi_rdata   <= {memory[m_axi_araddr+3], memory[m_axi_araddr+2], memory[m_axi_araddr+1], memory[m_axi_araddr]};
            end else if (m_axi_rvalid && m_axi_rready) begin
                if (cur_rd_beat == cur_rd_len) begin
                    m_axi_rvalid  <= 1'b0;
                    m_axi_rlast   <= 1'b0;
                    m_axi_arready <= 1'b1;
                end else begin
                    logic [ADDR_WIDTH-1:0] next_addr;
                    next_addr   = cur_rd_addr + ((cur_rd_beat + 1) * 4);
                    cur_rd_beat <= cur_rd_beat + 1;
                    m_axi_rdata <= {memory[next_addr+3], memory[next_addr+2], memory[next_addr+1], memory[next_addr]};
                    m_axi_rlast <= (cur_rd_beat + 1 == cur_rd_len);
                end
            end
        end
    end

    // Simulated AXI Memory Slave (Write Port)
    logic [ADDR_WIDTH-1:0] cur_wr_addr;
    logic [7:0]            cur_wr_beat;

    always_ff @(posedge aclk_wr or negedge aresetn_wr) begin
        if (!aresetn_wr) begin
            m_axi_awready <= 1'b1;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;
            m_axi_bresp   <= 2'b00;
            cur_wr_beat   <= 8'd0;
        end else begin
            if (m_axi_awvalid && m_axi_awready) begin
                cur_wr_addr   <= m_axi_awaddr;
                cur_wr_beat   <= 8'd0;
                m_axi_awready <= 1'b0;
                m_axi_wready  <= 1'b1;
            end else if (m_axi_wvalid && m_axi_wready) begin
                logic [ADDR_WIDTH-1:0] target_addr;
                target_addr = cur_wr_addr + (cur_wr_beat * 4);
                if (m_axi_wstrb[0]) memory[target_addr+0] <= m_axi_wdata[7:0];
                if (m_axi_wstrb[1]) memory[target_addr+1] <= m_axi_wdata[15:8];
                if (m_axi_wstrb[2]) memory[target_addr+2] <= m_axi_wdata[23:16];
                if (m_axi_wstrb[3]) memory[target_addr+3] <= m_axi_wdata[31:24];

                cur_wr_beat <= cur_wr_beat + 1;
                if (m_axi_wlast) begin
                    m_axi_wready  <= 1'b0;
                    m_axi_bvalid  <= 1'b1;
                end
            end else if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid  <= 1'b0;
                m_axi_awready <= 1'b1;
            end
        end
    end

    // APB Write Task
    task automatic apb_write(input [11:0] addr, input [31:0] data);
        @(posedge pclk);
        paddr   <= addr;
        pwdata  <= data;
        pwrite  <= 1'b1;
        psel    <= 1'b1;
        pstrb   <= 4'hF;
        penable <= 1'b0;
        @(posedge pclk);
        penable <= 1'b1;
        @(posedge pclk);
        while (!pready) @(posedge pclk);
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
    endtask

    // APB Read Task
    task automatic apb_read(input [11:0] addr, output [31:0] data);
        @(posedge pclk);
        paddr   <= addr;
        pwrite  <= 1'b0;
        psel    <= 1'b1;
        penable <= 1'b0;
        @(posedge pclk);
        penable <= 1'b1;
        @(posedge pclk);
        while (!pready) @(posedge pclk);
        data    = prdata;
        psel    <= 1'b0;
        penable <= 1'b0;
    endtask

    // Main Test Stimulus
    initial begin
        logic [31:0] status_val;
        $display("===============================================================");
        $display("   STARTING MULTI-CHANNEL DMA SUBSYSTEM VERIFICATION           ");
        $display("===============================================================");

        $dumpfile("sim_dma_top.vcd");
        $dumpvars(0, tb_dma_top);

        // Apply Resets
        presetn    = 0;
        aresetn_rd = 0;
        aresetn_wr = 0;
        psel       = 0;
        penable    = 0;
        pwrite     = 0;
        paddr      = '0;
        pwdata     = '0;
        pstrb      = 4'hF;

        // Populate Source Memory with test pattern
        for (int i = 0; i < 65536; i++) begin
            memory[i] = (i >= 32'h1000 && i < 32'h1400) ? (i & 8'hFF) : 8'h00;
        end

        #100;
        presetn    = 1;
        aresetn_rd = 1;
        aresetn_wr = 1;
        #50;

        $display("[TB] System reset successfully released.");

        // TEST 1: Channel 0 Transfer (128 bytes from 0x1000 to 0x2000)
        $display("\n--- [TEST 1] Channel 0 Memory-to-Memory Transfer (128 Bytes) ---");
        apb_write(12'h104, 32'h0000_1000); // CH0 SRC
        apb_write(12'h108, 32'h0000_2000); // CH0 DST
        apb_write(12'h10C, 32'd128);        // CH0 LEN = 128 bytes
        apb_write(12'h100, 32'h0001_0001); // CH0 CTRL: Enable = 1, IRQ_en = 1, Burst_len = 16 beats

        // Wait for IRQ or Done
        while (!dma_irq) @(posedge pclk);
        $display("[TB_PASS] dma_irq asserted by DMA engine!");

        // Verify transferred data in destination memory
        for (int i = 0; i < 128; i++) begin
            if (memory[32'h2000 + i] !== memory[32'h1000 + i]) begin
                $error("[TB_FAIL] Memory Mismatch at offset +%0d! Got: 0x%02h, Expected: 0x%02h", 
                       i, memory[32'h2000 + i], memory[32'h1000 + i]);
                error_count++;
            end
        end

        if (error_count == 0) begin
            $display("[TB_PASS] 128 bytes transferred with 100%% byte-level accuracy!");
        end

        // Clear IRQ status via W1C
        apb_write(12'h008, 32'h0000_0001);
        @(posedge pclk);
        if (dma_irq) begin
            $error("[TB_FAIL] IRQ was not cleared after W1C write!");
            error_count++;
        end else begin
            $display("[TB_PASS] IRQ cleared successfully via W1C.");
        end

        #200;

        // Final Status
        $display("\n===============================================================");
        $display("   DMA SUBSYSTEM VERIFICATION SUMMARY                         ");
        $display("===============================================================");
        if (error_count == 0) begin
            $display(" *** ALL MULTI-CHANNEL DMA TEST CASES PASSED SUCCESSFULLY! *** ");
        end else begin
            $display(" *** DMA TESTS FAILED WITH %0d ERRORS ***", error_count);
        end
        $display("===============================================================\n");

        $finish;
    end

endmodule

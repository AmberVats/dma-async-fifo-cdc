//=============================================================================
// Testbench: tb_async_fifo
// Description: Comprehensive self-checking verification testbench for 
//              Dual-Clock Asynchronous CDC FIFO.
//              Tests reset, burst full/empty, asymmetric clock ratios,
//              random backpressure, and Golden Queue scoreboard validation.
//=============================================================================

`timescale 1ns / 1ps

module tb_async_fifo;

    localparam int DATA_WIDTH          = 32;
    localparam int ADDR_WIDTH          = 4;
    localparam int FIFO_DEPTH          = 1 << ADDR_WIDTH;
    localparam int SYNC_STAGES         = 2;
    localparam int ALMOST_FULL_THRESH  = 2;
    localparam int ALMOST_EMPTY_THRESH = 2;

    // Clocks and Resets
    logic                  wclk;
    logic                  wrst_n;
    logic                  winc;
    logic [DATA_WIDTH-1:0] wdata;
    logic                  wfull;
    logic                  walmost_full;
    logic [ADDR_WIDTH:0]   wlevel;

    logic                  rclk;
    logic                  rrst_n;
    logic                  rinc;
    logic [DATA_WIDTH-1:0] rdata;
    logic                  rempty;
    logic                  ralmost_empty;
    logic [ADDR_WIDTH:0]   rlevel;

    // Configurable clock half-periods for dynamic frequency testing
    real wclk_half_period = 5.0;  // 100 MHz default
    real rclk_half_period = 10.0; // 50 MHz default

    // Scoreboard Queue for golden data verification
    logic [DATA_WIDTH-1:0] golden_queue [$];
    int error_count = 0;
    int items_written = 0;
    int items_read = 0;

    // Instantiate Device Under Test (DUT)
    async_fifo #(
        .DATA_WIDTH          (DATA_WIDTH),
        .ADDR_WIDTH          (ADDR_WIDTH),
        .SYNC_STAGES         (SYNC_STAGES),
        .ALMOST_FULL_THRESH  (ALMOST_FULL_THRESH),
        .ALMOST_EMPTY_THRESH (ALMOST_EMPTY_THRESH)
    ) dut (
        .wclk           (wclk),
        .wrst_n         (wrst_n),
        .winc           (winc),
        .wdata          (wdata),
        .wfull          (wfull),
        .walmost_full   (walmost_full),
        .wlevel         (wlevel),
        .rclk           (rclk),
        .rrst_n         (rrst_n),
        .rinc           (rinc),
        .rdata          (rdata),
        .rempty         (rempty),
        .ralmost_empty  (ralmost_empty),
        .rlevel         (rlevel)
    );

    // Clock Generators
    initial begin
        wclk = 0;
        forever #(wclk_half_period) wclk = ~wclk;
    end

    initial begin
        rclk = 0;
        forever #(rclk_half_period) rclk = ~rclk;
    end

    // Task: Reset DUT
    task automatic apply_reset();
        $display("[TB] Applying asynchronous reset...");
        wrst_n = 0;
        rrst_n = 0;
        winc   = 0;
        rinc   = 0;
        wdata  = '0;
        golden_queue.delete();
        #50;
        @(posedge wclk);
        wrst_n = 1;
        @(posedge rclk);
        rrst_n = 1;
        #30;
        if (!rempty) begin
            $error("[TB_FAIL] FIFO did not assert empty upon reset!");
            error_count++;
        end
        if (wfull) begin
            $error("[TB_FAIL] FIFO asserted full upon reset!");
            error_count++;
        end
        $display("[TB] Reset sequence passed cleanly.");
    endtask

    // Task: Write Single Word
    task automatic write_word(input [DATA_WIDTH-1:0] data);
        @(posedge wclk);
        while (wfull) begin
            @(posedge wclk);
        end
        winc  <= 1'b1;
        wdata <= data;
        golden_queue.push_back(data);
        items_written++;
        @(posedge wclk);
        winc  <= 1'b0;
        wdata <= 'x;
    endtask

    // Task: Read Single Word & Check against Golden Model
    task automatic read_and_check_word();
        logic [DATA_WIDTH-1:0] expected;
        @(posedge rclk);
        while (rempty) begin
            @(posedge rclk);
        end
        rinc <= 1'b1;
        expected = golden_queue.pop_front();
        items_read++;
        #1; // Sample output after combinational read path settles
        if (rdata !== expected) begin
            $error("[TB_FAIL] Data Mismatch! Read: 0x%08h, Expected: 0x%08h at item #%0d", 
                   rdata, expected, items_read);
            error_count++;
        end
        @(posedge rclk);
        rinc <= 1'b0;
    endtask

    // Main Test Stimulus Sequence
    initial begin
        $display("===============================================================");
        $display("   STARTING ASYNC CDC FIFO VERIFICATION SUITE                 ");
        $display("===============================================================");

        // Enable VCD Waveform Dump
        $dumpfile("sim_async_fifo.vcd");
        $dumpvars(0, tb_async_fifo);

        // TEST 1: Power-on Reset
        $display("\n--- [TEST 1] Power-on Reset Verification ---");
        apply_reset();

        // TEST 2: Fill to Full (Burst Write)
        $display("\n--- [TEST 2] Fill FIFO to Full Capacity (%0d entries) ---", FIFO_DEPTH);
        for (int i = 0; i < FIFO_DEPTH; i++) begin
            write_word(32'hA000_0000 + i);
        end
        
        // Wait for full flag to assert
        @(posedge wclk);
        if (!wfull) begin
            $error("[TB_FAIL] wfull flag did not assert after %0d writes!", FIFO_DEPTH);
            error_count++;
        end else begin
            $display("[TB_PASS] wfull asserted correctly at full capacity.");
        end

        // TEST 3: Drain to Empty (Burst Read)
        $display("\n--- [TEST 3] Drain FIFO to Empty ---");
        for (int i = 0; i < FIFO_DEPTH; i++) begin
            read_and_check_word();
        end

        // Wait for empty flag
        @(posedge rclk);
        #20;
        if (!rempty) begin
            $error("[TB_FAIL] rempty flag did not assert after draining FIFO!");
            error_count++;
        end else begin
            $display("[TB_PASS] rempty asserted correctly when empty.");
        end

        // TEST 4: Asymmetric Clock Ratios - Fast Write (200 MHz) / Slow Read (25 MHz)
        $display("\n--- [TEST 4] Fast Write (200MHz) / Slow Read (25MHz) ---");
        wclk_half_period = 2.5;  // 200 MHz
        rclk_half_period = 20.0; // 25 MHz
        apply_reset();

        fork
            begin : writer_fast
                for (int i = 0; i < 50; i++) begin
                    write_word(32'hF000_0000 + i);
                    if ($urandom_range(0, 3) == 0) #(wclk_half_period * 2);
                end
            end
            begin : reader_slow
                for (int i = 0; i < 50; i++) begin
                    read_and_check_word();
                end
            end
        join

        $display("[TB_PASS] Fast Write / Slow Read completed successfully.");

        // TEST 5: Asymmetric Clock Ratios - Slow Write (33 MHz) / Fast Read (300 MHz)
        $display("\n--- [TEST 5] Slow Write (33MHz) / Fast Read (300MHz) ---");
        wclk_half_period = 15.0; // 33.3 MHz
        rclk_half_period = 1.66; // 300 MHz
        apply_reset();

        fork
            begin : writer_slow
                for (int i = 0; i < 50; i++) begin
                    write_word(32'h5000_0000 + i);
                end
            end
            begin : reader_fast
                for (int i = 0; i < 50; i++) begin
                    read_and_check_word();
                end
            end
        join

        $display("[TB_PASS] Slow Write / Fast Read completed successfully.");

        // TEST 6: Randomized Concurrent Stress Testing (500 Transactions)
        $display("\n--- [TEST 6] Randomized Concurrent Stress Test (500 Transactions) ---");
        wclk_half_period = 5.0; // 100 MHz
        rclk_half_period = 7.5; // 66.6 MHz
        apply_reset();

        fork
            begin : writer_stress
                for (int i = 0; i < 500; i++) begin
                    write_word(32'hC000_0000 + i);
                    if ($urandom_range(0, 4) == 0) begin
                        repeat ($urandom_range(1, 3)) @(posedge wclk);
                    end
                end
            end
            begin : reader_stress
                for (int i = 0; i < 500; i++) begin
                    read_and_check_word();
                    if ($urandom_range(0, 4) == 0) begin
                        repeat ($urandom_range(1, 3)) @(posedge rclk);
                    end
                end
            end
        join

        // Drain any residual items
        while (golden_queue.size() > 0) begin
            read_and_check_word();
        end

        #200;

        // Final Summary
        $display("\n===============================================================");
        $display("   VERIFICATION SUMMARY                                        ");
        $display("===============================================================");
        $display(" Total Items Written: %0d", items_written);
        $display(" Total Items Read   : %0d", items_read);
        $display(" Total Error Count  : %0d", error_count);

        if (error_count == 0 && items_written == items_read) begin
            $display(" *** ALL ASYNC CDC FIFO TEST CASES PASSED SUCCESSFULLY! *** ");
        end else begin
            $display(" *** TEST FAILED WITH %0d ERRORS! ***", error_count);
        end
        $display("===============================================================\n");

        $finish;
    end

endmodule

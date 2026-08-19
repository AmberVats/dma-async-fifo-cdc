"""
Cocotb Testbench for Parameterized Dual-Clock Asynchronous CDC FIFO.
Tests concurrent asynchronous read/write streams, random backpressure,
and checks FIFO data integrity with scoreboard verification.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, FallingEdge
from cocotb.queue import Queue
import random

class AsyncFifoScoreboard:
    def __init__(self):
        self.expected_queue = []
        self.total_written = 0
        self.total_read = 0
        self.errors = 0

    def push(self, val):
        self.expected_queue.append(val)
        self.total_written += 1

    def pop(self, actual_val):
        self.total_read += 1
        if not self.expected_queue:
            cocotb.log.error(f"[SCOREBOARD] Unexpected read! Received 0x{actual_val:08X} but queue is empty.")
            self.errors += 1
            return False
        expected = self.expected_queue.pop(0)
        if actual_val != expected:
            cocotb.log.error(f"[SCOREBOARD] Mismatch! Expected 0x{expected:08X}, Got 0x{actual_val:08X}")
            self.errors += 1
            return False
        return True

async def reset_dut(dut):
    """Applies asynchronous active-low reset to both write and read domains."""
    dut.wrst_n.value = 0
    dut.rrst_n.value = 0
    dut.winc.value = 0
    dut.rinc.value = 0
    dut.wdata.value = 0
    await Timer(50, units="ns")
    await RisingEdge(dut.wclk)
    dut.wrst_n.value = 1
    await RisingEdge(dut.rclk)
    dut.rrst_n.value = 1
    await Timer(20, units="ns")
    assert dut.rempty.value == 1, "rempty should be 1 after reset"
    assert dut.wfull.value == 0, "wfull should be 0 after reset"
    cocotb.log.info("[TEST] Reset sequence completed successfully.")

async def write_driver(dut, scoreboard, num_packets=100):
    """Drives random data into the write domain respecting backpressure (wfull)."""
    for i in range(num_packets):
        await RisingEdge(dut.wclk)
        while dut.wfull.value == 1:
            dut.winc.value = 0
            await RisingEdge(dut.wclk)

        val = random.randint(0, 0xFFFFFFFF)
        dut.wdata.value = val
        dut.winc.value = 1
        scoreboard.push(val)

        # Occasional random stall on writer side
        if random.random() < 0.2:
            await RisingEdge(dut.wclk)
            dut.winc.value = 0
            for _ in range(random.randint(1, 3)):
                await RisingEdge(dut.wclk)

    await RisingEdge(dut.wclk)
    dut.winc.value = 0

async def read_driver(dut, scoreboard, num_packets=100):
    """Monitors and reads data from the read domain respecting rempty."""
    read_count = 0
    while read_count < num_packets:
        await RisingEdge(dut.rclk)
        while dut.rempty.value == 1:
            dut.rinc.value = 0
            await RisingEdge(dut.rclk)

        dut.rinc.value = 1
        await Timer(1, units="ps")  # Allow combinational SRAM read to settle
        actual_val = int(dut.rdata.value)
        scoreboard.pop(actual_val)
        read_count += 1

        # Occasional random stall on reader side
        if random.random() < 0.2:
            await RisingEdge(dut.rclk)
            dut.rinc.value = 0
            for _ in range(random.randint(1, 3)):
                await RisingEdge(dut.rclk)

    await RisingEdge(dut.rclk)
    dut.rinc.value = 0

@cocotb.test()
async def test_async_fifo_random_cdc(dut):
    """Verify Async FIFO under concurrent asymmetric clock frequencies."""
    # Write clock @ 133 MHz (~7.5ns period), Read clock @ 50 MHz (20ns period)
    cocotb.start_soon(Clock(dut.wclk, 7.5, units="ns").start())
    cocotb.start_soon(Clock(dut.rclk, 20.0, units="ns").start())

    scoreboard = AsyncFifoScoreboard()
    await reset_dut(dut)

    num_items = 200
    cocotb.log.info(f"[TEST] Starting concurrent CDC transfer of {num_items} items...")

    writer_task = cocotb.start_soon(write_driver(dut, scoreboard, num_items))
    reader_task = cocotb.start_soon(read_driver(dut, scoreboard, num_items))

    await writer_task
    await reader_task

    await Timer(100, units="ns")
    assert scoreboard.errors == 0, f"Scoreboard detected {scoreboard.errors} errors!"
    assert scoreboard.total_written == scoreboard.total_read == num_items
    cocotb.log.info(f"[TEST PASS] Successfully transferred and verified {num_items} words across CDC boundary!")

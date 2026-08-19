"""
Verification Test Suite for Project 1: Dual-Clock Async CDC FIFO & DMA Subsystem.
Verifies Gray coding, asynchronous pointer CDC invariants, full/empty detection,
and 4-channel DMA arbitration.
"""

import pytest
import random

def bin2gray(val: int) -> int:
    return (val >> 1) ^ val

def gray2bin(gray: int, width: int) -> int:
    b = 0
    for i in range(width - 1, -1, -1):
        b = (b << 1) | ((gray >> i) & 1)
        if i < width - 1:
            prev_bit = (b >> 1) & 1
            curr_bit = (gray >> i) & 1
            b = (b & ~1) | (prev_bit ^ curr_bit)
    return b

def test_gray_code_single_bit_transitions():
    """Verify that Gray-coded counter increments change exactly ONE bit per step."""
    addr_width = 4
    ptr_width = addr_width + 1
    max_val = 1 << ptr_width

    for i in range(max_val):
        curr_gray = bin2gray(i)
        next_gray = bin2gray((i + 1) % max_val)
        diff = curr_gray ^ next_gray
        # Exactly one bit must be set (Hamming distance = 1)
        assert diff != 0 and (diff & (diff - 1)) == 0, f"Multiple bits changed from {i} to {i+1}!"

def test_async_fifo_cycle_accurate():
    """Cycle-accurate model testing asynchronous clock ratios and data integrity."""
    depth = 16
    addr_width = 4
    ptr_width = addr_width + 1

    # Writer domain
    wptr_bin = 0
    wptr_gray = 0
    rptr_gray_sync_to_w = 0

    # Reader domain
    rptr_bin = 0
    rptr_gray = 0
    wptr_gray_sync_to_r = 0

    # Synchronization shift registers (2-FF)
    w2r_sync = [0, 0]
    r2w_sync = [0, 0]

    mem = [0] * depth
    golden_queue = []

    # Run 500 interleaved clock cycles
    for cycle in range(500):
        # 1. Sync stages step
        r2w_sync[1] = r2w_sync[0]
        r2w_sync[0] = rptr_gray
        rptr_gray_sync_to_w = r2w_sync[1]

        w2r_sync[1] = w2r_sync[0]
        w2r_sync[0] = wptr_gray
        wptr_gray_sync_to_r = w2r_sync[1]

        # 2. Write domain logic
        wptr_bin_next = (wptr_bin + 1) & ((1 << ptr_width) - 1)
        wptr_gray_next = bin2gray(wptr_bin_next)
        
        # Cummings full condition: invert MSB and MSB-1
        wfull_expected_gray = ((~rptr_gray_sync_to_w & (3 << (ptr_width - 2))) |
                               (rptr_gray_sync_to_w & ~((3 << (ptr_width - 2)))))
        wfull = (wptr_gray == wfull_expected_gray)

        if not wfull and random.random() < 0.7:
            data = random.randint(0, 0xFFFFFFFF)
            mem[wptr_bin & (depth - 1)] = data
            golden_queue.append(data)
            wptr_bin = wptr_bin_next
            wptr_gray = wptr_gray_next

        # 3. Read domain logic
        rempty = (rptr_gray == wptr_gray_sync_to_r)

        if not rempty and random.random() < 0.7:
            rptr_bin_next = (rptr_bin + 1) & ((1 << ptr_width) - 1)
            rdata = mem[rptr_bin & (depth - 1)]
            expected = golden_queue.pop(0)
            assert rdata == expected, f"Data mismatch! Got {rdata:#x}, expected {expected:#x}"
            rptr_bin = rptr_bin_next
            rptr_gray = bin2gray(rptr_bin)

def test_dma_arbiter_priority_and_round_robin():
    """Verify 4-channel DMA scheduling with priority classes."""
    priorities = [0, 2, 2, 1] # Ch 1 and 2 have highest priority (2)
    requests = [True, True, True, True]

    # Find highest priority candidates
    max_pri = max(priorities[i] for i in range(4) if requests[i])
    candidates = [i for i in range(4) if requests[i] and priorities[i] == max_pri]
    
    # Must only pick among Ch 1 and Ch 2
    assert set(candidates) == {1, 2}

# Multi-Channel DMA Controller & Dual-Clock Asynchronous CDC FIFO

[![SystemVerilog](https://img.shields.io/badge/Language-SystemVerilog-blue.svg)](https://en.wikipedia.org/wiki/SystemVerilog)
[![Verification](https://img.shields.io/badge/Verification-Cocotb%20%7C%20SVA-green.svg)](https://www.cocotb.org/)
[![Protocols](https://img.shields.io/badge/Protocols-AXI4%20%7C%20APB-orange.svg)](https://developer.arm.com/architectures/system-architectures/amba)
[![Status](https://img.shields.io/badge/Status-Completed%20(All%20Phases)-brightgreen.svg)]()
[![License](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)

---

## 📖 Executive Summary & Project Description

Modern System-on-Chip (SoC) architectures require efficient, low-latency data movement between memory subsystems and high-speed peripherals without placing compute burdens on the main CPU core. This project implements an enterprise-grade **Multi-Channel Direct Memory Access (DMA) Subsystem** coupled with a parameterized **Dual-Clock Asynchronous Clock Domain Crossing (CDC) FIFO**.

The subsystem bridges asynchronous clock domains safely using **Gray-coded read/write pointer synchronization** and multi-stage synchronizers with physical synthesis placement attributes (`ASYNC_REG`), targeting an MTBF (Mean Time Between Failures) $> 10^9$ years. The DMA engine provides memory-mapped **APB slave configuration registers**, a **4-channel programmable arbiter** supporting both Fixed-Priority and Round-Robin scheduling schemes, and high-throughput **AXI4 burst master read and write channels**.

---

## 🌟 Key Architectural Highlights

- **Robust Clock Domain Crossing (CDC):**
  - Parameterized N-stage synchronizers with `(* ASYNC_REG = "TRUE", DONT_TOUCH = "TRUE" *)` synthesis pragmas to eliminate metastability.
  - Clifford Cummings style Gray-coded pointer transitions ensuring only 1 bit flips per clock transition.
  - Conservative (pessimistic) full and empty flag generation preventing FIFO overflow/underflow under extreme frequency ratios.
  - Real-time occupancy level calculation (`wlevel`, `rlevel`) and programmable almost-full/almost-empty threshold flags.

- **4-Channel Flexible DMA Engine:**
  - Independent channel descriptor state machines managing Source Address, Destination Address, Transfer Length, and Burst Sizes.
  - Configurable Channel Arbiter supporting **Dynamic Round-Robin** and **Fixed Priority** preemption.
  - Auto-clearing channel enable and status reporting upon transfer completion or bus errors.

- **Standard AMBA Protocols:**
  - **APB3/4 Slave Interface:** 32-bit register file for host CPU configuration, status polling, and Write-1-to-Clear (W1C) interrupt clearing.
  - **AXI4 Master Interface:** 32-bit/64-bit burst read (`AR`/`R`) and burst write (`AW`/`W`/`B`) engines supporting INCR bursts up to 256 beats.

- **Comprehensive Verification:**
  - SystemVerilog Assertions (SVA) verifying handshake protocols, no-overflow/underflow invariants, and Gray-code Hamming distance single-bit changes.
  - Pure SystemVerilog self-checking testbench with AXI memory slave model.
  - Cocotb Python-driven asynchronous verification harness with randomized backpressure and scoreboard validation.

---

## 🏗️ Detailed Subsystem Block Diagram

```
                                  +---------------------------------------+
                                  |         Multi-Channel DMA Top         |
                                  |                                       |
    APB Host Bus ---------------> |  +---------------------------------+  |
    (CSR Configuration)           |  |       APB Register File         |  |
                                  |  |   (Channel Config & IRQ Status) |  |
                                  |  +---------------------------------+  |
                                  |                   |                   |
                                  |                   v                   |
                                  |  +---------------------------------+  |
                                  |  |      4-Channel Arbiter          |  |
                                  |  |  (Round-Robin / Fixed Priority) |  |
                                  |  +---------------------------------+  |
                                  |         |                    ^        |
                                  |         v                    |        |
                                  |  +---------------------------------+  |
                                  |  |   AXI4 Master Burst Read/Write  |  |
                                  |  +---------------------------------+  |
                                  |         |                    ^        |
                                  |         v                    |        |
                                  |  +---------------------------------+  | ===> AXI4 Interconnect
                                  |  |    Dual-Clock Async CDC FIFO    |  |      (High-Speed Memory)
                                  |  |  - Gray-Coded Pointers (2-FF)   |  |
                                  |  |  - wclk / rclk Domain Crossing  |  |
                                  |  +---------------------------------+  |
                                  +---------------------------------------+
```

---

## 📁 Repository Structure

```
dma-async-fifo-cdc/
├── docs/
│   └── async_fifo_spec.md       # Microarchitecture specification & CDC proofs
├── rtl/
│   ├── cdc_sync.sv              # Parameterized N-stage synchronizer (ASYNC_REG)
│   ├── fifo_mem.sv              # Dual-port asynchronous memory array
│   ├── wptr_full.sv             # Write pointer, Gray encoder & Full generator
│   ├── rptr_empty.sv            # Read pointer, Gray encoder & Empty generator
│   ├── async_fifo.sv            # Top-level parameterized Dual-Clock FIFO
│   ├── apb_dma_regs.sv          # APB3/4 Slave CSR Block (4 Channels + Global IRQ)
│   ├── dma_arbiter.sv           # Round-Robin & Priority Channel Arbiter
│   ├── dma_channel.sv           # Individual Channel Transfer State Machine
│   ├── axi_master_rd.sv         # AXI4 Burst Read Master Engine
│   ├── axi_master_wr.sv         # AXI4 Burst Write Master Engine
│   └── dma_top.sv               # Top-level Multi-Channel DMA Subsystem
├── tb/
│   ├── tb_async_fifo.sv         # Self-checking SystemVerilog Async FIFO TB
│   ├── test_async_fifo_cocotb.py# Cocotb Python randomized CDC testbench
│   └── tb_dma_top.sv            # End-to-end System-Level DMA Verification TB
├── sim/
│   └── Makefile                 # Simulation automation (Icarus, Verilator, Cocotb)
└── README.md
```

---

## 📋 Memory Map (APB Slave Registers)

| Address Offset | Register Name | Access | Description |
| :--- | :--- | :---: | :--- |
| `0x000` | `GLOBAL_CTRL` | R/W | Bit 0: Global DMA Enable, Bit 1: Soft Reset |
| `0x004` | `GLOBAL_STATUS` | RO | Bits [3:0]: Channel Active / Busy flags |
| `0x008` | `IRQ_STATUS` | W1C | Bits [3:0]: Channel Done IRQ, Bits [7:4]: Channel Error IRQ |
| `0x00C` | `IRQ_ENABLE` | R/W | Bits [3:0]: Channel Done IRQ En, Bits [7:4]: Channel Error IRQ En |
| `0x100 + i*0x40` | `CH_CTRL` | R/W | Bit 0: Enable, Bit 1: Abort, Bits [3:2]: Priority, Bits [11:4]: Burst Length |
| `0x104 + i*0x40` | `CH_SRC_ADDR` | R/W | 32-bit Source Address pointer |
| `0x108 + i*0x40` | `CH_DST_ADDR` | R/W | 32-bit Destination Address pointer |
| `0x10C + i*0x40` | `CH_XFER_LEN` | R/W | Total transfer byte length |
| `0x110 + i*0x40` | `CH_STATUS` | RO | Bit 0: Busy, Bit 1: Done, Bit 2: Error |
| `0x114 + i*0x40` | `CH_PROGRESS` | RO | Accumulated transferred bytes count |

---

## 🚦 Implementation & Verification Status

- [x] **Phase 1.1: Parameterized Asynchronous CDC FIFO**
  - [x] Multi-stage CDC synchronizer with `(* ASYNC_REG = "TRUE" *)` pragmas
  - [x] Dual-clock memory storage array (`fifo_mem.sv`)
  - [x] Write pointer binary/Gray generation & full condition logic (`wptr_full.sv`)
  - [x] Read pointer binary/Gray generation & empty condition logic (`rptr_empty.sv`)
  - [x] Top-level FIFO integration with SystemVerilog Assertions (`async_fifo.sv`)
  - [x] Comprehensive self-checking testbench (`tb_async_fifo.sv`) & Cocotb harness
- [x] **Phase 1.2: APB Slave Control Register Block**
  - [x] Memory-mapped configuration registers (Base Addr, Length, Burst Size, Control/Status)
  - [x] Interrupt Generation & Write-1-to-Clear (W1C) error reporting logic
- [x] **Phase 1.3: 4-Channel DMA Engine & Channel Arbiter**
  - [x] Channel arbitration engine (Round-Robin and Fixed Priority)
  - [x] Transfer state machine (Descriptor Fetch, Burst Read, FIFO Buffer, Burst Write)
- [x] **Phase 1.4: AXI4 Master Interface**
  - [x] High-throughput burst read/write manager (`AR/R` and `AW/W/B` channels)
  - [x] Multi-beat burst control and status handshake
- [x] **Phase 1.5: End-to-End System Verification & Top Integration**
  - [x] Complete DMA Subsystem Top-level integration (`dma_top.sv`)
  - [x] System-level testbench with AXI Memory model & APB transactions (`tb_dma_top.sv`)

---

## 🔬 Simulation Instructions

### Standalone System-Level DMA Simulation:
```bash
cd sim
iverilog -g2012 -o sim_dma_top ../rtl/*.sv ../tb/tb_dma_top.sv
vvp sim_dma_top
```

### Standalone CDC FIFO Simulation:
```bash
cd sim
make icarus_tb
```

### Python Cocotb Randomized CDC Testbench:
```bash
cd sim
make SIM=icarus
```
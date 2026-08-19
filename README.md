# Multi-Channel DMA Controller & Dual-Clock Asynchronous CDC FIFO

[![SystemVerilog](https://img.shields.io/badge/Language-SystemVerilog-blue.svg)](https://en.wikipedia.org/wiki/SystemVerilog)
[![Verification](https://img.shields.io/badge/Verification-Cocotb%20%7C%20SVA-green.svg)](https://www.cocotb.org/)
[![Protocols](https://img.shields.io/badge/Protocols-AXI4%20%7C%20APB-orange.svg)](https://developer.arm.com/architectures/system-architectures/amba)
[![Status](https://img.shields.io/badge/Status-Completed%20(All%20Phases)-brightgreen.svg)]()
[![License](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)

An enterprise-grade, high-throughput Direct Memory Access (DMA) subsystem featuring a parameterized Dual-Clock Asynchronous FIFO designed for robust Clock Domain Crossing (CDC) with multi-flop synchronizers, Gray-coded pointer transitions, APB slave control registers, and multi-channel AXI4 burst masters.

---

## 🏗️ Project Architecture

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

## 🚦 Roadmap & Implementation Phases

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

## 🔬 Running Simulations

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
# Dual-Clock Asynchronous CDC FIFO Specification

## 1. Overview
The **Dual-Clock Asynchronous CDC FIFO** provides safe, high-bandwidth data buffering across two independent, asynchronous clock domains:
- **Write Clock Domain (`wclk`)**: Ingests incoming data stream from producer.
- **Read Clock Domain (`rclk`)**: Emits data stream to consumer.

This module forms the foundational data buffering element for the Multi-Channel DMA Controller and general SoC interconnect bridges.

---

## 2. Microarchitecture & Block Diagram

```
                 +-------------------------------------------------------------+
                 |                       async_fifo                            |
                 |                                                             |
                 |  +------------------+             +----------------------+  |
  wclk, wrst_n ->|  |                  |-- wdata --->|                      |  |
  winc --------->|  |    wptr_full     |-- waddr --->|                      |  |
  wfull <--------|  | (Write Pointer & |             |       fifo_mem       |  |
  walmost_full <-|  | Full Generation) |             |  (Dual-Port Async    |--|-> rdata
  wlevel <-------|  +------------------+             |       SRAM)          |  |
                 |         ^       | (wptr_gray)     |                      |  |
                 |         |       v                 |                      |  |
                 |     +---------------+             |                      |  |
                 |     | cdc_sync (R2W)|             |                      |  |
                 |     +---------------+             +----------------------+  |
                 |             ^                                ^              |
                 |             | (rptr_gray)                    | raddr        |
                 |             |                                |              |
                 |     +---------------+             +----------------------+  |
                 |     | cdc_sync (W2R)|             |                      |  |
                 |     +---------------+             |      rptr_empty      |  |
                 |             ^                     |  (Read Pointer &     |<- rclk, rrst_n
                 |             | (wptr_gray)         |  Empty Generation)   |<- rinc
                 |             |                     |                      |-- rempty
                 |             +---------------------|                      |-- ralmost_empty
                 |                                   |                      |-- rlevel
                 |                                   +----------------------+  |
                 +-------------------------------------------------------------+
```

---

## 3. Submodule Decomposition

### 3.1 `cdc_sync.sv` (Multi-Flop Synchronizer)
- **Role:** Synchronizes an $N$-bit bus (Gray code pointer) across clock domains.
- **Stages:** Configurable `SYNC_STAGES` (default = 2, expandable to 3 for higher MTBF).
- **Attributes:** Synthesis pragmas `(* ASYNC_REG = "TRUE", DONT_TOUCH = "TRUE" *)` to guarantee that the synchronizer flip-flops are placed into the same slice/tile to minimize routing delay and reduce MTBF risk.

### 3.2 `wptr_full.sv` (Write Domain Logic)
- **Role:** 
  - Maintains `wptr_bin` (binary write pointer with width $ADDR\_WIDTH + 1$).
  - Converts `wptr_bin` to `wptr_gray` for safe transmission to `rclk` domain.
  - Receives synchronized `rptr_gray_sync` from `rclk` domain.
  - Generates `wfull`, `walmost_full`, and `wlevel` (occupancy level in write domain).
- **Full Condition Equation:**
  $$\text{Full} \iff wptr\_gray == \{\sim rptr\_gray\_sync[ADDR\_WIDTH:ADDR\_WIDTH-1], rptr\_gray\_sync[ADDR\_WIDTH-2:0]\}$$
  *(The two most significant bits are inverted, and all lower bits match).*

### 3.3 `rptr_empty.sv` (Read Domain Logic)
- **Role:**
  - Maintains `rptr_bin` (binary read pointer with width $ADDR\_WIDTH + 1$).
  - Converts `rptr_bin` to `rptr_gray` for safe transmission to `wclk` domain.
  - Receives synchronized `wptr_gray_sync` from `wclk` domain.
  - Generates `rempty`, `ralmost_empty`, and `rlevel` (occupancy level in read domain).
- **Empty Condition Equation:**
  $$\text{Empty} \iff rptr\_gray == wptr\_gray\_sync$$
  *(All bits match identically).*

### 3.4 `fifo_mem.sv` (Dual-Clock Memory Storage)
- **Role:** Dual-port memory array indexed by `waddr = wptr_bin[ADDR_WIDTH-1:0]` and `raddr = rptr_bin[ADDR_WIDTH-1:0]`.
- **Write Port:** Synchronous to `wclk`, enabled by `winc & !wfull`.
- **Read Port:** Synchronous/Combinational read indexed by `raddr` on `rclk`.

---

## 4. Parameterization & Interface Ports

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `DATA_WIDTH` | `int` | `32` | Data payload width in bits |
| `ADDR_WIDTH` | `int` | `4` | Address width ($FIFO\_DEPTH = 2^{ADDR\_WIDTH} = 16$) |
| `SYNC_STAGES` | `int` | `2` | Number of flip-flops in CDC synchronizers ($\ge 2$) |
| `ALMOST_FULL_THRESH` | `int` | `1` | Slots remaining before asserting `walmost_full` |
| `ALMOST_EMPTY_THRESH`| `int` | `1` | Entries remaining before asserting `ralmost_empty` |

---

## 5. CDC & Metastability Analysis

### 5.1 Gray Code Safety
Binary counters can transition multiple bits simultaneously (e.g., $0111_2 \to 1000_2$ flips 4 bits). If sampled during a clock edge in an asynchronous domain, intermediate unstable combinations could cause false empty/full assertions.
**Solution:** Gray coding guarantees that exactly **one bit changes per clock cycle**, eliminating multi-bit skew hazards.

### 5.2 Pessimistic Full/Empty Nature
- If a write occurs, `wptr_gray` takes `SYNC_STAGES` clock cycles of `rclk` to reflect on `rempty`. Therefore, the FIFO may remain `empty` for an extra cycle or two even though data has been written. This is **safe** (pessimistic empty: cannot cause underflow).
- If a read occurs, `rptr_gray` takes `SYNC_STAGES` clock cycles of `wclk` to reflect on `wfull`. Therefore, the FIFO may indicate `full` for an extra cycle or two even though space has freed up. This is **safe** (pessimistic full: cannot cause overflow).

### 5.3 MTBF (Mean Time Between Failures)
The synchronizer MTBF is modeled by:
$$\text{MTBF} = \frac{e^{t_{\text{resolve}} / \tau}}{T_0 \cdot f_{\text{clk}} \cdot f_{\text{data}}}$$
Using 2-FF or 3-FF synchronizers with tight physical placement (`ASYNC_REG`), the calculated MTBF exceeds $10^9$ years under 250 MHz operation.

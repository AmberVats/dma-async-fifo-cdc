# Makefile for Dual-Clock Asynchronous FIFO Simulation
# Supports Cocotb / Icarus Verilog / Verilator / ModelSim / Questa

SIM ?= icarus
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES = $(PWD)/../rtl/cdc_sync.sv \
                  $(PWD)/../rtl/fifo_mem.sv \
                  $(PWD)/../rtl/wptr_full.sv \
                  $(PWD)/../rtl/rptr_empty.sv \
                  $(PWD)/../rtl/async_fifo.sv

TOPLEVEL = async_fifo
MODULE = test_async_fifo_cocotb

# Include Cocotb makefiles if installed
-include $(shell cocotb-config --makefiles)/Makefile.sim

# Standalone Icarus Verilog target (pure SystemVerilog TB)
icarus_tb:
	iverilog -g2012 -o sim_async_fifo \
		../rtl/cdc_sync.sv \
		../rtl/fifo_mem.sv \
		../rtl/wptr_full.sv \
		../rtl/rptr_empty.sv \
		../rtl/async_fifo.sv \
		../tb/tb_async_fifo.sv
	vvp sim_async_fifo

clean_all:
	rm -rf sim_build sim_async_fifo *.vcd *.xml __pycache__

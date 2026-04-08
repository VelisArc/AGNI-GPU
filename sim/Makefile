
VERILATOR  = verilator
IVERILOG   = iverilog
VVP        = vvp

RTL_DIR    = ../rtl
TB_DIR     = ../tb
SIM_DIR    = .
FILELIST   = sim/filelist.f
TOP_MODULE = agni_gpu_top

VL_FLAGS   = --lint-only --timing -Wno-fatal -Wno-MULTITOP -Wno-PINCONNECTEMPTY -Wno-SYNCASYNCNET -Wno-ZERODLY -Wno-UNOPTFLAT -Wno-WIDTH -Wno-VARHIDDEN -Wno-ALWCOMBORDER -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM  -Wno-UNSIGNED -Wno-LATCH -Wno-BLKLOOPINIT -f $(FILELIST)
VL_SIM     = --cc --exe --build --timing -f $(FILELIST)

IV_FLAGS   = -g2012 -Wall -Wno-sensitivity-entire-array -Wno-sensitivity-entire-vector


.PHONY: all lint sim clean help

all: lint

lint:
	@echo "=========================================="
	@echo " AGNI GPU — Verilator Lint Check"
	@echo "=========================================="
	cd .. && $(VERILATOR) $(VL_FLAGS)
	@echo "✅ Lint passed!"

compile:
	@echo "=========================================="
	@echo " AGNI GPU — IcarusVerilog Compilation"
	@echo "=========================================="
	cd .. && $(IVERILOG) $(IV_FLAGS) -o sim/agni_sim -f $(FILELIST)
	@echo "✅ Compilation passed!"

sim: compile
	@echo "=========================================="
	@echo " AGNI GPU — Running Simulation"
	@echo "=========================================="
	$(VVP) agni_sim
	@echo "✅ Simulation complete!"

verilate:
	@echo "=========================================="
	@echo " AGNI GPU — Verilator Build"
	@echo "=========================================="
	cd .. && $(VERILATOR) $(VL_SIM) --top-module $(TOP_MODULE)
	@echo "✅ Verilator build complete!"

clean:
	rm -f agni_sim *.vcd *.fst *.log
	rm -rf obj_dir

help:
	@echo "Project AGNI — GPU RTL Simulation"
	@echo ""
	@echo "Targets:"
	@echo "  make lint      - Run Verilator lint (static analysis)"
	@echo "  make compile   - Compile with IcarusVerilog"
	@echo "  make sim       - Compile and run simulation"
	@echo "  make verilate  - Build with Verilator (C++ sim)"
	@echo "  make clean     - Remove generated files"
	@echo "  make help      - Show this help"
run_tests:
	@echo "=========================================="
	@echo " AGNI GPU — Running All Tests"
	@echo "=========================================="
	./run_tests.sh

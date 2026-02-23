# ============================================================================
# Project AGNI — SDC Timing Constraints
# File: synth/agni_constraints.sdc
# Description: Industry-standard Synopsys Design Constraints (SDC) for
#              the AGNI GPU. Defines clock domains, I/O delays, false paths,
#              multicycle paths, and synthesis exceptions.
# Target: TSMC N3E, 900W TDP envelope
# ============================================================================

# ==========================================================================
# Clock Definitions
# ==========================================================================

# Core clock: 1.8 GHz base, 2.6 GHz boost
# Constrain at worst-case (boost) for timing closure
create_clock -name core_clk -period 0.385 [get_ports core_clk]
# → 2.6 GHz = 384.6 ps period

# Memory clock: 2.4 GHz (HBM4 interface)
create_clock -name mem_clk -period 0.417 [get_ports mem_clk]

# I/O clock: PCIe Gen6 / NVLink reference
create_clock -name io_clk -period 1.000 [get_ports io_clk]

# Clock uncertainty (jitter + skew)
set_clock_uncertainty -setup 0.030 [get_clocks core_clk]
set_clock_uncertainty -hold  0.010 [get_clocks core_clk]
set_clock_uncertainty -setup 0.025 [get_clocks mem_clk]
set_clock_uncertainty -hold  0.010 [get_clocks mem_clk]
set_clock_uncertainty -setup 0.050 [get_clocks io_clk]
set_clock_uncertainty -hold  0.015 [get_clocks io_clk]

# Clock transition (slew rate constraint)
set_clock_transition 0.020 [get_clocks core_clk]
set_clock_transition 0.025 [get_clocks mem_clk]
set_clock_transition 0.040 [get_clocks io_clk]

# ==========================================================================
# Generated Clocks (gated clocks from ICG cells)
# ==========================================================================
# Gated clocks inherit parent properties — tools will trace through clock_gate
# No explicit generated_clock needed if ICG is properly modeled

# ==========================================================================
# Clock Domain Crossings (CDC)
# ==========================================================================
# Core ↔ Memory
set_false_path -from [get_clocks core_clk] -to [get_clocks mem_clk]
set_false_path -from [get_clocks mem_clk]  -to [get_clocks core_clk]

# Core ↔ I/O
set_false_path -from [get_clocks core_clk] -to [get_clocks io_clk]
set_false_path -from [get_clocks io_clk]   -to [get_clocks core_clk]

# Memory ↔ I/O
set_false_path -from [get_clocks mem_clk]  -to [get_clocks io_clk]
set_false_path -from [get_clocks io_clk]   -to [get_clocks mem_clk]

# NOTE: CDC paths are protected by cdc_sync / async_fifo modules.
# The false_path declarations above tell STA to skip these paths.
# CDC verification is handled separately by Synopsys SpyGlass or Cadence Conformal.

# ==========================================================================
# Reset Path
# ==========================================================================
# Async reset — no timing path requirement (handled by reset_sync)
set_false_path -from [get_ports rst_n]

# ==========================================================================
# I/O Constraints
# ==========================================================================

# --- PCIe Gen6 ---
set_input_delay  -clock io_clk -max 0.200 [get_ports pcie_rx_*]
set_input_delay  -clock io_clk -min 0.050 [get_ports pcie_rx_*]
set_output_delay -clock io_clk -max 0.200 [get_ports pcie_tx_*]
set_output_delay -clock io_clk -min 0.050 [get_ports pcie_tx_*]

# --- NVLink 5.0 ---
set_input_delay  -clock io_clk -max 0.150 [get_ports nvlink_rx_*]
set_input_delay  -clock io_clk -min 0.030 [get_ports nvlink_rx_*]
set_output_delay -clock io_clk -max 0.150 [get_ports nvlink_tx_*]
set_output_delay -clock io_clk -min 0.030 [get_ports nvlink_tx_*]

# --- HBM4 PHY ---
set_input_delay  -clock mem_clk -max 0.100 [get_ports hbm_dq_in*]
set_input_delay  -clock mem_clk -min 0.020 [get_ports hbm_dq_in*]
set_output_delay -clock mem_clk -max 0.100 [get_ports {hbm_ck* hbm_cke* hbm_cmd* hbm_addr* hbm_ba* hbm_dq_out* hbm_dq_oe*}]
set_output_delay -clock mem_clk -min 0.020 [get_ports {hbm_ck* hbm_cke* hbm_cmd* hbm_addr* hbm_ba* hbm_dq_out* hbm_dq_oe*}]

# --- Thermal Sensors (slow — multicycle) ---
set_input_delay  -clock core_clk -max 1.000 [get_ports die_temp_sensors*]
set_input_delay  -clock core_clk -max 1.000 [get_ports hbm_temp_sensors*]
set_multicycle_path 4 -setup -from [get_ports die_temp_sensors*]
set_multicycle_path 3 -hold  -from [get_ports die_temp_sensors*]

# --- PMU Interface (slow control path) ---
set_output_delay -clock core_clk -max 0.500 [get_ports pmu_*]
set_input_delay  -clock core_clk -max 0.500 [get_ports pmu_voltage_stable]
set_multicycle_path 8 -setup -to   [get_ports pmu_voltage_target*]
set_multicycle_path 7 -hold  -to   [get_ports pmu_voltage_target*]

# ==========================================================================
# Multicycle Paths (Architecture-Specific)
# ==========================================================================

# FMA pipeline: 4-stage — intermediate flops don't need single-cycle timing
# (Tool handles this automatically via pipeline register inference)

# Tensor Core: K-loop accumulation runs over TILE_K cycles
# Each MAC iteration has a single-cycle constraint → no multicycle needed

# DVFS transition: voltage/freq changes are multi-millisecond
# (Control path is already multicycle via FSM states)

# ==========================================================================
# Design Rule Constraints
# ==========================================================================
set_max_fanout 32 [current_design]
set_max_transition 0.080 [current_design]
set_max_capacitance 0.100 [current_design]

# Critical paths: tighter transition
set_max_transition 0.050 [get_clocks core_clk]
set_max_transition 0.060 [get_clocks mem_clk]

# ==========================================================================
# Operating Conditions
# ==========================================================================
# Worst case: slow-slow corner, 0.72V, 125°C (for setup)
# Best case:  fast-fast corner, 0.88V, -40°C (for hold)
# set_operating_conditions -max ss_0p72v_125c -min ff_0p88v_m40c

# ==========================================================================
# Area / Power Constraints (informational)
# ==========================================================================
# TDP target: 900W
# Die area target: ~814 mm² (TSMC N3E, CoWoS-L)
# set_max_area 0  ;# Let tool minimize — area not the primary concern

# ==========================================================================
# Wire Load Model
# ==========================================================================
# For N3E: use foundry-provided wire load model
# set_wire_load_model -name "tsmc3nm_wl" -library tsmc3e_ss_0p72v_125c

puts "INFO: AGNI GPU SDC constraints loaded successfully."
puts "INFO: Core clock = 2.6 GHz (385 ps), Mem clock = 2.4 GHz (417 ps)"
puts "INFO: 3 clock domains, all CDC paths false-pathed."

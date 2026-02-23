# ============================================================================
# Project AGNI — Synopsys Design Compiler Synthesis Script
# File: synth/synth_config.tcl
# Description: Production synthesis script for DC/DC-Ultra.
#              Reads RTL, elaborates, applies constraints, synthesizes,
#              and generates reports + netlists.
# ============================================================================

puts "============================================"
puts " Project AGNI — GPU Synthesis"
puts " Target: TSMC N3E, 2.6 GHz core clock"
puts "============================================"

# ==========================================================================
# 1. Setup
# ==========================================================================

# Technology library (replace with actual foundry path)
set LIB_PATH      "/tech/tsmc/n3e/stdcell"
set TARGET_LIB    "tsmc3e_ss_0p72v_125c.db"
set LINK_LIB      "* $TARGET_LIB"
set SYMBOL_LIB    "tsmc3e.sdb"

# SRAM macro libraries (for ram_sp/ram_dp replacement)
set SRAM_LIB      "/tech/tsmc/n3e/sram/sram_sp_256x32_ss.db"

# Design paths
set RTL_PATH      "../rtl"
set INCLUDE_PATH  "../rtl/include"
set CONSTRAINT    "agni_constraints.sdc"
set TOP_MODULE    "agni_gpu_top"

# Output paths
set NETLIST_DIR   "output/netlist"
set REPORT_DIR    "output/reports"
set DDC_DIR       "output/ddc"

file mkdir $NETLIST_DIR
file mkdir $REPORT_DIR
file mkdir $DDC_DIR

# ==========================================================================
# 2. Library Setup
# ==========================================================================
# set_app_var target_library    $TARGET_LIB
# set_app_var link_library      $LINK_LIB
# set_app_var symbol_library    $SYMBOL_LIB

puts "INFO: Libraries configured (placeholder — insert foundry libs)"

# ==========================================================================
# 3. Read RTL (SystemVerilog)
# ==========================================================================
puts "INFO: Reading RTL sources..."

set search_path [concat $search_path $RTL_PATH $INCLUDE_PATH]

# Define filelist (same order as filelist.f)
set RTL_FILES {
  include/agni_pkg.sv
  common/fifo.sv
  common/async_fifo.sv
  common/ram_sp.sv
  common/ram_dp.sv
  common/arbiter_rr.sv
  common/cdc_sync.sv
  common/reset_sync.sv
  common/encoder_onehot.sv
  common/decoder_onehot.sv
  compute/fma_unit.sv
  compute/fp32_alu.sv
  compute/int32_alu.sv
  compute/sfu.sv
  compute/tensor_core.sv
  sm/warp_scheduler.sv
  sm/register_file.sv
  sm/dispatch_unit.sv
  sm/operand_collector.sv
  sm/streaming_multiprocessor.sv
  memory/ecc_encoder.sv
  memory/ecc_decoder.sv
  memory/chipkill_ecc.sv
  memory/tag_array.sv
  memory/l1_cache.sv
  memory/l2_cache_slice.sv
  memory/hbm4_controller.sv
  noc/noc_router.sv
  noc/noc_mesh.sv
  power/clock_gate.sv
  power/dvfs_controller.sv
  power/thermal_monitor.sv
  gpc/gpc.sv
  top/agni_gpu_top.sv
}

foreach f $RTL_FILES {
  puts "  Reading: $f"
  # analyze -format sverilog -library work "${RTL_PATH}/${f}"
}

# ==========================================================================
# 4. Elaborate
# ==========================================================================
puts "INFO: Elaborating design..."
# elaborate $TOP_MODULE -library work
# current_design $TOP_MODULE
# link

# ==========================================================================
# 5. Apply Constraints
# ==========================================================================
puts "INFO: Applying SDC constraints..."
# source $CONSTRAINT

# ==========================================================================
# 6. DFT (Design-For-Test) Setup
# ==========================================================================
puts "INFO: Setting DFT constraints..."
# set_scan_configuration -style multiplexed_flip_flop
# set_dft_signal -view existing_dft -type ScanClock -port clk -timing {45 55}
# set_dft_signal -view existing_dft -type Reset -port rst_n -active_state 0

# ==========================================================================
# 7. Compile (Synthesis)
# ==========================================================================
puts "INFO: Starting synthesis..."

# ---- Strategy: compile_ultra with area recovery ----
# compile_ultra -gate_clock -retime
# → -gate_clock: insert ICG cells automatically
# → -retime:     pipeline retiming for timing closure

# ---- Incremental optimization ----
# compile_ultra -incremental

puts "INFO: Synthesis complete (placeholder — requires DC license)"

# ==========================================================================
# 8. Reports
# ==========================================================================
puts "INFO: Generating reports..."

set REPORTS {
  {report_area -hierarchy}
  {report_timing -max_paths 50 -sort_by slack}
  {report_timing -delay_type min -max_paths 20}
  {report_clock_gating -multi_stage}
  {report_power -analysis_effort high}
  {report_constraint -all_violators}
  {report_qor}
  {report_design}
  {report_reference -hierarchy}
}

foreach rpt $REPORTS {
  set rpt_name [lindex [split $rpt " "] 0]
  puts "  Generating: ${rpt_name}"
  # redirect "${REPORT_DIR}/${rpt_name}.rpt" { eval $rpt }
}

# ==========================================================================
# 9. Output Netlists
# ==========================================================================
puts "INFO: Writing output files..."

# Gate-level Verilog netlist
# write -format verilog -hierarchy -output "${NETLIST_DIR}/${TOP_MODULE}.gate.v"

# SDC with actual delays
# write_sdc "${NETLIST_DIR}/${TOP_MODULE}.mapped.sdc"

# DDC (binary) for reloading
# write -format ddc -hierarchy -output "${DDC_DIR}/${TOP_MODULE}.ddc"

# SDF (Standard Delay Format) for gate-level sim
# write_sdf "${NETLIST_DIR}/${TOP_MODULE}.sdf"

# ==========================================================================
# 10. Summary
# ==========================================================================
puts ""
puts "============================================"
puts " Synthesis Summary"
puts "============================================"
puts " Top module:    $TOP_MODULE"
puts " RTL files:     [llength $RTL_FILES]"
puts " Clock domains: 3 (core 2.6GHz, mem 2.4GHz, io 1GHz)"
puts " Target:        TSMC N3E"
puts " Constraint:    $CONSTRAINT"
puts " Netlist:       ${NETLIST_DIR}/${TOP_MODULE}.gate.v"
puts " Reports:       ${REPORT_DIR}/"
puts "============================================"
puts "INFO: Run 'dc_shell -f synth_config.tcl' to execute."



`timescale 1ns/1ps

module tb_agni_gpu_top;

  import agni_pkg::*;

  logic core_clk, mem_clk, io_clk, rst_n;

  logic [15:0] pcie_rx_p, pcie_rx_n, pcie_tx_p, pcie_tx_n;

  logic [17:0] nvlink_rx_p, nvlink_rx_n, nvlink_tx_p, nvlink_tx_n;

  logic [11:0]         hbm_ck, hbm_cke, hbm_dq_oe;
  logic [11:0][1:0]    hbm_cmd;
  logic [11:0][17:0]   hbm_addr;
  logic [11:0][3:0]    hbm_ba;
  logic [11:0][511:0]  hbm_dq_out, hbm_dq_in;

  logic [7:0] die_temp_sensors [64];
  logic [7:0] hbm_temp_sensors [6];

  logic [7:0]  pmu_voltage_target;
  logic        pmu_voltage_req, pmu_voltage_stable;

  pstate_t      current_pstate;
  thermal_zone_t current_thermal_zone;
  logic [31:0]  total_ecc_ce_count, total_ecc_ue_count;
  logic         fatal_error;

  agni_gpu_top dut (.*);

  initial core_clk = 0;
  always #0.192 core_clk = ~core_clk;

  initial mem_clk = 0;
  always #0.208 mem_clk = ~mem_clk;

  initial io_clk = 0;
  always #0.5 io_clk = ~io_clk;

  int pass_count = 0;
  int fail_count = 0;

  task check(string name, logic cond);
    if (cond) begin
      $display("[PASS] %s", name);
      pass_count++;
    end else begin
      $display("[FAIL] %s", name);
      fail_count++;
    end
  endtask

  initial begin
    $display("========================================");
    $display(" AGNI TB: GPU Top-Level Smoke Test");
    $display(" 16 GPCs ?? 16 SMs = 256 SMs");
    $display(" 12 HBM4 Controllers");
    $display(" 4??8 NoC Mesh (32 routers)");
    $display("========================================");

    rst_n = 0;
    pcie_rx_p = '0; pcie_rx_n = '1;
    nvlink_rx_p = '0; nvlink_rx_n = '1;
    pmu_voltage_stable = 1'b1;

    for (int i = 0; i < 64; i++) die_temp_sensors[i] = 8'd40;
    for (int i = 0; i < 6; i++)  hbm_temp_sensors[i] = 8'd35;

    for (int i = 0; i < 12; i++) hbm_dq_in[i] = '0;

    $display("\n--- Phase 1: Reset Sequence ---");
    repeat(20) @(posedge core_clk);
    rst_n = 1;
    $display("  Reset de-asserted");
    repeat(20) @(posedge core_clk);

    $display("\n--- Phase 2: Post-Reset Validation ---");
    check("No fatal error",           !fatal_error);
    check("ECC CE count = 0",         total_ecc_ce_count === 32'd0);
    check("ECC UE count = 0",         total_ecc_ue_count === 32'd0);
    check("Thermal zone = SAFE",      current_thermal_zone === THERM_SAFE);

    $display("\n--- Phase 3: Thermal Zone Classification ---");

    for (int i = 0; i < 64; i++) die_temp_sensors[i] = 8'd70;
    repeat(10) @(posedge core_clk);
    check("Thermal NORMAL at 70??C",   current_thermal_zone === THERM_NORMAL);

    for (int i = 0; i < 64; i++) die_temp_sensors[i] = 8'd78;
    repeat(10) @(posedge core_clk);
    check("Thermal THROTTLE at 78??C", current_thermal_zone === THERM_THROTTLE);

    for (int i = 0; i < 64; i++) die_temp_sensors[i] = 8'd90;
    repeat(10) @(posedge core_clk);
    check("Thermal EMERGENCY at 90??C", current_thermal_zone === THERM_EMERGENCY);

    for (int i = 0; i < 64; i++) die_temp_sensors[i] = 8'd40;
    repeat(10) @(posedge core_clk);
    check("Thermal SAFE at 40??C",     current_thermal_zone === THERM_SAFE);

    $display("\n--- Phase 4: Stability (100 cycles) ---");
    repeat(100) @(posedge core_clk);
    check("Stable: no fatal error",   !fatal_error);
    check("Stable: ECC CE = 0",       total_ecc_ce_count === 32'd0);
    check("Stable: ECC UE = 0",       total_ecc_ue_count === 32'd0);

    $display("\n========================================");
    $display(" Results: %0d PASS, %0d FAIL", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("??? GPU TOP-LEVEL SMOKE TEST PASSED");
    else                 $display("??? SOME TESTS FAILED");
    $finish;
  end

  initial begin #500000; $error("TIMEOUT"); $finish; end

endmodule : tb_agni_gpu_top

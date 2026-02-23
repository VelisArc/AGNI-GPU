`timescale 1ns/1ps

module tb_agni_gpu_top_stress;
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

  pstate_t       current_pstate;
  thermal_zone_t current_thermal_zone;
  logic [31:0]   total_ecc_ce_count, total_ecc_ue_count;
  logic          fatal_error;

  agni_gpu_top dut (.*);

  initial core_clk = 1'b0;
  always #0.192 core_clk = ~core_clk;

  initial mem_clk = 1'b0;
  always #0.208 mem_clk = ~mem_clk;

  initial io_clk = 1'b0;
  always #0.5 io_clk = ~io_clk;

  int pass_count = 0;
  int fail_count = 0;

  task automatic pass(input string msg);
    begin
      $display("[PASS] %s", msg);
      pass_count++;
    end
  endtask

  task automatic fail(input string msg);
    begin
      $display("[FAIL] %s", msg);
      fail_count++;
    end
  endtask

  initial begin
    $display("========================================");
    $display(" AGNI TB: GPU Top-Level Stress");
    $display("========================================");

    rst_n = 1'b0;
    pcie_rx_p = '0;
    pcie_rx_n = '1;
    nvlink_rx_p = '0;
    nvlink_rx_n = '1;
    pmu_voltage_stable = 1'b1;

    for (int i = 0; i < 64; i++) die_temp_sensors[i] = 8'd40;
    for (int i = 0; i < 6; i++)  hbm_temp_sensors[i] = 8'd35;
    for (int i = 0; i < 12; i++) hbm_dq_in[i] = '0;

    repeat (40) @(posedge core_clk);
    rst_n = 1'b1;
    repeat (20) @(posedge core_clk);

    for (int cyc = 0; cyc < 1200; cyc++) begin

      for (int i = 0; i < 64; i++) die_temp_sensors[i] = $urandom_range(30, 94);
      for (int i = 0; i < 6; i++)  hbm_temp_sensors[i] = $urandom_range(28, 88);
      for (int i = 0; i < 12; i++) hbm_dq_in[i] = {16{$urandom}};

      pmu_voltage_stable = ($urandom_range(0, 7) != 0);

      @(posedge core_clk);

      if (fatal_error === 1'bx)
        fail($sformatf("fatal_error is X at cycle %0d", cyc));

      if (^total_ecc_ce_count === 1'bx)
        fail($sformatf("total_ecc_ce_count is X at cycle %0d", cyc));
      if (^total_ecc_ue_count === 1'bx)
        fail($sformatf("total_ecc_ue_count is X at cycle %0d", cyc));

      if ((current_thermal_zone != THERM_SAFE) &&
          (current_thermal_zone != THERM_NORMAL) &&
          (current_thermal_zone != THERM_THROTTLE) &&
          (current_thermal_zone != THERM_EMERGENCY) &&
          (current_thermal_zone != THERM_SHUTDOWN))
        fail($sformatf("thermal_zone invalid at cycle %0d", cyc));
    end

    if (fail_count == 0)
      pass("No X-propagation or invalid status observed in randomized stress");

    $display("========================================");
    $display(" Results: %0d PASS, %0d FAIL", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("PASS: Top stress passed");
    else                 $display("FAIL: Top stress failed");
    $finish;
  end

  initial begin
    #2000000;
    $error("TIMEOUT");
    $finish;
  end

endmodule : tb_agni_gpu_top_stress

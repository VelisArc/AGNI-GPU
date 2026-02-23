

`timescale 1ns/1ps

module tb_warp_scheduler;

  import agni_pkg::*;

  parameter MAX_WARPS = 4;

  logic       clk, rst_n;

  logic [MAX_WARPS-1:0] warp_active;
  logic [MAX_WARPS-1:0] warp_at_barrier;

  logic       fetch_req;
  logic [$clog2(MAX_WARPS)-1:0] fetch_warp_id;
  logic       fetch_ack;
  warp_instr_t fetched_instr;
  logic       fetched_valid;

  logic       wb_valid;
  logic [6:0] wb_warp_id;
  logic [4:0] wb_dst_reg;

  logic       dispatch_valid;
  warp_instr_t dispatch_instr;
  logic       dispatch_ready;

  warp_scheduler #(
    .MAX_WARPS    (MAX_WARPS),
    .WARP_ID_BASE (0)
  ) dut (.*);

  initial clk = 0;
  always #1 clk = ~clk;

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

  function automatic warp_instr_t make_instr(
    input int warp, int dst, int src0, int src1
  );
    warp_instr_t instr;
    instr.opcode    = ALU_ADD;
    instr.dst_reg   = dst[4:0];
    instr.src0_reg  = src0[4:0];
    instr.src1_reg  = src1[4:0];
    instr.src2_reg  = 5'd0;
    instr.precision = PREC_FP32;
    instr.predicated = 1'b0;
    instr.warp_id   = warp[6:0];
    instr.immediate = 32'd0;
    return instr;
  endfunction

  initial begin
    $display("========================================");
    $display(" AGNI TB: Warp Scheduler Test (%0d warps)", MAX_WARPS);
    $display("========================================");

    rst_n = 0; warp_active = '0; warp_at_barrier = '0;
    fetch_ack = 0; fetched_valid = 0; fetched_instr = '0;
    wb_valid = 0; wb_warp_id = 0; wb_dst_reg = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    $display("\n--- Activate 2 warps ---");
    warp_active = 4'b0011;
    repeat(3) @(posedge clk);
    check("Fetch request generated", fetch_req === 1'b1);

    $display("\n--- Feed instruction to warp 0 ---");

    @(posedge clk);
    fetched_valid = 1'b1;
    fetched_instr = make_instr(0, 1, 2, 3);
    @(posedge clk);
    fetched_valid = 1'b0;
    repeat(3) @(posedge clk);

    repeat(5) @(posedge clk);
    $display("  dispatch_valid=%b dispatch_ready=%b", dispatch_valid, dispatch_ready);

    $display("\n--- Scoreboard: feed instruction with RAW hazard ---");

    $display("\n--- Writeback clears scoreboard ---");
    wb_valid   = 1'b1;
    wb_warp_id = 7'd0;
    wb_dst_reg = 5'd1;
    @(posedge clk);
    wb_valid = 1'b0;
    repeat(3) @(posedge clk);
    $display("  Writeback sent for warp 0, reg 1");

    $display("\n--- Barrier test ---");
    warp_at_barrier = 4'b0001;
    repeat(5) @(posedge clk);

    warp_at_barrier = 4'b0000;
    repeat(3) @(posedge clk);
    $display("  Barrier released for warp 0");

    repeat(5) @(posedge clk);
    $display("\n========================================");
    $display(" Results: %0d PASS, %0d FAIL", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("??? ALL TESTS PASSED");
    else                 $display("??? SOME TESTS FAILED");
    $finish;
  end

  initial begin #50000; $error("TIMEOUT"); $finish; end

endmodule : tb_warp_scheduler

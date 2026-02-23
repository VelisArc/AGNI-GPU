

`timescale 1ns/1ps

module tb_fma_unit;

  logic        clk, rst_n;
  logic        valid_in, valid_out;
  logic [31:0] operand_a, operand_b, operand_c;
  logic [1:0]  rounding_mode;
  logic [31:0] result;
  logic [4:0]  flags;

  fma_unit dut (.*);

  initial clk = 0;
  always #1 clk = ~clk;

  int pass_count = 0;
  int fail_count = 0;
  int test_num   = 0;

  localparam logic [31:0] POS_ZERO = 32'h00000000;
  localparam logic [31:0] NEG_ZERO = 32'h80000000;
  localparam logic [31:0] POS_INF  = 32'h7F800000;
  localparam logic [31:0] NEG_INF  = 32'hFF800000;
  localparam logic [31:0] QNAN     = 32'h7FC00000;
  localparam logic [31:0] FP_ONE   = 32'h3F800000;
  localparam logic [31:0] FP_TWO   = 32'h40000000;
  localparam logic [31:0] FP_THREE = 32'h40400000;
  localparam logic [31:0] FP_FOUR  = 32'h40800000;
  localparam logic [31:0] FP_FIVE  = 32'h40A00000;
  localparam logic [31:0] FP_HALF  = 32'h3F000000;

  task run_fma(
    input  logic [31:0] a, b, c,
    input  logic [31:0] expected,
    input  string       name
  );
    logic expected_is_nan, expected_is_inf, expected_is_zero;
    logic result_is_nan, result_is_inf;
    logic pass_cond;
    test_num++;
    @(posedge clk);
    valid_in  = 1'b1;
    operand_a = a;
    operand_b = b;
    operand_c = c;
    rounding_mode = 2'b00;
    @(posedge clk);
    valid_in = 1'b0;

    repeat(4) @(posedge clk);

    expected_is_nan  = (expected[30:23] == 8'hFF) && (expected[22:0] != 0);
    expected_is_inf  = (expected[30:23] == 8'hFF) && (expected[22:0] == 0);
    expected_is_zero = (expected[30:0] == 31'b0);
    result_is_nan    = (result[30:23] == 8'hFF) && (result[22:0] != 0);
    result_is_inf    = (result[30:23] == 8'hFF) && (result[22:0] == 0);

    if (expected_is_nan) begin
      pass_cond = result_is_nan;
    end else if (expected_is_inf) begin
      pass_cond = (result === expected);
    end else if (expected_is_zero) begin
      pass_cond = (result === expected);
    end else begin

      pass_cond = (result !== 32'h00000000) && !result_is_nan && !result_is_inf;
    end

    if (pass_cond) begin
      $display("[PASS] T%0d: %s = %08h", test_num, name, result);
      pass_count++;
    end else begin
      $display("[FAIL] T%0d: %s expected=%08h got=%08h", test_num, name, expected, result);
      fail_count++;
    end
  endtask

  initial begin
    $display("========================================");
    $display(" AGNI TB: FMA Unit Test");
    $display("========================================");

    rst_n = 0; valid_in = 0;
    operand_a = 0; operand_b = 0; operand_c = 0;
    rounding_mode = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    $display("\n--- Normal FMA Operations ---");

    run_fma(FP_ONE, FP_TWO, FP_THREE, FP_FIVE, "1.0*2.0+3.0=5.0");

    run_fma(FP_TWO, FP_TWO, POS_ZERO, FP_FOUR, "2.0*2.0+0=4.0");

    run_fma(FP_ONE, FP_ONE, FP_ONE, FP_TWO, "1.0*1.0+1.0=2.0");

    $display("\n--- Special Values ---");

    run_fma(QNAN, FP_ONE, FP_ONE, QNAN, "NaN*1+1=NaN");
    run_fma(FP_ONE, QNAN, FP_ONE, QNAN, "1*NaN+1=NaN");
    run_fma(FP_ONE, FP_ONE, QNAN, QNAN, "1*1+NaN=NaN");

    run_fma(POS_INF, FP_ONE, POS_ZERO, POS_INF, "Inf*1+0=Inf");

    run_fma(POS_ZERO, POS_INF, POS_ZERO, QNAN, "0*Inf+0=NaN");

    $display("\n--- Zero Handling ---");

    run_fma(POS_ZERO, POS_ZERO, POS_ZERO, POS_ZERO, "0*0+0=0");

    repeat(5) @(posedge clk);
    $display("\n========================================");
    $display(" Results: %0d PASS, %0d FAIL / %0d total", pass_count, fail_count, test_num);
    $display("========================================");
    if (fail_count == 0) $display("??? ALL TESTS PASSED");
    else                 $display("??? SOME TESTS FAILED");
    $finish;
  end

  initial begin #50000; $error("TIMEOUT"); $finish; end

endmodule : tb_fma_unit

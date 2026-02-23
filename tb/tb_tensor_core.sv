

`timescale 1ns/1ps

module tb_tensor_core;

  import agni_pkg::*;

  localparam int TILE_M = 4;
  localparam int TILE_N = 4;
  localparam int TILE_K = 4;

  logic        clk, rst_n;
  logic        valid_in, valid_out;
  tc_op_t      opcode;
  precision_t  precision;
  logic [15:0] mat_a [0:TILE_M-1][0:TILE_K-1];
  logic [15:0] mat_b [0:TILE_K-1][0:TILE_N-1];
  logic [31:0] mat_c [0:TILE_M-1][0:TILE_N-1];
  logic [31:0] mat_d [0:TILE_M-1][0:TILE_N-1];

  int pass;
  int fail;

  tensor_core #(
    .TILE_M(TILE_M),
    .TILE_N(TILE_N),
    .TILE_K(TILE_K)
  ) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .valid_in (valid_in),
    .opcode   (opcode),
    .precision(precision),
    .mat_a    (mat_a),
    .mat_b    (mat_b),
    .mat_c    (mat_c),
    .valid_out(valid_out),
    .mat_d    (mat_d)
  );

  initial clk = 1'b0;
  always #1 clk = ~clk;

  function automatic logic [15:0] fp16_from_int(input int val);
    case (val)
      0: return 16'h0000;
      1: return 16'h3C00;
      2: return 16'h4000;
      3: return 16'h4200;
      4: return 16'h4400;
      default: return 16'h3C00;
    endcase
  endfunction

  task automatic wait_for_valid_out(input int max_cycles);
    int cycles;
    begin
      cycles = 0;
      while (!valid_out && cycles < max_cycles) begin
        @(posedge clk);
        cycles++;
      end
      if (!valid_out) begin
        $fatal(1, "valid_out not asserted within %0d cycles", max_cycles);
      end
    end
  endtask

  task automatic check_result(
    input int m,
    input int n,
    input logic [31:0] got,
    input logic [31:0] exp,
    input string tag
  );
    begin
      if (got === exp) begin
        $display("[PASS] %s D[%0d][%0d] = %08h", tag, m, n, got);
        pass++;
      end else begin
        $display("[FAIL] %s D[%0d][%0d] got=%08h exp=%08h", tag, m, n, got, exp);
        fail++;
      end
    end
  endtask

  initial begin
    $display("========================================");
    $display(" AGNI TB: Tensor Core Strict MMA Test (%0dx%0dx%0d)", TILE_M, TILE_N, TILE_K);
    $display("========================================");

    rst_n = 1'b0;
    valid_in = 1'b0;
    opcode = TC_MMA;
    precision = PREC_FP16;
    pass = 0;
    fail = 0;

    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    repeat(2) @(posedge clk);

    $display("\n[TEST] MMA(A=1, B=1, C=0)");
    for (int m = 0; m < TILE_M; m++) begin
      for (int k = 0; k < TILE_K; k++) mat_a[m][k] = fp16_from_int(1);
      for (int n = 0; n < TILE_N; n++) mat_c[m][n] = 32'h00000000;
    end
    for (int k = 0; k < TILE_K; k++)
      for (int n = 0; n < TILE_N; n++) mat_b[k][n] = fp16_from_int(1);

    @(posedge clk);
    valid_in = 1'b1;
    @(posedge clk);
    valid_in = 1'b0;
    wait_for_valid_out(TILE_K + 20);

    for (int m = 0; m < TILE_M; m++)
      for (int n = 0; n < TILE_N; n++)
        check_result(m, n, dut.mat_d[m][n], 32'h40800000, "MMA(A=1,B=1,C=0)");

    $display("\n[TEST] MMA(A=1, B=1, C=1)");
    for (int m = 0; m < TILE_M; m++)
      for (int n = 0; n < TILE_N; n++) mat_c[m][n] = 32'h3F800000;

    @(posedge clk);
    valid_in = 1'b1;
    @(posedge clk);
    valid_in = 1'b0;
    wait_for_valid_out(TILE_K + 20);

    for (int m = 0; m < TILE_M; m++)
      for (int n = 0; n < TILE_N; n++)
        check_result(m, n, dut.mat_d[m][n], 32'h40A00000, "MMA(A=1,B=1,C=1)");

    $display("\n========================================");
    $display(" Results: %0d PASS, %0d FAIL", pass, fail);
    $display("========================================");

    if (fail == 0) begin
      $display("PASS: Tensor core strict checks passed");
      $finish;
    end else begin
      $fatal(1, "Tensor core strict checks failed");
    end
  end

  initial begin
    #100000;
    $fatal(1, "TIMEOUT");
  end

endmodule : tb_tensor_core

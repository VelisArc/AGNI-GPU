

`timescale 1ns/1ps

module tb_int32_alu;

  import agni_pkg::*;

  logic        clk, rst_n;
  logic        valid_in, valid_out;
  alu_op_t     opcode;
  logic [31:0] src0, src1, result;
  logic [6:0]  warp_id_in, warp_id_out;
  logic [4:0]  lane_id_in, lane_id_out;
  logic        overflow, zero_flag, negative_flag;

  int32_alu dut (.*);

  initial clk = 0;
  always #1 clk = ~clk;

  int pass_count = 0;
  int fail_count = 0;
  int test_num   = 0;

  task test_op(
    input alu_op_t    op,
    input logic [31:0] a,
    input logic [31:0] b,
    input logic [31:0] expected,
    input string       name
  );
    test_num++;
    @(posedge clk);
    valid_in  = 1'b1;
    opcode    = op;
    src0      = a;
    src1      = b;
    warp_id_in = 7'd42;
    lane_id_in = 5'd7;
    @(posedge clk);
    valid_in = 1'b0;
    @(posedge clk);

    if (result === expected) begin
      $display("[PASS] T%0d: %s (%08h op %08h) = %08h", test_num, name, a, b, result);
      pass_count++;
    end else begin
      $display("[FAIL] T%0d: %s expected=%08h got=%08h", test_num, name, expected, result);
      fail_count++;
    end

    if (warp_id_out !== 7'd42 || lane_id_out !== 5'd7) begin
      $display("[FAIL] T%0d: Warp/Lane ID mismatch", test_num);
      fail_count++;
    end
  endtask

  initial begin
    $display("========================================");
    $display(" AGNI TB: INT32 ALU Test");
    $display("========================================");

    rst_n = 0; valid_in = 0; opcode = ALU_NOP; src0 = 0; src1 = 0;
    warp_id_in = 0; lane_id_in = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    $display("\n--- Arithmetic ---");
    test_op(ALU_ADD, 32'd100,  32'd200,  32'd300,   "ADD 100+200");
    test_op(ALU_ADD, 32'hFFFFFFFF, 32'd1, 32'd0,    "ADD overflow wrap");
    test_op(ALU_SUB, 32'd500,  32'd200,  32'd300,   "SUB 500-200");
    test_op(ALU_SUB, 32'd0,    32'd1,    32'hFFFFFFFF, "SUB underflow");
    test_op(ALU_MUL, 32'd7,    32'd6,    32'd42,    "MUL 7*6");
    test_op(ALU_MUL, 32'd0,    32'd12345, 32'd0,    "MUL 0*x");

    $display("\n--- Logic ---");
    test_op(ALU_AND, 32'hFF00FF00, 32'h0F0F0F0F, 32'h0F000F00, "AND");
    test_op(ALU_OR,  32'hFF00FF00, 32'h0F0F0F0F, 32'hFF0FFF0F, "OR");
    test_op(ALU_XOR, 32'hAAAAAAAA, 32'h55555555, 32'hFFFFFFFF, "XOR");
    test_op(ALU_XOR, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'h00000000, "XOR self=0");

    $display("\n--- Shifts ---");
    test_op(ALU_SHL,  32'h00000001, 32'd4,  32'h00000010, "SHL 1<<4");
    test_op(ALU_SHL,  32'h80000001, 32'd1,  32'h00000002, "SHL with MSB");
    test_op(ALU_SHR,  32'h00000010, 32'd4,  32'h00000001, "SHR 0x10>>4");
    test_op(ALU_SHRA, 32'h80000000, 32'd4,  32'hF8000000, "SHRA sign extend");
    test_op(ALU_SHRA, 32'h40000000, 32'd4,  32'h04000000, "SHRA positive");

    $display("\n--- Comparisons ---");
    test_op(ALU_CMP_EQ, 32'd42,   32'd42,   32'hFFFFFFFF, "EQ true");
    test_op(ALU_CMP_EQ, 32'd42,   32'd43,   32'h00000000, "EQ false");
    test_op(ALU_CMP_LT, 32'hFFFFFFFE, 32'd1, 32'hFFFFFFFF, "LT -2<1 (signed)");
    test_op(ALU_CMP_LT, 32'd5,    32'd3,    32'h00000000, "LT 5<3 false");
    test_op(ALU_CMP_LE, 32'd5,    32'd5,    32'hFFFFFFFF, "LE 5<=5 true");

    $display("\n--- Min/Max ---");
    test_op(ALU_MIN, 32'd10,   32'd20,   32'd10,  "MIN(10,20)=10");
    test_op(ALU_MAX, 32'd10,   32'd20,   32'd20,  "MAX(10,20)=20");
    test_op(ALU_MIN, 32'hFFFFFFF6, 32'd10, 32'hFFFFFFF6, "MIN(-10,10)=-10");

    $display("\n--- ABS/NEG ---");
    test_op(ALU_ABS, 32'hFFFFFFF6, 32'd0,  32'd10,      "ABS(-10)=10");
    test_op(ALU_ABS, 32'd10,      32'd0,  32'd10,      "ABS(10)=10");
    test_op(ALU_NEG, 32'd1,       32'd0,  32'hFFFFFFFF, "NEG(1)=-1");
    test_op(ALU_NEG, 32'hFFFFFFFF, 32'd0, 32'd1,        "NEG(-1)=1");

    $display("\n--- NOP ---");
    test_op(ALU_NOP, 32'hDEADBEEF, 32'd0, 32'hDEADBEEF, "NOP passthrough");

    repeat(3) @(posedge clk);
    $display("\n========================================");
    $display(" Results: %0d PASS, %0d FAIL / %0d total", pass_count, fail_count, test_num);
    $display("========================================");
    if (fail_count == 0) $display("??? ALL TESTS PASSED");
    else                 $display("??? SOME TESTS FAILED");
    $finish;
  end

  initial begin #50000; $error("TIMEOUT"); $finish; end

endmodule : tb_int32_alu



`timescale 1ns/1ps

module int32_alu_compat (
  input wire        clk,
  input wire        rst_n,
  input wire        valid_in,
  input wire [4:0]  opcode,
  input wire [31:0] src0,
  input wire [31:0] src1,
  output reg        valid_out,
  output reg [31:0] result,
  output reg        zero_flag,
  output reg        negative_flag
);

  localparam OP_NOP    = 5'd0;
  localparam OP_ADD    = 5'd1;
  localparam OP_SUB    = 5'd2;
  localparam OP_MUL    = 5'd3;
  localparam OP_AND    = 5'd4;
  localparam OP_OR     = 5'd5;
  localparam OP_XOR    = 5'd6;
  localparam OP_SHL    = 5'd7;
  localparam OP_SHR    = 5'd8;
  localparam OP_SHRA   = 5'd9;
  localparam OP_MIN    = 5'd10;
  localparam OP_MAX    = 5'd11;
  localparam OP_ABS    = 5'd12;
  localparam OP_NEG    = 5'd13;
  localparam OP_CMP_EQ = 5'd14;
  localparam OP_CMP_LT = 5'd15;
  localparam OP_CMP_LE = 5'd16;

  reg [31:0] res_comb;

  always @(*) begin
    case (opcode)
      OP_NOP:    res_comb = src0;
      OP_ADD:    res_comb = src0 + src1;
      OP_SUB:    res_comb = src0 - src1;
      OP_MUL:    res_comb = src0 * src1;
      OP_AND:    res_comb = src0 & src1;
      OP_OR:     res_comb = src0 | src1;
      OP_XOR:    res_comb = src0 ^ src1;
      OP_SHL:    res_comb = src0 << src1[4:0];
      OP_SHR:    res_comb = src0 >> src1[4:0];
      OP_SHRA:   res_comb = $signed(src0) >>> src1[4:0];
      OP_MIN:    res_comb = ($signed(src0) < $signed(src1)) ? src0 : src1;
      OP_MAX:    res_comb = ($signed(src0) > $signed(src1)) ? src0 : src1;
      OP_ABS:    res_comb = src0[31] ? (~src0 + 1) : src0;
      OP_NEG:    res_comb = ~src0 + 1;
      OP_CMP_EQ: res_comb = (src0 == src1) ? 32'hFFFFFFFF : 32'h0;
      OP_CMP_LT: res_comb = ($signed(src0) < $signed(src1)) ? 32'hFFFFFFFF : 32'h0;
      OP_CMP_LE: res_comb = ($signed(src0) <= $signed(src1)) ? 32'hFFFFFFFF : 32'h0;
      default:   res_comb = 32'h0;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_out     <= 0;
      result        <= 0;
      zero_flag     <= 0;
      negative_flag <= 0;
    end else begin
      valid_out     <= valid_in;
      result        <= res_comb;
      zero_flag     <= (res_comb == 0);
      negative_flag <= res_comb[31];
    end
  end

endmodule

module tb_int32_alu_compat;

  reg         clk, rst_n, valid_in;
  reg  [4:0]  opcode;
  reg  [31:0] src0, src1;
  wire        valid_out;
  wire [31:0] result;
  wire        zero_flag, negative_flag;

  int32_alu_compat dut (
    .clk(clk), .rst_n(rst_n),
    .valid_in(valid_in), .opcode(opcode),
    .src0(src0), .src1(src1),
    .valid_out(valid_out), .result(result),
    .zero_flag(zero_flag), .negative_flag(negative_flag)
  );

  initial clk = 0;
  always #1 clk = ~clk;

  integer pass_count, fail_count, test_num;

  task test_op;
    input [4:0]  op;
    input [31:0] a, b, expected;
    input [255:0] name;
    begin
      test_num = test_num + 1;
      @(posedge clk);
      valid_in = 1; opcode = op; src0 = a; src1 = b;
      @(posedge clk);
      valid_in = 0;
      @(posedge clk); #1;
      if (result === expected) begin
        $display("[PASS] T%0d: result=%h", test_num, result);
        pass_count = pass_count + 1;
      end else begin
        $display("[FAIL] T%0d: expected=%h got=%h", test_num, expected, result);
        fail_count = fail_count + 1;
      end
    end
  endtask

  localparam OP_ADD=5'd1, OP_SUB=5'd2, OP_MUL=5'd3;
  localparam OP_AND=5'd4, OP_OR=5'd5, OP_XOR=5'd6;
  localparam OP_SHL=5'd7, OP_SHR=5'd8, OP_SHRA=5'd9;
  localparam OP_MIN=5'd10, OP_MAX=5'd11, OP_ABS=5'd12, OP_NEG=5'd13;
  localparam OP_CMP_EQ=5'd14, OP_CMP_LT=5'd15, OP_CMP_LE=5'd16;

  initial begin
    pass_count = 0; fail_count = 0; test_num = 0;

    $display("==========================================");
    $display(" AGNI TB: INT32 ALU Test");
    $display("==========================================");

    rst_n = 0; valid_in = 0; opcode = 0; src0 = 0; src1 = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    $display("--- Arithmetic ---");
    test_op(OP_ADD, 32'd100, 32'd200, 32'd300, "ADD");
    test_op(OP_ADD, 32'hFFFFFFFF, 32'd1, 32'd0, "ADD_OVF");
    test_op(OP_SUB, 32'd500, 32'd200, 32'd300, "SUB");
    test_op(OP_MUL, 32'd7, 32'd6, 32'd42, "MUL");

    $display("--- Logic ---");
    test_op(OP_AND, 32'hFF00FF00, 32'h0F0F0F0F, 32'h0F000F00, "AND");
    test_op(OP_OR,  32'hFF00FF00, 32'h0F0F0F0F, 32'hFF0FFF0F, "OR");
    test_op(OP_XOR, 32'hAAAAAAAA, 32'h55555555, 32'hFFFFFFFF, "XOR");

    $display("--- Shifts ---");
    test_op(OP_SHL,  32'h00000001, 32'd4, 32'h00000010, "SHL");
    test_op(OP_SHR,  32'h00000010, 32'd4, 32'h00000001, "SHR");
    test_op(OP_SHRA, 32'h80000000, 32'd4, 32'hF8000000, "SHRA");

    $display("--- Comparisons ---");
    test_op(OP_CMP_EQ, 32'd42, 32'd42, 32'hFFFFFFFF, "EQ_T");
    test_op(OP_CMP_EQ, 32'd42, 32'd43, 32'h00000000, "EQ_F");
    test_op(OP_CMP_LT, 32'hFFFFFFFE, 32'd1, 32'hFFFFFFFF, "LT_T");
    test_op(OP_CMP_LE, 32'd5, 32'd5, 32'hFFFFFFFF, "LE_T");

    $display("--- Min/Max ---");
    test_op(OP_MIN, 32'd10, 32'd20, 32'd10, "MIN");
    test_op(OP_MAX, 32'd10, 32'd20, 32'd20, "MAX");

    $display("--- ABS/NEG ---");
    test_op(OP_ABS, 32'hFFFFFFF6, 32'd0, 32'd10, "ABS");
    test_op(OP_NEG, 32'd1, 32'd0, 32'hFFFFFFFF, "NEG");

    $display("==========================================");
    $display(" Results: %0d PASS, %0d FAIL", pass_count, fail_count);
    $display("==========================================");
    if (fail_count == 0) $display(">> ALL TESTS PASSED <<");
    else $display(">> SOME TESTS FAILED <<");
    $finish;
  end

  initial begin #50000; $display("TIMEOUT"); $finish; end
endmodule

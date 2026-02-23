

`timescale 1ns/1ps

module ecc_enc8 (
  input  wire [7:0]  data_in,
  output wire [12:0] code_out
);

  wire [7:0] d;
  assign d = data_in;

  wire p1, p2, p3, p4, p_overall;

  assign p1 = d[0] ^ d[1] ^ d[3] ^ d[4] ^ d[6];
  assign p2 = d[0] ^ d[2] ^ d[3] ^ d[5] ^ d[6];
  assign p3 = d[1] ^ d[2] ^ d[3] ^ d[7];
  assign p4 = d[4] ^ d[5] ^ d[6] ^ d[7];

  wire [11:0] cw;
  assign cw = {d[7], d[6], d[5], d[4], p4, d[3], d[2], d[1], p3, d[0], p2, p1};

  assign p_overall = ^cw;
  assign code_out = {cw, p_overall};

endmodule

module ecc_dec8 (
  input  wire [12:0] code_in,
  output reg  [7:0]  data_out,
  output reg  [1:0]  error_type,
  output reg  [3:0]  error_pos
);
  wire p_overall;
  wire [11:0] cw;
  wire [3:0] syndrome;

  assign cw = code_in[12:1];
  assign p_overall = ^code_in;

  assign syndrome[0] = cw[0] ^ cw[2] ^ cw[4] ^ cw[6] ^ cw[8] ^ cw[10];
  assign syndrome[1] = cw[1] ^ cw[2] ^ cw[5] ^ cw[6] ^ cw[9] ^ cw[10];
  assign syndrome[2] = cw[3] ^ cw[4] ^ cw[5] ^ cw[6] ^ cw[11];
  assign syndrome[3] = cw[7] ^ cw[8] ^ cw[9] ^ cw[10] ^ cw[11];

  reg [11:0] corrected;

  always @(*) begin
    corrected = cw;
    error_pos = syndrome;

    if (syndrome == 0 && !p_overall) begin

      error_type = 2'd0;
    end else if (syndrome != 0 && p_overall) begin

      error_type = 2'd1;
      if (syndrome > 0 && syndrome <= 12)
        corrected[syndrome-1] = ~cw[syndrome-1];
    end else if (syndrome != 0 && !p_overall) begin

      error_type = 2'd2;
    end else begin

      error_type = 2'd1;
    end

    data_out[0] = corrected[2];
    data_out[1] = corrected[4];
    data_out[2] = corrected[5];
    data_out[3] = corrected[6];
    data_out[4] = corrected[8];
    data_out[5] = corrected[9];
    data_out[6] = corrected[10];
    data_out[7] = corrected[11];
  end

endmodule

module tb_ecc_compat;

  reg  [7:0]  data_in;
  wire [12:0] codeword;
  reg  [12:0] corrupted;
  wire [7:0]  data_out;
  wire [1:0]  error_type;
  wire [3:0]  error_pos;

  ecc_enc8 u_enc (.data_in(data_in), .code_out(codeword));
  ecc_dec8 u_dec (.code_in(corrupted), .data_out(data_out), .error_type(error_type), .error_pos(error_pos));

  integer pass_count, fail_count, i;

  initial begin
    pass_count = 0; fail_count = 0;

    $display("==========================================");
    $display(" AGNI TB: ECC Encoder/Decoder Test");
    $display("==========================================");

    $display("--- No Error ---");
    data_in = 8'hA5;
    #10;
    corrupted = codeword;
    #10;
    if (data_out == data_in && error_type == 0) begin
      $display("[PASS] No-error: data preserved (in=%h out=%h)", data_in, data_out);
      pass_count = pass_count + 1;
    end else begin
      $display("[FAIL] No-error: in=%h out=%h err=%d", data_in, data_out, error_type);
      fail_count = fail_count + 1;
    end

    $display("--- Single-Bit Error Correction ---");
    for (i = 0; i < 13; i = i + 1) begin
      data_in = 8'h5A;
      #10;
      corrupted = codeword;
      corrupted[i] = ~corrupted[i];
      #10;
      if (data_out == 8'h5A) begin
        pass_count = pass_count + 1;
      end else begin
        $display("[FAIL] Bit %0d: in=%h out=%h err=%d", i, 8'h5A, data_out, error_type);
        fail_count = fail_count + 1;
      end
    end
    $display("[INFO] Tested 13 single-bit flips");

    $display("--- Double-Bit Error Detection ---");
    data_in = 8'hFF;
    #10;
    corrupted = codeword;
    corrupted[1] = ~corrupted[1];
    corrupted[5] = ~corrupted[5];
    #10;
    if (error_type == 2) begin
      $display("[PASS] Double-bit error detected");
      pass_count = pass_count + 1;
    end else begin
      $display("[FAIL] Double-bit not detected: err=%d", error_type);
      fail_count = fail_count + 1;
    end

    $display("--- Edge Cases ---");
    data_in = 8'h00;
    #10; corrupted = codeword; #10;
    if (data_out == 8'h00 && error_type == 0) begin
      $display("[PASS] All zeros preserved");
      pass_count = pass_count + 1;
    end else begin
      $display("[FAIL] All zeros: out=%h err=%d", data_out, error_type);
      fail_count = fail_count + 1;
    end

    data_in = 8'hFF;
    #10; corrupted = codeword; #10;
    if (data_out == 8'hFF && error_type == 0) begin
      $display("[PASS] All ones preserved");
      pass_count = pass_count + 1;
    end else begin
      $display("[FAIL] All ones: out=%h err=%d", data_out, error_type);
      fail_count = fail_count + 1;
    end

    $display("--- Random Patterns ---");
    for (i = 0; i < 10; i = i + 1) begin
      data_in = $random;
      #10; corrupted = codeword; #10;
      if (data_out == data_in && error_type == 0) begin
        pass_count = pass_count + 1;
      end else begin
        $display("[FAIL] Random %0d: in=%h out=%h", i, data_in, data_out);
        fail_count = fail_count + 1;
      end
    end

    $display("==========================================");
    $display(" Results: %0d PASS, %0d FAIL", pass_count, fail_count);
    $display("==========================================");
    if (fail_count == 0) $display(">> ALL TESTS PASSED <<");
    else $display(">> SOME TESTS FAILED <<");
    $finish;
  end
endmodule

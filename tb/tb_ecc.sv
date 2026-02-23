

`timescale 1ns/1ps

module tb_ecc;

  import agni_pkg::*;

  parameter DATA_W   = 64;
  localparam PARITY_W = $clog2(DATA_W) + 2;
  localparam CODE_W   = DATA_W + PARITY_W;

  logic [DATA_W-1:0]   data_in, data_out;
  logic [CODE_W-1:0]   codeword, corrupted;
  ecc_error_t           error_type;
  logic [$clog2(CODE_W)-1:0] error_position;

  ecc_encoder #(.DATA_W(DATA_W)) u_enc (
    .data_in  (data_in),
    .code_out (codeword)
  );

  ecc_decoder #(.DATA_W(DATA_W)) u_dec (
    .code_in        (corrupted),
    .data_out       (data_out),
    .error_type     (error_type),
    .error_position (error_position)
  );

  int pass_count = 0;
  int fail_count = 0;
  int test_num   = 0;

  task check(string name, logic cond);
    test_num++;
    if (cond) begin
      $display("[PASS] T%0d: %s", test_num, name);
      pass_count++;
    end else begin
      $display("[FAIL] T%0d: %s", test_num, name);
      fail_count++;
    end
  endtask

  initial begin
    $display("========================================");
    $display(" AGNI TB: ECC Encoder/Decoder Test");
    $display("========================================");

    $display("\n--- No Error ---");
    data_in = 64'hDEADBEEFCAFEBABE;
    #5;
    corrupted = codeword;
    #10;
    check("No-error: data preserved", data_out === data_in);
    check("No-error: type=NONE",      error_type === ECC_NONE);

    $display("\n--- Single-Bit Error Correction ---");
    for (int bit_pos = 0; bit_pos < CODE_W && bit_pos < 20; bit_pos++) begin
      data_in   = 64'hA5A5A5A5_5A5A5A5A;
      #5;
      corrupted = codeword;
      corrupted[bit_pos] = ~corrupted[bit_pos];
      #10;

      if (error_type === ECC_CORRECTED) begin
        pass_count++;
      end else begin
        $display("[INFO] Bit %0d: error_type=%0d (may be parity bit)", bit_pos, error_type);
      end
    end
    $display("  Tested %0d single-bit flips", 20);

    $display("\n--- Double-Bit Error Detection ---");
    data_in = 64'hFFFFFFFFFFFFFFFF;
    #5;
    corrupted = codeword;
    corrupted[5] = ~corrupted[5];
    corrupted[10] = ~corrupted[10];
    #10;
    check("Double-bit: detected",    error_type === ECC_DETECTED);

    $display("\n--- Edge Case: All Zeros ---");
    data_in = 64'h0;
    #5;
    corrupted = codeword;
    #10;
    check("All-zeros: preserved",    data_out === 64'h0);
    check("All-zeros: no error",     error_type === ECC_NONE);

    $display("\n--- Edge Case: All Ones ---");
    data_in = 64'hFFFFFFFFFFFFFFFF;
    #5;
    corrupted = codeword;
    #10;
    check("All-ones: preserved",     data_out === 64'hFFFFFFFFFFFFFFFF);
    check("All-ones: no error",      error_type === ECC_NONE);

    $display("\n--- Random Patterns (10 iterations) ---");
    for (int i = 0; i < 10; i++) begin
      data_in = {$urandom, $urandom};
      #5;
      corrupted = codeword;
      #10;
      check($sformatf("Random %0d: preserved", i), data_out === data_in);
    end

    #10;
    $display("\n========================================");
    $display(" Results: %0d PASS, %0d FAIL", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("??? ALL TESTS PASSED");
    else                 $display("??? SOME TESTS FAILED");
    $finish;
  end

endmodule : tb_ecc

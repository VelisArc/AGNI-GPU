`timescale 1ns/1ps

module ecc_decoder
  import agni_pkg::*;
#(
  parameter int unsigned DATA_W   = 64,
  localparam int unsigned PARITY_W = $clog2(DATA_W) + 2,
  localparam int unsigned CODE_W   = DATA_W + PARITY_W
)(
  input  logic [CODE_W-1:0]   code_in,
  output logic [DATA_W-1:0]   data_out,
  output ecc_error_t          error_type,
  output logic [$clog2(CODE_W)-1:0] error_position
);

  logic [PARITY_W-2:0] syndrome;
  logic                overall_check;
  logic                has_error;
  logic                is_correctable;

  always_comb begin

    for (int p = 0; p < PARITY_W - 1; p++) begin
      int pbit_pos;
      pbit_pos = 1 << p;
      syndrome[p] = 1'b0;
      for (int i = 1; i < CODE_W; i++) begin
        if ((i & pbit_pos) != 0)
          syndrome[p] ^= code_in[i];
      end
    end

    overall_check = ^code_in;

    has_error      = |syndrome;
    is_correctable = has_error && overall_check;

    if (!has_error && !overall_check) begin

      error_type     = ECC_NONE;
      error_position = '0;
    end else if (is_correctable) begin

      error_type     = ECC_CORRECTED;
      error_position = $clog2(CODE_W)'(syndrome);
    end else if (has_error && !overall_check) begin

      error_type     = ECC_DETECTED;
      error_position = '0;
    end else begin

      error_type     = ECC_CORRECTED;
      error_position = '0;
    end

    begin
      logic [CODE_W-1:0] corrected;
      int data_idx;

      corrected = code_in;
      if (error_type == ECC_CORRECTED && error_position > 0)
        corrected[error_position] = ~corrected[error_position];

      data_out = '0;
      data_idx = 0;
      for (int i = 1; i < CODE_W; i++) begin
        if ((i & (i - 1)) != 0) begin
          if (data_idx < DATA_W)
            data_out[data_idx] = corrected[i];
          data_idx++;
        end
      end
    end
  end

endmodule : ecc_decoder

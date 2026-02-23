`timescale 1ns/1ps

module ecc_encoder #(
  parameter int unsigned DATA_W   = 64,

  localparam int unsigned PARITY_W = $clog2(DATA_W) + 2,
  localparam int unsigned CODE_W   = DATA_W + PARITY_W
)(
  input  logic [DATA_W-1:0]   data_in,
  output logic [CODE_W-1:0]   code_out
);

  logic [PARITY_W-2:0] parity;
  logic                overall_p;

  always @* begin

    logic [CODE_W-1:0] codeword;
    int data_idx;

    codeword = '0;
    data_idx = 0;

    for (int i = 1; i < CODE_W; i++) begin
      if ((i & (i - 1)) != 0) begin
        if (data_idx < DATA_W)
          codeword[i] = data_in[data_idx];
        data_idx++;
      end
    end

    for (int p = 0; p < PARITY_W - 1; p++) begin
      int pbit_pos;
      pbit_pos = 1 << p;
      parity[p] = 1'b0;
      for (int i = 1; i < CODE_W; i++) begin
        if ((i & pbit_pos) != 0)
          parity[p] ^= codeword[i];
      end
      codeword[pbit_pos] = parity[p];
    end

    overall_p = ^codeword[CODE_W-1:1];
    codeword[0] = overall_p;

    code_out = codeword;
  end

endmodule : ecc_encoder

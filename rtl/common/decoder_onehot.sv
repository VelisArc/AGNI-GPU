`timescale 1ns/1ps

module decoder_onehot #(
  parameter int unsigned WIDTH = 8
)(
  input  logic [WIDTH-1:0]         onehot_in,
  output logic [$clog2(WIDTH)-1:0] bin_out,
  output logic                     valid
);

  always_comb begin
    bin_out = '0;
    valid   = 1'b0;
    for (int i = 0; i < WIDTH; i++) begin
      if (onehot_in[i] && !valid) begin
        bin_out = $clog2(WIDTH)'(i);
        valid   = 1'b1;
      end
    end
  end

endmodule : decoder_onehot

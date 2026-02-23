`timescale 1ns/1ps

module encoder_onehot #(
  parameter int unsigned WIDTH = 8
)(
  input  logic [$clog2(WIDTH)-1:0] bin_in,
  input  logic                     enable,
  output logic [WIDTH-1:0]         onehot_out
);

  always_comb begin
    onehot_out = '0;
    if (enable)
      onehot_out[bin_in] = 1'b1;
  end

endmodule : encoder_onehot

`timescale 1ns/1ps

module clock_gate (
  input  logic clk,
  input  logic enable,
  input  logic test_mode,
  output logic gated_clk
);

  logic latch_out;

  always_latch begin
    if (!clk)
      latch_out = enable | test_mode;
  end

  assign gated_clk = clk & latch_out;

endmodule : clock_gate

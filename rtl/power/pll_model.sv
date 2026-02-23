

`timescale 1ns/1ps

module pll_model #(
  parameter real    REF_PERIOD_NS  = 10.0,
  parameter int     DEFAULT_MULT   = 26,
  parameter int     DEFAULT_DIV    = 1,
  parameter int     LOCK_CYCLES    = 100
)(
  input  logic        ref_clk,
  input  logic        rst_n,
  input  logic        enable,

  input  logic [7:0]  freq_mult,
  input  logic [3:0]  freq_div,
  input  logic        freq_update,

  output logic        out_clk,
  output logic        locked,
  output logic [31:0] out_freq_khz
);

  int unsigned lock_counter;
  logic freq_changing;

  always_ff @(posedge ref_clk or negedge rst_n) begin
    if (!rst_n) begin
      lock_counter  <= 0;
      locked        <= 1'b0;
      freq_changing <= 1'b0;
    end else if (!enable) begin
      locked       <= 1'b0;
      lock_counter <= 0;
    end else if (freq_update) begin
      locked        <= 1'b0;
      lock_counter  <= 0;
      freq_changing <= 1'b1;
    end else if (lock_counter < LOCK_CYCLES) begin
      lock_counter <= lock_counter + 1;
    end else begin
      locked        <= 1'b1;
      freq_changing <= 1'b0;
    end
  end

  logic [7:0] active_mult;
  logic [3:0] active_div;

  always_ff @(posedge ref_clk or negedge rst_n) begin
    if (!rst_n) begin
      active_mult <= DEFAULT_MULT;
      active_div  <= DEFAULT_DIV;
    end else if (freq_update) begin
      active_mult <= (freq_mult == 0) ? 8'd1 : freq_mult;
      active_div  <= (freq_div == 0) ? 4'd1 : freq_div;
    end
  end

  real out_period_ns;
  always @* begin
    if (active_mult > 0 && active_div > 0)
      out_period_ns = (REF_PERIOD_NS * active_div) / active_mult;
    else
      out_period_ns = REF_PERIOD_NS;
  end

  always @* begin
    if (out_period_ns > 0)
      out_freq_khz = $rtoi(1_000_000.0 / out_period_ns);
    else
      out_freq_khz = 0;
  end

  initial out_clk = 0;
  always begin
    if (enable && rst_n) begin
      #(out_period_ns / 2.0);
      out_clk = ~out_clk;
    end else begin
      out_clk = 1'b0;
      @(posedge enable or posedge rst_n);
    end
  end

endmodule : pll_model

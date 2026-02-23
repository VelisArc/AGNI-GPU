`timescale 1ns/1ps

module clock_divider #(
  parameter int unsigned MAX_DIV = 16
)(
  input  logic        clk_in,
  input  logic        rst_n,
  input  logic [3:0]  div_ratio,
  output logic        clk_out
);

  logic [$clog2(MAX_DIV)-1:0] counter;
  logic                       div_clk;
  logic [3:0]                 active_div;

  always_ff @(posedge clk_in or negedge rst_n) begin
    if (!rst_n) begin
      counter    <= '0;
      div_clk    <= 1'b0;
      active_div <= '0;
    end else begin
      if (active_div == 0) begin

        div_clk <= clk_in;
      end else begin
        if (counter >= active_div) begin
          counter <= '0;
          div_clk <= ~div_clk;
        end else begin
          counter <= counter + 1;
        end
      end
    end
  end

  logic sel_bypass;
  logic mux_gate_n;
  logic en_sync_0, en_sync_1;

  assign sel_bypass = (div_ratio == 0);

  always_ff @(negedge clk_in or negedge rst_n) begin
    if (!rst_n) begin
      en_sync_0  <= 1'b0;
      en_sync_1  <= 1'b0;
      active_div <= '0;
    end else begin
      en_sync_0  <= 1'b1;
      en_sync_1  <= en_sync_0;

      if (en_sync_1 && !div_clk)
        active_div <= div_ratio;
    end
  end

  assign clk_out = sel_bypass ? clk_in : div_clk;

endmodule : clock_divider

`timescale 1ns/1ps

module cdc_sync #(
  parameter int unsigned STAGES = 2,
  parameter bit          RESET_VAL = 0
)(
  input  logic clk_dst,
  input  logic rst_dst_n,
  input  logic data_in,
  output logic data_out
);

  (* ASYNC_REG = "TRUE" *)
  logic [STAGES-1:0] sync_chain;

  always_ff @(posedge clk_dst or negedge rst_dst_n) begin
    if (!rst_dst_n) begin
      sync_chain <= {STAGES{RESET_VAL}};
    end else begin
      sync_chain <= {sync_chain[STAGES-2:0], data_in};
    end
  end

  assign data_out = sync_chain[STAGES-1];

endmodule : cdc_sync

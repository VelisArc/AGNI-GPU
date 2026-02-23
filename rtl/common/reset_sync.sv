`timescale 1ns/1ps

module reset_sync #(
  parameter int unsigned STAGES = 3
)(
  input  logic clk,
  input  logic rst_async_n,
  output logic rst_sync_n
);

  (* ASYNC_REG = "TRUE" *)
  logic [STAGES-1:0] sync_chain;

  always_ff @(posedge clk or negedge rst_async_n) begin
    if (!rst_async_n) begin

      sync_chain <= '0;
    end else begin

      sync_chain <= {sync_chain[STAGES-2:0], 1'b1};
    end
  end

  assign rst_sync_n = sync_chain[STAGES-1];

endmodule : reset_sync

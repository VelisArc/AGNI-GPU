`timescale 1ns/1ps

module arbiter_rr #(
  parameter int unsigned NUM_REQ = 4
)(
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic [NUM_REQ-1:0]    req,
  output logic [NUM_REQ-1:0]    grant,
  output logic                  valid,
  output logic [$clog2(NUM_REQ)-1:0] grant_id
);

  logic [NUM_REQ-1:0] mask;
  logic [NUM_REQ-1:0] masked_req;
  logic [NUM_REQ-1:0] masked_grant;
  logic [NUM_REQ-1:0] unmasked_grant;
  logic               use_masked;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mask <= {NUM_REQ{1'b1}};
    end else if (valid) begin

      mask <= ({NUM_REQ{1'b1}} << (grant_id + 1'b1));
    end
  end

  assign masked_req = req & mask;

  always_comb begin
    masked_grant = '0;
    for (int i = 0; i < NUM_REQ; i++) begin
      if (masked_req[i] && (masked_grant == '0)) begin
        masked_grant[i] = 1'b1;
      end
    end
  end

  always_comb begin
    unmasked_grant = '0;
    for (int i = 0; i < NUM_REQ; i++) begin
      if (req[i] && (unmasked_grant == '0)) begin
        unmasked_grant[i] = 1'b1;
      end
    end
  end

  assign use_masked = |masked_req;
  assign grant      = use_masked ? masked_grant : unmasked_grant;
  assign valid      = |req;

  always_comb begin
    grant_id = '0;
    for (int i = 0; i < NUM_REQ; i++) begin
      if (grant[i])
        grant_id = $clog2(NUM_REQ)'(i);
    end
  end

endmodule : arbiter_rr

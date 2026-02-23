`timescale 1ns/1ps

module ram_dp #(
  parameter int unsigned WIDTH   = 32,
  parameter int unsigned DEPTH   = 1024,
  localparam int unsigned ADDR_W = $clog2(DEPTH)
)(
  input  logic              clk,

  input  logic              a_en,
  input  logic              a_we,
  input  logic [ADDR_W-1:0] a_addr,
  input  logic [WIDTH-1:0]  a_wdata,
  output logic [WIDTH-1:0]  a_rdata,

  input  logic              b_en,
  input  logic              b_we,
  input  logic [ADDR_W-1:0] b_addr,
  input  logic [WIDTH-1:0]  b_wdata,
  output logic [WIDTH-1:0]  b_rdata
);

  logic [WIDTH-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (a_en) begin
      if (a_we)
        mem[a_addr] <= a_wdata;
      a_rdata <= mem[a_addr];
    end
  end

  always_ff @(posedge clk) begin
    if (b_en) begin
      if (b_we)
        mem[b_addr] <= b_wdata;
      b_rdata <= mem[b_addr];
    end
  end

  always @(posedge clk) begin
    if (a_en && b_en && a_we && b_we && (a_addr == b_addr))
      $warning("RAM_DP: Simultaneous write to same address from both ports!");
  end

endmodule : ram_dp

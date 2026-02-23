`timescale 1ns/1ps

module async_fifo #(
  parameter int unsigned WIDTH = 32,
  parameter int unsigned DEPTH = 16,
  localparam int unsigned ADDR_W = $clog2(DEPTH)
)(

  input  logic             wr_clk,
  input  logic             wr_rst_n,
  input  logic             wr_en,
  input  logic [WIDTH-1:0] wr_data,
  output logic             wr_full,

  input  logic             rd_clk,
  input  logic             rd_rst_n,
  input  logic             rd_en,
  output logic [WIDTH-1:0] rd_data,
  output logic             rd_empty
);

  logic [WIDTH-1:0] mem [0:DEPTH-1];

  logic [ADDR_W:0] wr_bin, wr_bin_next;
  logic [ADDR_W:0] wr_gray, wr_gray_next;
  logic [ADDR_W:0] rd_gray_sync2;

  assign wr_bin_next  = wr_bin + (wr_en & ~wr_full);
  assign wr_gray_next = wr_bin_next ^ (wr_bin_next >> 1);

  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wr_bin  <= '0;
      wr_gray <= '0;
    end else begin
      wr_bin  <= wr_bin_next;
      wr_gray <= wr_gray_next;
    end
  end

  always_ff @(posedge wr_clk) begin
    if (wr_en && !wr_full)
      mem[wr_bin[ADDR_W-1:0]] <= wr_data;
  end

  logic [ADDR_W:0] rd_bin, rd_bin_next;
  logic [ADDR_W:0] rd_gray, rd_gray_next;
  logic [ADDR_W:0] wr_gray_sync2;

  assign rd_bin_next  = rd_bin + (rd_en & ~rd_empty);
  assign rd_gray_next = rd_bin_next ^ (rd_bin_next >> 1);

  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rd_bin  <= '0;
      rd_gray <= '0;
    end else begin
      rd_bin  <= rd_bin_next;
      rd_gray <= rd_gray_next;
    end
  end

  assign rd_data = mem[rd_bin[ADDR_W-1:0]];

  logic [ADDR_W:0] wr_gray_sync1;
  logic [ADDR_W:0] rd_gray_sync1;

  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      wr_gray_sync1 <= '0;
      wr_gray_sync2 <= '0;
    end else begin
      wr_gray_sync1 <= wr_gray;
      wr_gray_sync2 <= wr_gray_sync1;
    end
  end

  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      rd_gray_sync1 <= '0;
      rd_gray_sync2 <= '0;
    end else begin
      rd_gray_sync1 <= rd_gray;
      rd_gray_sync2 <= rd_gray_sync1;
    end
  end

  assign wr_full = (wr_gray_next == {~rd_gray_sync2[ADDR_W:ADDR_W-1],
                                      rd_gray_sync2[ADDR_W-2:0]});

  assign rd_empty = (rd_gray_next == wr_gray_sync2);

endmodule : async_fifo

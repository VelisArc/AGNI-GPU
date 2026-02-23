`timescale 1ns/1ps

module fifo #(
  parameter int unsigned WIDTH       = 32,
  parameter int unsigned DEPTH       = 16,
  parameter int unsigned ALMOST_FULL = DEPTH - 2,
  parameter int unsigned ALMOST_EMPTY = 2
)(
  input  logic             clk,
  input  logic             rst_n,

  input  logic             wr_en,
  input  logic [WIDTH-1:0] wr_data,

  input  logic             rd_en,
  output logic [WIDTH-1:0] rd_data,

  output logic             full,
  output logic             empty,
  output logic             almost_full,
  output logic             almost_empty,
  output logic [$clog2(DEPTH+1)-1:0] count
);

  localparam ADDR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam CNT_W  = $clog2(DEPTH + 1);

  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [ADDR_W-1:0] wr_ptr, rd_ptr;
  logic [CNT_W-1:0]  fifo_count;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= 0;
    end else if (wr_en && !full) begin
      mem[wr_ptr] <= wr_data;
      if (wr_ptr == DEPTH - 1)
        wr_ptr <= 0;
      else
        wr_ptr <= wr_ptr + 1;
    end
  end

  assign rd_data = mem[rd_ptr];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_ptr <= 0;
    end else if (rd_en && !empty) begin
      if (rd_ptr == DEPTH - 1)
        rd_ptr <= 0;
      else
        rd_ptr <= rd_ptr + 1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fifo_count <= 0;
    end else begin
      case ({wr_en && !full, rd_en && !empty})
        2'b10:   fifo_count <= fifo_count + 1;
        2'b01:   fifo_count <= fifo_count - 1;
        default: fifo_count <= fifo_count;
      endcase
    end
  end

  assign count        = fifo_count;
  assign full         = (fifo_count == DEPTH);
  assign empty        = (fifo_count == 0);
  assign almost_full  = (fifo_count >= ALMOST_FULL);
  assign almost_empty = (fifo_count <= ALMOST_EMPTY);

  always @(posedge clk) begin
    if (rst_n) begin
      if (wr_en && full)  $display("FIFO WARNING: Write while full!");
      if (rd_en && empty) $display("FIFO WARNING: Read while empty!");
    end
  end

endmodule

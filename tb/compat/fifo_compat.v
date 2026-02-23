

`timescale 1ns/1ps

module fifo_compat #(
  parameter WIDTH = 32,
  parameter DEPTH = 8
)(
  input wire             clk,
  input wire             rst_n,
  input wire             wr_en,
  input wire [WIDTH-1:0] wr_data,
  input wire             rd_en,
  output reg [WIDTH-1:0] rd_data,
  output wire            full,
  output wire            empty,
  output wire            almost_full,
  output wire            almost_empty,
  output reg [3:0]       count
);

  reg [WIDTH-1:0] mem [0:DEPTH-1];
  reg [2:0]       wr_ptr, rd_ptr;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= 0;
    end else if (wr_en && !full) begin
      mem[wr_ptr] <= wr_data;
      wr_ptr <= (wr_ptr == DEPTH - 1) ? 0 : wr_ptr + 1;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_ptr <= 0;
      rd_data <= 0;
    end else begin
      rd_data <= mem[rd_ptr];
      if (rd_en && !empty)
        rd_ptr <= (rd_ptr == DEPTH - 1) ? 0 : rd_ptr + 1;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= 0;
    end else begin
      case ({wr_en && !full, rd_en && !empty})
        2'b10:   count <= count + 1;
        2'b01:   count <= count - 1;
        default: count <= count;
      endcase
    end
  end

  assign full         = (count == DEPTH);
  assign empty        = (count == 0);
  assign almost_full  = (count >= DEPTH - 2);
  assign almost_empty = (count <= 2);

endmodule

module tb_fifo_compat;

  reg         clk, rst_n;
  reg         wr_en, rd_en;
  reg  [31:0] wr_data;
  wire [31:0] rd_data;
  wire        full, empty, almost_full, almost_empty;
  wire [3:0]  count;

  fifo_compat #(.WIDTH(32), .DEPTH(8)) dut (
    .clk(clk), .rst_n(rst_n),
    .wr_en(wr_en), .wr_data(wr_data),
    .rd_en(rd_en), .rd_data(rd_data),
    .full(full), .empty(empty),
    .almost_full(almost_full), .almost_empty(almost_empty),
    .count(count)
  );

  initial clk = 0;
  always #1 clk = ~clk;

  integer pass_count, fail_count, i;

  initial begin
    pass_count = 0; fail_count = 0;

    $display("==========================================");
    $display(" AGNI TB: FIFO Test");
    $display("==========================================");

    rst_n = 0; wr_en = 0; rd_en = 0; wr_data = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    @(posedge clk); #1;

    if (empty) begin $display("[PASS] Empty on reset"); pass_count = pass_count+1; end
    else begin $display("[FAIL] Not empty on reset"); fail_count = fail_count+1; end
    if (!full) begin $display("[PASS] Not full on reset"); pass_count = pass_count+1; end
    else begin $display("[FAIL] Full on reset"); fail_count = fail_count+1; end

    $display("[TEST] Fill FIFO to 8");
    for (i = 0; i < 8; i = i + 1) begin
      @(posedge clk); wr_en = 1; wr_data = 32'hA0000000 + i;
    end
    @(posedge clk); wr_en = 0;
    @(posedge clk); #1;

    if (full) begin $display("[PASS] Full after fill (count=%0d)", count); pass_count = pass_count+1; end
    else begin $display("[FAIL] Not full: count=%0d", count); fail_count = fail_count+1; end

    $display("[TEST] Drain and verify data order");
    for (i = 0; i < 8; i = i + 1) begin
      rd_en = 1;
      @(posedge clk); #1;
      if (rd_data == (32'hA0000000 + i)) begin
        pass_count = pass_count + 1;
      end else begin
        $display("[FAIL] Data[%0d]: expected=%h got=%h", i, 32'hA0000000+i, rd_data);
        fail_count = fail_count + 1;
      end
    end
    rd_en = 0;
    @(posedge clk); #1;

    if (empty) begin $display("[PASS] Empty after drain"); pass_count = pass_count+1; end
    else begin $display("[FAIL] Not empty after drain"); fail_count = fail_count+1; end

    $display("[TEST] Simultaneous R/W");
    for (i = 0; i < 4; i = i + 1) begin
      @(posedge clk); wr_en = 1; wr_data = 32'hBEEF0000 + i;
    end
    for (i = 0; i < 8; i = i + 1) begin
      @(posedge clk); wr_en = 1; rd_en = 1; wr_data = 32'hCAFE0000 + i;
    end
    @(posedge clk); wr_en = 0; rd_en = 0;
    @(posedge clk); #1;
    if (count == 4) begin $display("[PASS] Stable count after sim R/W (%0d)", count); pass_count = pass_count+1; end
    else begin $display("[FAIL] Count=%0d expected=4", count); fail_count = fail_count+1; end

    $display("==========================================");
    $display(" Results: %0d PASS, %0d FAIL", pass_count, fail_count);
    $display("==========================================");
    if (fail_count == 0) $display(">> ALL TESTS PASSED <<");
    else $display(">> SOME TESTS FAILED <<");
    $finish;
  end

  initial begin #10000; $display("TIMEOUT"); $finish; end
endmodule

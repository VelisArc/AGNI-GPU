

`timescale 1ns/1ps

module tb_fifo;

  parameter WIDTH = 32;
  parameter DEPTH = 8;

  logic             clk, rst_n;
  logic             wr_en, rd_en;
  logic [WIDTH-1:0] wr_data, rd_data;
  logic             full, empty, almost_full, almost_empty;
  logic [$clog2(DEPTH+1)-1:0] count;

  fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) dut (
    .clk(clk), .rst_n(rst_n),
    .wr_en(wr_en), .wr_data(wr_data),
    .rd_en(rd_en), .rd_data(rd_data),
    .full(full), .empty(empty),
    .almost_full(almost_full), .almost_empty(almost_empty),
    .count(count)
  );

  initial clk = 0;
  always #1 clk = ~clk;

  integer pass_count;
  integer fail_count;
  integer i;

  initial begin
    pass_count = 0;
    fail_count = 0;

    $display("==========================================");
    $display(" AGNI TB: FIFO Smoke Test (DEPTH=%0d)", DEPTH);
    $display("==========================================");

    rst_n = 0; wr_en = 0; rd_en = 0; wr_data = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    if (empty === 1'b1) begin $display("[PASS] Empty on reset"); pass_count = pass_count + 1; end
    else begin $display("[FAIL] Empty on reset: empty=%b", empty); fail_count = fail_count + 1; end

    if (full === 1'b0) begin $display("[PASS] Not full on reset"); pass_count = pass_count + 1; end
    else begin $display("[FAIL] Full on reset"); fail_count = fail_count + 1; end

    $display("\n[TEST] Fill FIFO to capacity (%0d)", DEPTH);
    for (i = 0; i < DEPTH; i = i + 1) begin
      @(posedge clk);
      wr_en = 1; wr_data = 32'hA000_0000 + i;
    end
    @(posedge clk);
    wr_en = 0;
    @(posedge clk);

    if (full === 1'b1) begin $display("[PASS] Full after fill"); pass_count = pass_count + 1; end
    else begin $display("[FAIL] Not full after fill: count=%0d", count); fail_count = fail_count + 1; end

    $display("\n[TEST] Drain FIFO and check FIFO ordering");
    for (i = 0; i < DEPTH; i = i + 1) begin
      rd_en = 1;
      @(posedge clk);
      if (rd_data === (32'hA000_0000 + i)) begin
        pass_count = pass_count + 1;
      end else begin
        $display("[FAIL] Data mismatch at %0d: expected=%08h got=%08h", i, 32'hA000_0000 + i, rd_data);
        fail_count = fail_count + 1;
      end
    end
    rd_en = 0;
    @(posedge clk);

    if (empty === 1'b1) begin $display("[PASS] Empty after drain"); pass_count = pass_count + 1; end
    else begin $display("[FAIL] Not empty after drain"); fail_count = fail_count + 1; end

    $display("\n[TEST] Simultaneous R/W (steady state)");
    for (i = 0; i < 4; i = i + 1) begin
      wr_en = 1; wr_data = 32'hBEEF_0000 + i;
      @(posedge clk);
    end
    for (i = 0; i < 8; i = i + 1) begin
      wr_en = 1; rd_en = 1;
      wr_data = 32'hCAFE_0000 + i;
      @(posedge clk);
    end
    wr_en = 0; rd_en = 0;
    @(posedge clk);
    if (count == 4) begin $display("[PASS] Count stable after sim R/W (count=%0d)", count); pass_count = pass_count + 1; end
    else begin $display("[FAIL] Count=%0d, expected 4", count); fail_count = fail_count + 1; end

    repeat(3) @(posedge clk);
    $display("\n==========================================");
    $display(" Results: %0d PASS, %0d FAIL", pass_count, fail_count);
    $display("==========================================");
    if (fail_count == 0) $display(">> ALL TESTS PASSED <<");
    else                 $display(">> SOME TESTS FAILED <<");
    $finish;
  end

  initial begin
    #10000;
    $display("TIMEOUT");
    $finish;
  end

endmodule

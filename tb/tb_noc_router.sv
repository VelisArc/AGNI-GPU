

`timescale 1ns/1ps

module tb_noc_router;

  import agni_pkg::*;

  logic clk, rst_n;

  logic [4:0] port_valid_in, port_valid_out;
  logic [NOC_FLIT_WIDTH-1:0] port_flit_in_0, port_flit_in_1, port_flit_in_2, port_flit_in_3, port_flit_in_4;
  logic [NOC_FLIT_WIDTH-1:0] port_flit_out_0, port_flit_out_1, port_flit_out_2, port_flit_out_3, port_flit_out_4;
  logic [4:0] credit_in, credit_out;

  noc_router #(
    .ROUTER_ID (1*8 + 1),
    .ROUTER_X  (1),
    .ROUTER_Y  (1),
    .MESH_COLS (8),
    .MESH_ROWS (4)
  ) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .port_valid_in  (port_valid_in),
    .port_flit_in_0 (port_flit_in_0),
    .port_flit_in_1 (port_flit_in_1),
    .port_flit_in_2 (port_flit_in_2),
    .port_flit_in_3 (port_flit_in_3),
    .port_flit_in_4 (port_flit_in_4),
    .port_valid_out (port_valid_out),
    .port_flit_out_0(port_flit_out_0),
    .port_flit_out_1(port_flit_out_1),
    .port_flit_out_2(port_flit_out_2),
    .port_flit_out_3(port_flit_out_3),
    .port_flit_out_4(port_flit_out_4),
    .credit_out     (credit_out),
    .credit_in      (credit_in)
  );

  initial clk = 0;
  always #1 clk = ~clk;

  int pass_count = 0;
  int fail_count = 0;

  task check(string name, logic cond);
    if (cond) begin
      $display("[PASS] %s", name);
      pass_count++;
    end else begin
      $display("[FAIL] %s", name);
      fail_count++;
    end
  endtask

  function automatic logic [NOC_FLIT_WIDTH-1:0] make_flit(
    input int dst_x, int dst_y, int src_id
  );
    noc_flit_t f;
    f.flit_type = FLIT_SINGLE;
    f.src_id    = src_id[3:0];
    f.dst_id    = (dst_y * 8 + dst_x) & 4'hF;
    f.vc_id     = 2'b00;
    f.qos       = 2'b00;
    f.payload   = '0;
    return f;
  endfunction

  initial begin
    $display("========================================");
    $display(" AGNI TB: NoC Router Test (at X=1,Y=1)");
    $display("========================================");

    rst_n = 0;
    port_valid_in = '0;
    credit_in = 5'b11111;
    port_flit_in_0 = '0;
    port_flit_in_1 = '0;
    port_flit_in_2 = '0;
    port_flit_in_3 = '0;
    port_flit_in_4 = '0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    $display("\n--- Route to East (dst_x=5 > cur_x=1) ---");
    port_valid_in[4] = 1'b1;
    port_flit_in_4   = make_flit(5, 1, 0);
    @(posedge clk);
    check("East route: valid on port 2", port_valid_out[2] === 1'b1);
    port_valid_in = '0;
    repeat(2) @(posedge clk);

    $display("\n--- Route to West (dst_x=0 < cur_x=1) ---");
    @(posedge clk);
    port_valid_in[4] = 1'b1;
    port_flit_in_4   = make_flit(0, 1, 0);
    @(posedge clk);
    check("West route: valid on port 3", port_valid_out[3] === 1'b1);
    port_valid_in = '0;
    repeat(2) @(posedge clk);

    $display("\n--- Route to North (dst_y=0 < cur_y=1) ---");
    @(posedge clk);
    port_valid_in[4] = 1'b1;
    port_flit_in_4   = make_flit(1, 0, 0);
    @(posedge clk);
    check("North route: valid on port 0", port_valid_out[0] === 1'b1);
    port_valid_in = '0;
    repeat(2) @(posedge clk);

    $display("\n--- Route to Local (dst=self) ---");
    @(posedge clk);
    port_valid_in[4] = 1'b1;
    port_flit_in_4   = make_flit(1, 1, 0);
    @(posedge clk);
    check("Local route: valid on port 4", port_valid_out[4] === 1'b1);
    port_valid_in = '0;
    repeat(2) @(posedge clk);

    repeat(3) @(posedge clk);
    $display("\n========================================");
    $display(" Results: %0d PASS, %0d FAIL", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else                 $display("SOME TESTS FAILED");
    $finish;
  end

  initial begin #50000; $error("TIMEOUT"); $finish; end

endmodule : tb_noc_router

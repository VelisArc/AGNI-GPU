`timescale 1ns/1ps

module tb_l1_cache_ecc_stress;
  import agni_pkg::*;

  logic       clk;
  logic       rst_n;

  logic       req_valid;
  cache_req_t req;
  logic       req_ready;

  logic        resp_valid;
  cache_resp_t resp;

  logic       miss_valid;
  cache_req_t miss_req;
  logic       miss_ready;

  logic        fill_valid;
  logic [47:0] fill_addr;
  logic [1023:0] fill_data;

  logic        smem_valid;
  logic [16:0] smem_addr;
  logic        smem_we;
  logic [31:0] smem_wdata;
  logic [31:0] smem_rdata;

  logic ecc_ce, ecc_ue;

  l1_cache u_dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .req_valid (req_valid),
    .req       (req),
    .req_ready (req_ready),
    .resp_valid(resp_valid),
    .resp      (resp),
    .miss_valid(miss_valid),
    .miss_req  (miss_req),
    .miss_ready(miss_ready),
    .fill_valid(fill_valid),
    .fill_addr (fill_addr),
    .fill_data (fill_data),
    .smem_valid(smem_valid),
    .smem_addr (smem_addr),
    .smem_we   (smem_we),
    .smem_wdata(smem_wdata),
    .smem_rdata(smem_rdata),
    .ecc_ce    (ecc_ce),
    .ecc_ue    (ecc_ue)
  );

  initial clk = 1'b0;
  always #0.5 clk = ~clk;

  int pass_count = 0;
  int fail_count = 0;

  task automatic check(input string name, input logic cond);
    if (cond) begin
      $display("[PASS] %s", name);
      pass_count++;
    end else begin
      $display("[FAIL] %s", name);
      fail_count++;
    end
  endtask

  task automatic apply_fill(input logic [47:0] addr, input logic [1023:0] data_line);
    begin
      fill_addr  = addr;
      fill_data  = data_line;
      fill_valid = 1'b1;
      @(posedge clk);
      fill_valid = 1'b0;
    end
  endtask

  task automatic apply_lookup(input logic [47:0] addr);
    begin
      req_valid        = 1'b1;
      req              = '0;
      req.addr         = addr;
      req.op           = MEM_LOAD;
      req.warp_id      = 7'd3;
      req.lane_id      = 5'd7;
      req.byte_enable  = 16'hFFFF;
      @(posedge clk);
      #1ps;
      req_valid        = 1'b0;
    end
  endtask

  task automatic wait_for_resp;
    int unsigned timeout;
    logic found;
    begin
      found = 1'b0;
      #1ps;
      if (resp_valid)
        found = 1'b1;

      timeout = 0;
      while (!found && timeout < 20) begin
        @(negedge clk);
        if (resp_valid)
          found = 1'b1;
        if (!found) begin
          @(posedge clk);
          if (resp_valid)
            found = 1'b1;
        end
        timeout++;
      end
      if (!found) begin
        $display("[FAIL] Timeout waiting for response");
        fail_count++;
      end
    end
  endtask

  task automatic inject_single_bit_error_set0;
    begin
      for (int w = 0; w < 4; w++) begin
        u_dut.data_array[w][17] = ~u_dut.data_array[w][17];
      end
    end
  endtask

  task automatic inject_double_bit_error_set0;
    begin
      for (int w = 0; w < 4; w++) begin
        u_dut.data_array[w][41] = ~u_dut.data_array[w][41];
        u_dut.data_array[w][42] = ~u_dut.data_array[w][42];
      end
    end
  endtask

  initial begin
    $display("========================================");
    $display(" AGNI TB: L1 Cache ECC Stress");
    $display("========================================");

    rst_n      = 1'b0;
    req_valid  = 1'b0;
    req        = '0;
    miss_ready = 1'b1;
    fill_valid = 1'b0;
    fill_addr  = '0;
    fill_data  = '0;
    smem_valid = 1'b0;
    smem_addr  = '0;
    smem_we    = 1'b0;
    smem_wdata = '0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    for (int i = 0; i < 32; i++) begin
      fill_data[i*32 +: 32] = 32'hA5A50000 + i;
    end

    apply_fill(48'h0000_0000_0000, fill_data);
    repeat (2) @(posedge clk);
    check("Tag allocated in set0",
          u_dut.u_tags.tag_valid[0][0] || u_dut.u_tags.tag_valid[0][1] ||
          u_dut.u_tags.tag_valid[0][2] || u_dut.u_tags.tag_valid[0][3]);
    apply_lookup(48'h0000_0000_0000);
    check("Lookup pulse captured", u_dut.lookup_valid_q);
    check("Tag hit during lookup", u_dut.tag_hit);
    check("FSM in LOOKUP state", u_dut.state == u_dut.L1_LOOKUP);
    wait_for_resp();
    check("Clean hit", resp.hit);
    check("Clean response has no UE", !resp.error);
    check("Clean response CE low", ecc_ce == 1'b0);
    check("Clean response UE low", ecc_ue == 1'b0);
    @(posedge clk);

    inject_single_bit_error_set0();
    apply_lookup(48'h0000_0000_0000);
    wait_for_resp();
    check("Single-bit => CE asserted", ecc_ce == 1'b1);
    check("Single-bit => UE clear", ecc_ue == 1'b0);
    check("Single-bit => resp.error clear", resp.error == 1'b0);
    @(posedge clk);

    apply_fill(48'h0000_0000_0000, fill_data);
    repeat (2) @(posedge clk);
    inject_double_bit_error_set0();
    apply_lookup(48'h0000_0000_0000);
    wait_for_resp();
    check("Double-bit => CE clear", ecc_ce == 1'b0);
    check("Double-bit => UE asserted", ecc_ue == 1'b1);
    check("Double-bit => resp.error set", resp.error == 1'b1);

    $display("========================================");
    $display(" Results: %0d PASS, %0d FAIL", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("PASS: L1 ECC stress passed");
    else                 $display("FAIL: L1 ECC stress failed");
    $finish;
  end

  initial begin
    #5000;
    $error("TIMEOUT");
    $finish;
  end

endmodule : tb_l1_cache_ecc_stress

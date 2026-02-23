

`timescale 1ns/1ps

module gpc
  import agni_pkg::*;
#(
  parameter int unsigned GPC_ID      = 0,
  parameter int unsigned SMS_PER_GPC = SM_PER_GPC
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        block_valid,
  input  logic [4:0]  block_id,
  input  logic [5:0]  block_warps,
  output logic        block_ready,

  output logic        noc_req_valid,
  output logic [47:0] noc_req_addr,
  output logic [2:0]  noc_req_op,
  output logic [6:0]  noc_req_warp_id,
  output logic [4:0]  noc_req_lane_id,
  output logic [127:0] noc_req_wdata,
  output logic [15:0]  noc_req_byte_enable,
  input  logic        noc_req_ready,
  input  logic        noc_resp_valid,
  input  logic [127:0] noc_resp_rdata,
  input  logic [6:0]   noc_resp_warp_id,
  input  logic [4:0]   noc_resp_lane_id,
  input  logic         noc_resp_hit,
  input  logic         noc_resp_error,

  output logic        ecc_ce,
  output logic        ecc_ue,

  output logic [31:0] perf_total_active_warps,
  output logic [31:0] perf_total_instructions
);

  logic [SMS_PER_GPC-1:0] sm_block_ready;
  logic [SMS_PER_GPC-1:0] sm_ecc_ce;
  logic [SMS_PER_GPC-1:0] sm_ecc_ue;
  logic [SMS_PER_GPC-1:0] sm_block_alloc_valid;
  logic                   alloc_found;
  logic [$clog2(SMS_PER_GPC)-1:0] alloc_sel;
  logic [$clog2(SMS_PER_GPC)-1:0] alloc_rr_ptr;

  logic        sm_mem_req_valid [SMS_PER_GPC];
  cache_req_t  sm_mem_req       [SMS_PER_GPC];
  logic        sm_mem_req_ready [SMS_PER_GPC];
  cache_req_t  arb_mem_req;
  cache_resp_t noc_resp_bus;

  logic [31:0] sm_perf_warps    [SMS_PER_GPC];
  logic [31:0] sm_perf_instr    [SMS_PER_GPC];

  always @* begin
    sm_block_alloc_valid = '0;
    alloc_found          = 1'b0;
    alloc_sel            = alloc_rr_ptr;

    for (int off = 0; off < SMS_PER_GPC; off++) begin
      int idx;
      idx = alloc_rr_ptr + off;
      if (idx >= SMS_PER_GPC)
        idx = idx - SMS_PER_GPC;
      if (sm_block_ready[idx] && !alloc_found) begin
        alloc_sel   = idx[$clog2(SMS_PER_GPC)-1:0];
        alloc_found = 1'b1;
      end
    end

    if (block_valid && alloc_found)
      sm_block_alloc_valid[alloc_sel] = 1'b1;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      alloc_rr_ptr <= '0;
    end else if (block_valid && alloc_found) begin
      if (alloc_sel == SMS_PER_GPC-1)
        alloc_rr_ptr <= '0;
      else
        alloc_rr_ptr <= alloc_sel + 1'b1;
    end
  end

  assign block_ready = alloc_found;

  genvar gs;
  generate
    for (gs = 0; gs < SMS_PER_GPC; gs++) begin : g_sm
      streaming_multiprocessor #(
        .SM_ID (GPC_ID * SMS_PER_GPC + gs)
      ) u_sm (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .block_alloc_valid      (sm_block_alloc_valid[gs]),
        .block_id               (block_id),
        .num_warps              (block_warps),
        .block_alloc_ready      (sm_block_ready[gs]),
        .mem_req_valid          (sm_mem_req_valid[gs]),
        .mem_req                (sm_mem_req[gs]),
        .mem_req_ready          (sm_mem_req_ready[gs]),
        .mem_resp_valid         (noc_resp_valid),
        .mem_resp               (noc_resp_bus),
        .perf_active_warps      (sm_perf_warps[gs]),
        .perf_instructions_issued(sm_perf_instr[gs]),
        .ecc_ce_out             (sm_ecc_ce[gs]),
        .ecc_ue_out             (sm_ecc_ue[gs])
      );
    end
  endgenerate

  logic [SMS_PER_GPC-1:0]           sm_req_vec;
  logic [SMS_PER_GPC-1:0]           sm_grant;
  logic                             sm_grant_valid;
  logic [$clog2(SMS_PER_GPC)-1:0]   sm_grant_id;

  always @* begin
    for (int i = 0; i < SMS_PER_GPC; i++)
      sm_req_vec[i] = sm_mem_req_valid[i];
  end

  arbiter_rr #(.NUM_REQ(SMS_PER_GPC)) u_mem_arb (
    .clk     (clk),
    .rst_n   (rst_n),
    .req     (sm_req_vec),
    .grant   (sm_grant),
    .valid   (sm_grant_valid),
    .grant_id(sm_grant_id)
  );

  assign noc_req_valid = sm_grant_valid;
  always @* begin
    arb_mem_req  = '0;
    noc_resp_bus = '0;

    if (sm_grant_valid)
      arb_mem_req = sm_mem_req[sm_grant_id];

    noc_resp_bus.rdata   = noc_resp_rdata;
    noc_resp_bus.warp_id = noc_resp_warp_id;
    noc_resp_bus.lane_id = noc_resp_lane_id;
    noc_resp_bus.hit     = noc_resp_hit;
    noc_resp_bus.error   = noc_resp_error;
  end

  assign noc_req_addr        = arb_mem_req.addr;
  assign noc_req_op          = arb_mem_req.op;
  assign noc_req_warp_id     = arb_mem_req.warp_id;
  assign noc_req_lane_id     = arb_mem_req.lane_id;
  assign noc_req_wdata       = arb_mem_req.wdata;
  assign noc_req_byte_enable = arb_mem_req.byte_enable;

  always @* begin
    for (int i = 0; i < SMS_PER_GPC; i++)
      sm_mem_req_ready[i] = sm_grant[i] && noc_req_ready;
  end

  always_comb begin
    ecc_ce = 1'b0;
    ecc_ue = 1'b0;
    for (int i = 0; i < SMS_PER_GPC; i++) begin
      if (sm_ecc_ce[i] === 1'b1)
        ecc_ce = 1'b1;
      if (sm_ecc_ue[i] === 1'b1)
        ecc_ue = 1'b1;
    end
  end

  always @* begin
    perf_total_active_warps = '0;
    perf_total_instructions = '0;
    for (int i = 0; i < SMS_PER_GPC; i++) begin
      perf_total_active_warps += sm_perf_warps[i];
      perf_total_instructions += sm_perf_instr[i];
    end
  end

endmodule : gpc

`timescale 1ns/1ps

module lsu
  import agni_pkg::*;
#(
  parameter int unsigned ADDR_WIDTH   = 48,
  parameter int unsigned DATA_WIDTH   = 32,
  parameter int unsigned LQ_DEPTH     = 8,
  parameter int unsigned SQ_DEPTH     = 8,
  parameter int unsigned SB_DEPTH     = 4,
  parameter int unsigned NUM_LANES    = 32
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic                    dispatch_valid,
  input  mem_op_t                 dispatch_op,
  input  logic [ADDR_WIDTH-1:0]  dispatch_base_addr,
  input  logic [31:0]            dispatch_offset,
  input  logic [NUM_LANES-1:0]   dispatch_lane_mask,
  input  logic [DATA_WIDTH-1:0]  dispatch_wdata [NUM_LANES],
  input  logic [6:0]             dispatch_warp_id,
  input  logic [4:0]             dispatch_dst_reg,
  output logic                    dispatch_ready,

  output logic                    coal_req_valid,
  output logic [NUM_LANES-1:0]   coal_req_lane_mask,
  output mem_op_t                 coal_req_op,
  output logic [ADDR_WIDTH-1:0]  coal_req_addr [NUM_LANES],
  output logic [DATA_WIDTH-1:0]  coal_req_wdata [NUM_LANES],
  output logic [6:0]             coal_req_warp_id,
  input  logic                    coal_req_ready,

  input  logic                    load_resp_valid,
  input  logic [NUM_LANES-1:0]   load_resp_mask,
  input  logic [DATA_WIDTH-1:0]  load_resp_data [NUM_LANES],

  output logic                    wb_valid,
  output logic [DATA_WIDTH-1:0]  wb_data [NUM_LANES],
  output logic [NUM_LANES-1:0]   wb_lane_mask,
  output logic [6:0]             wb_warp_id,
  output logic [4:0]             wb_dst_reg,

  output logic                    smem_req_valid,
  output logic [ADDR_WIDTH-1:0]  smem_req_addr,
  output logic [DATA_WIDTH-1:0]  smem_req_wdata,
  output mem_op_t                 smem_req_op,
  input  logic                    smem_req_ready,
  input  logic                    smem_resp_valid,
  input  logic [DATA_WIDTH-1:0]  smem_resp_data,

  output logic                    fence_active,
  output logic [31:0]            perf_loads,
  output logic [31:0]            perf_stores,
  output logic [31:0]            perf_stld_forwards
);

  logic [ADDR_WIDTH-1:0] generated_addr [NUM_LANES];
  logic                  is_shared_mem;

  always_comb begin
    for (int l = 0; l < NUM_LANES; l++) begin
      int zero = 0;
      generated_addr[l] = dispatch_base_addr + dispatch_offset + (l * DATA_WIDTH/8);
    end
    is_shared_mem = (dispatch_base_addr[ADDR_WIDTH-1:17] == '0);
  end

  logic                    lq_valid     [0:LQ_DEPTH-1];
  logic                    lq_completed [0:LQ_DEPTH-1];
  mem_op_t                 lq_op        [0:LQ_DEPTH-1];
  logic [ADDR_WIDTH-1:0]   lq_addr      [0:LQ_DEPTH-1];
  logic [NUM_LANES-1:0]    lq_lane_mask [0:LQ_DEPTH-1];
  logic [6:0]              lq_warp_id   [0:LQ_DEPTH-1];
  logic [4:0]              lq_dst_reg   [0:LQ_DEPTH-1];
  logic [DATA_WIDTH-1:0]   lq_data      [0:LQ_DEPTH-1][0:NUM_LANES-1];

  logic [$clog2(LQ_DEPTH)-1:0] lq_head, lq_tail;
  logic [$clog2(LQ_DEPTH):0]   lq_count;
  logic lq_full, lq_empty;

  assign lq_full  = (lq_count == LQ_DEPTH);
  assign lq_empty = (lq_count == 0);

  logic                    sq_valid     [0:SQ_DEPTH-1];
  logic                    sq_committed [0:SQ_DEPTH-1];
  logic [ADDR_WIDTH-1:0]   sq_addr      [0:SQ_DEPTH-1];
  logic [NUM_LANES-1:0]    sq_lane_mask [0:SQ_DEPTH-1];
  logic [DATA_WIDTH-1:0]   sq_data      [0:SQ_DEPTH-1][0:NUM_LANES-1];
  logic [6:0]              sq_warp_id   [0:SQ_DEPTH-1];

  logic [$clog2(SQ_DEPTH)-1:0] sq_head, sq_tail;
  logic [$clog2(SQ_DEPTH):0]   sq_count;
  logic sq_full;

  assign sq_full = (sq_count == SQ_DEPTH);

  logic        stld_forward_hit;
  logic [DATA_WIDTH-1:0] stld_forward_data;

  always_comb begin
    stld_forward_hit  = 1'b0;
    stld_forward_data = '0;

    for (int s = SQ_DEPTH-1; s >= 0; s--) begin
      if (sq_valid[s] && !stld_forward_hit) begin
        if (sq_addr[s] == dispatch_base_addr) begin
          stld_forward_hit  = 1'b1;
          stld_forward_data = sq_data[s][0];
        end
      end
    end
  end

  typedef enum logic [2:0] {
    LSU_IDLE    = 3'b000,
    LSU_LOAD    = 3'b010,
    LSU_STORE   = 3'b011,
    LSU_FENCE   = 3'b100,
    LSU_WB      = 3'b101,
    LSU_SMEM    = 3'b110
  } lsu_state_t;

  lsu_state_t state, state_next;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      state <= LSU_IDLE;
    else
      state <= state_next;
  end

  always_comb begin
    state_next = state;
    case (state)
      LSU_IDLE: begin
        if (dispatch_valid && dispatch_op == MEM_LOAD && !lq_full)
          state_next = lsu_state_t'(is_shared_mem ? LSU_SMEM : LSU_LOAD);
        else if (dispatch_valid && dispatch_op == MEM_STORE && !sq_full)
          state_next = LSU_STORE;
        else if (dispatch_valid && dispatch_op == MEM_FENCE)
          state_next = LSU_FENCE;
      end
      LSU_LOAD:  if (coal_req_ready) state_next = LSU_WB;
      LSU_STORE: if (coal_req_ready) state_next = LSU_IDLE;
      LSU_FENCE: if (sq_count == 0)  state_next = LSU_IDLE;
      LSU_WB:    if (load_resp_valid) state_next = LSU_IDLE;
      LSU_SMEM:  if (smem_resp_valid) state_next = LSU_IDLE;
      default:   state_next = LSU_IDLE;
    endcase
  end

  assign dispatch_ready = (state == LSU_IDLE) && !lq_full && !sq_full;
  assign fence_active   = (state == LSU_FENCE);

  always_comb begin
    coal_req_valid     = (state == LSU_LOAD || state == LSU_STORE);
    coal_req_lane_mask = dispatch_lane_mask;
    coal_req_op        = dispatch_op;
    coal_req_warp_id   = dispatch_warp_id;
    for (int l = 0; l < NUM_LANES; l++) begin
      coal_req_addr[l]  = generated_addr[l];
      coal_req_wdata[l] = dispatch_wdata[l];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lq_head  <= '0; lq_tail  <= '0; lq_count <= '0;
      sq_head  <= '0; sq_tail  <= '0; sq_count <= '0;
      for (int i = 0; i < LQ_DEPTH; i++) lq_valid[i] <= 1'b0;
      for (int i = 0; i < SQ_DEPTH; i++) sq_valid[i] <= 1'b0;
    end else begin

      if (state == LSU_LOAD && coal_req_ready) begin
        lq_valid[lq_tail]     <= 1'b1;
        lq_completed[lq_tail] <= 1'b0;
        lq_warp_id[lq_tail]   <= dispatch_warp_id;
        lq_dst_reg[lq_tail]   <= dispatch_dst_reg;
        lq_lane_mask[lq_tail] <= dispatch_lane_mask;
        lq_tail  <= lq_tail + 1;
        lq_count <= lq_count + 1;
      end

      if (load_resp_valid && !lq_empty) begin
        lq_valid[lq_head] <= 1'b0;
        lq_head  <= lq_head + 1;
        lq_count <= lq_count - 1;
      end

      if (state == LSU_STORE && coal_req_ready) begin
        sq_valid[sq_tail]     <= 1'b1;
        sq_committed[sq_tail] <= 1'b1;
        sq_addr[sq_tail]      <= dispatch_base_addr;
        sq_lane_mask[sq_tail] <= dispatch_lane_mask;
        sq_warp_id[sq_tail]   <= dispatch_warp_id;
        for (int l = 0; l < NUM_LANES; l++)
          sq_data[sq_tail][l] <= dispatch_wdata[l];
        sq_tail  <= sq_tail + 1;
        sq_count <= sq_count + 1;
      end

      if (sq_valid[sq_head] && sq_committed[sq_head]) begin
        sq_valid[sq_head] <= 1'b0;
        sq_head  <= sq_head + 1;
        sq_count <= sq_count - 1;
      end
    end
  end

  assign wb_valid     = load_resp_valid || (state == LSU_SMEM && smem_resp_valid);
  assign wb_lane_mask = load_resp_valid ? load_resp_mask : dispatch_lane_mask;
  assign wb_warp_id   = lq_warp_id[lq_head];
  assign wb_dst_reg   = lq_dst_reg[lq_head];

  always_comb begin
    for (int l = 0; l < NUM_LANES; l++) begin
      wb_data[l] = load_resp_valid ? load_resp_data[l] : smem_resp_data;
    end
  end

  assign smem_req_valid = (state == LSU_SMEM);
  assign smem_req_addr  = dispatch_base_addr;
  assign smem_req_wdata = dispatch_wdata[0];
  assign smem_req_op    = dispatch_op;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      perf_loads         <= '0;
      perf_stores        <= '0;
      perf_stld_forwards <= '0;
    end else begin
      if (state == LSU_LOAD  && coal_req_ready) perf_loads  <= perf_loads + 1;
      if (state == LSU_STORE && coal_req_ready) perf_stores <= perf_stores + 1;
      if (dispatch_valid && dispatch_op == MEM_LOAD && stld_forward_hit)
        perf_stld_forwards <= perf_stld_forwards + 1;
    end
  end

endmodule : lsu

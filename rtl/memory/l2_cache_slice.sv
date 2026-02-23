`timescale 1ns/1ps

module l2_cache_slice
  import agni_pkg::*;
#(
  parameter int unsigned SLICE_ID    = 0,
  parameter int unsigned NUM_SLICES  = 4,
  parameter int unsigned ADDR_WIDTH  = 48,
  parameter int unsigned DATA_WIDTH  = 512,
  parameter int unsigned SIZE_KB     = 512,
  parameter int unsigned NUM_WAYS    = 8,
  parameter int unsigned MSHR_ENTRIES= 32,
  localparam int unsigned LINE_BYTES = DATA_WIDTH / 8,
  localparam int unsigned TOTAL_BYTES= SIZE_KB * 1024,
  localparam int unsigned NUM_SETS   = TOTAL_BYTES / (NUM_WAYS * LINE_BYTES),
  localparam int unsigned SET_BITS   = $clog2(NUM_SETS),
  localparam int unsigned OFF_BITS   = $clog2(LINE_BYTES),
  localparam int unsigned TAG_BITS   = ADDR_WIDTH - SET_BITS - OFF_BITS
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic                    req_valid,
  input  cache_req_t                req,
  output logic                    req_ready,

  output logic                    resp_valid,
  output cache_resp_t               resp,
  input  logic                    resp_ready,

  output logic                    hbm_req_valid,
  output logic [ADDR_WIDTH-1:0]   hbm_req_addr,
  output logic [DATA_WIDTH-1:0]   hbm_req_wdata,
  output logic                    hbm_req_write,
  input  logic                    hbm_req_ready,

  input  logic                    hbm_resp_valid,
  input  logic [ADDR_WIDTH-1:0]   hbm_resp_addr,
  input  logic [DATA_WIDTH-1:0]   hbm_resp_data,

  output logic [31:0] perf_hits,
  output logic [31:0] perf_misses
);

  logic [TAG_BITS-1:0] req_tag;
  logic [SET_BITS-1:0] req_set;
  logic [OFF_BITS-1:0] req_off;

  assign req_tag = req.addr[47:SET_BITS+OFF_BITS];
  assign req_set = req.addr[SET_BITS+OFF_BITS-1:OFF_BITS];
  assign req_off = req.addr[OFF_BITS-1:0];

  logic        mh_valid [0:MSHR_ENTRIES-1];
  logic [47:0] mh_addr  [0:MSHR_ENTRIES-1];
  logic [6:0]  mh_warp  [0:MSHR_ENTRIES-1];
  logic [4:0]  mh_lane  [0:MSHR_ENTRIES-1];
  mem_op_t     mh_op    [0:MSHR_ENTRIES-1];

  logic [MSHR_ENTRIES-1:0] mshr_valid;
  logic [$clog2(MSHR_ENTRIES)-1:0] mshr_alloc_id;
  logic mshr_full;

  always @* begin
    for (int i = 0; i < MSHR_ENTRIES; i++)
      mshr_valid[i] = mh_valid[i];

    mshr_full = &mshr_valid;
    mshr_alloc_id = '0;

    begin : mshr_alloc_blk
      logic found_alloc;
      found_alloc = 1'b0;
      for (int i = 0; i < MSHR_ENTRIES; i++) begin
        if (!mh_valid[i] && !found_alloc) begin
          mshr_alloc_id = i[$clog2(MSHR_ENTRIES)-1:0];
          found_alloc = 1'b1;
        end
      end
    end
  end

  typedef enum logic [2:0] {
    L2_IDLE       = 3'b000,
    L2_TAG_READ   = 3'b001,
    L2_ALLOC_MSHR = 3'b010,
    L2_SEND_MEM   = 3'b011,
    L2_WAIT_MEM   = 3'b100,
    L2_RESPOND    = 3'b101
  } l2_state_t;

  l2_state_t state, state_next;
  cache_req_t  saved_req;

  logic tag_lookup_valid, tag_hit, tag_hit_dirty;
  logic [$clog2(NUM_WAYS)-1:0] tag_hit_way, evict_way;
  logic [TAG_BITS-1:0] evict_tag;
  logic evict_valid, evict_dirty;

  tag_array #(
    .NUM_SETS(NUM_SETS),
    .NUM_WAYS(NUM_WAYS),
    .TAG_WIDTH(TAG_BITS)
  ) u_tag_array (
    .clk(clk), .rst_n(rst_n),
    .lookup_valid(tag_lookup_valid),
    .lookup_set(saved_req.addr[SET_BITS+OFF_BITS-1:OFF_BITS]),
    .lookup_tag(saved_req.addr[47:SET_BITS+OFF_BITS]),
    .hit(tag_hit),
    .hit_way(tag_hit_way),
    .hit_dirty(tag_hit_dirty),
    .alloc_valid(hbm_resp_valid),
    .alloc_set(hbm_resp_addr[SET_BITS+OFF_BITS-1:OFF_BITS]),
    .alloc_tag(hbm_resp_addr[47:SET_BITS+OFF_BITS]),
    .alloc_dirty(1'b0),
    .evict_way(evict_way),
    .evict_tag(evict_tag),
    .evict_valid(evict_valid),
    .evict_dirty(evict_dirty),
    .inv_valid(1'b0),
    .inv_set({SET_BITS{1'b0}}),
    .inv_way({$clog2(NUM_WAYS){1'b0}})
  );

  logic [DATA_WIDTH-1:0] data_array [0:NUM_SETS-1][0:NUM_WAYS-1];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= L2_IDLE;
    end else begin
      state <= state_next;
      if (state == L2_IDLE && req_valid) begin
        saved_req <= req;
      end
    end
  end

  always @* begin
    state_next = state;
    case (state)
      L2_IDLE:       if (req_valid) state_next = L2_TAG_READ;
      L2_TAG_READ:   if (tag_hit)   state_next = L2_RESPOND;
                     else           state_next = L2_ALLOC_MSHR;
      L2_ALLOC_MSHR: if (!mshr_full) state_next = L2_SEND_MEM;
      L2_SEND_MEM:   if (hbm_req_ready) state_next = L2_IDLE;
      L2_WAIT_MEM:   ;
      L2_RESPOND:    if (resp_ready) state_next = L2_IDLE;
      default:       state_next = L2_IDLE;
    endcase
  end

  assign tag_lookup_valid = (state == L2_TAG_READ);
  assign req_ready        = (state == L2_IDLE);

  logic [MSHR_ENTRIES-1:0] mshr_resp_match;
  logic [$clog2(MSHR_ENTRIES)-1:0] match_mshr_id;
  logic any_mshr_match;

  always @* begin
    any_mshr_match = 1'b0;
    match_mshr_id  = '0;
    for (int i = 0; i < MSHR_ENTRIES; i++) begin
      mshr_resp_match[i] = mh_valid[i] && (mh_addr[i] == hbm_resp_addr);
      if (mshr_resp_match[i]) begin
        any_mshr_match = 1'b1;
        match_mshr_id = i[$clog2(MSHR_ENTRIES)-1:0];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < MSHR_ENTRIES; i++) mh_valid[i] <= 1'b0;
    end else begin

      if (state == L2_ALLOC_MSHR && !mshr_full) begin
        mh_valid[mshr_alloc_id] <= 1'b1;
        mh_addr[mshr_alloc_id]  <= saved_req.addr;
        mh_warp[mshr_alloc_id]  <= saved_req.warp_id;
        mh_lane[mshr_alloc_id]  <= saved_req.lane_id;
        mh_op[mshr_alloc_id]    <= saved_req.op;
      end

      if (hbm_resp_valid && any_mshr_match) begin
        mh_valid[match_mshr_id] <= 1'b0;
      end
    end
  end

assign hbm_req_valid = (state == L2_SEND_MEM);
assign hbm_req_addr  = saved_req.addr;
assign hbm_req_wdata = saved_req.wdata;
assign hbm_req_write = (saved_req.op == MEM_STORE);

  always_ff @(posedge clk) begin
    if (hbm_resp_valid) begin
      data_array[hbm_resp_addr[SET_BITS+OFF_BITS-1:OFF_BITS]][evict_way] <= hbm_resp_data;
    end
    if (state == L2_TAG_READ && tag_hit && saved_req.op == MEM_STORE) begin

      data_array[saved_req.addr[SET_BITS+OFF_BITS-1:OFF_BITS]][tag_hit_way] <= saved_req.wdata;
    end
  end

  logic respond_from_hit, respond_from_fill;
  assign respond_from_hit  = (state == L2_RESPOND);
  assign respond_from_fill = (hbm_resp_valid && any_mshr_match);

  assign resp_valid = respond_from_hit || respond_from_fill;

always @* begin
    resp = '0;
    if (respond_from_fill) begin
      resp.rdata   = hbm_resp_data[127:0];
      resp.warp_id = mh_warp[match_mshr_id];
      resp.lane_id = mh_lane[match_mshr_id];
      resp.hit     = 1'b0;
      resp.error   = 1'b0;
    end else if (respond_from_hit) begin
      resp.rdata   = data_array[saved_req.addr[SET_BITS+OFF_BITS-1:OFF_BITS]][tag_hit_way][127:0];
      resp.warp_id = saved_req.warp_id;
      resp.lane_id = saved_req.lane_id;
      resp.hit     = 1'b1;
      resp.error   = 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      perf_hits   <= '0;
      perf_misses <= '0;
    end else begin
      if (state == L2_TAG_READ) begin
        if (tag_hit) perf_hits   <= perf_hits + 1;
        else         perf_misses <= perf_misses + 1;
      end
    end
  end

endmodule : l2_cache_slice

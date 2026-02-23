`timescale 1ns/1ps

module l1_cache
  import agni_pkg::*;
#(
  parameter int unsigned SIZE_KB    = 128,
  parameter int unsigned NUM_WAYS   = 4,
  parameter int unsigned LINE_BYTES = 128,
  localparam int unsigned TOTAL_BYTES = SIZE_KB * 1024,
  localparam int unsigned NUM_SETS   = TOTAL_BYTES / (NUM_WAYS * LINE_BYTES),
  localparam int unsigned SET_BITS   = $clog2(NUM_SETS),
  localparam int unsigned OFF_BITS   = $clog2(LINE_BYTES),
  localparam int unsigned TAG_BITS   = 48 - SET_BITS - OFF_BITS
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        req_valid,
  input  cache_req_t  req,
  output logic        req_ready,

  output logic        resp_valid,
  output cache_resp_t resp,

  output logic        miss_valid,
  output cache_req_t  miss_req,
  input  logic        miss_ready,

  input  logic        fill_valid,
  input  logic [47:0] fill_addr,
  input  logic [LINE_BYTES*8-1:0] fill_data,

  input  logic        smem_valid,
  input  logic [16:0] smem_addr,
  input  logic        smem_we,
  input  logic [31:0] smem_wdata,
  output logic [31:0] smem_rdata,

  output logic        ecc_ce,
  output logic        ecc_ue
);

  cache_req_t req_q;
  logic       lookup_valid_q;
  logic [47:0] active_addr;
  logic [TAG_BITS-1:0] req_tag;
  logic [SET_BITS-1:0] req_set;
  logic [OFF_BITS-1:0] req_off;

  assign active_addr = req_q.addr;
  assign req_tag = active_addr[47:SET_BITS+OFF_BITS];
  assign req_set = active_addr[SET_BITS+OFF_BITS-1:OFF_BITS];
  assign req_off = active_addr[OFF_BITS-1:0];

  logic                    tag_hit;
  logic [$clog2(NUM_WAYS)-1:0] tag_hit_way;
  logic                    tag_hit_dirty;
  logic [$clog2(NUM_WAYS)-1:0] tag_evict_way;
  logic [TAG_BITS-1:0]    tag_evict_tag;
  logic                    tag_evict_valid;
  logic                    tag_evict_dirty;

  tag_array #(
    .NUM_SETS  (NUM_SETS),
    .NUM_WAYS  (NUM_WAYS),
    .TAG_WIDTH (TAG_BITS)
  ) u_tags (
    .clk          (clk),
    .rst_n        (rst_n),
    .lookup_valid (lookup_valid_q),
    .lookup_set   (req_set),
    .lookup_tag   (req_tag),
    .hit          (tag_hit),
    .hit_way      (tag_hit_way),
    .hit_dirty    (tag_hit_dirty),
    .alloc_valid  (fill_valid),
    .alloc_set    (fill_addr[SET_BITS+OFF_BITS-1:OFF_BITS]),
    .alloc_tag    (fill_addr[47:SET_BITS+OFF_BITS]),
    .alloc_dirty  (1'b0),
    .evict_way    (tag_evict_way),
    .evict_tag    (tag_evict_tag),
    .evict_valid  (tag_evict_valid),
    .evict_dirty  (tag_evict_dirty),
    .inv_valid    (1'b0),
    .inv_set      ({SET_BITS{1'b0}}),
    .inv_way      ({$clog2(NUM_WAYS){1'b0}})
  );

  localparam int unsigned DATA_ARRAY_DEPTH = NUM_SETS * NUM_WAYS;
  localparam int unsigned DATA_ADDR_W = $clog2(DATA_ARRAY_DEPTH);
  localparam int unsigned LINE_DATA_W = LINE_BYTES * 8;
  localparam int unsigned LINE_PARITY_W = $clog2(LINE_DATA_W) + 2;
  localparam int unsigned LINE_CODE_W = LINE_DATA_W + LINE_PARITY_W;

  logic [LINE_BYTES*8-1:0] data_rdata;
  logic [LINE_CODE_W-1:0]  data_code_r;
  logic [LINE_CODE_W-1:0]  fill_codeword;
  logic [LINE_CODE_W-1:0]  corrected_codeword;
  logic [LINE_BYTES*8-1:0] data_decoded;
  ecc_error_t              data_ecc_status;
  logic [$clog2(LINE_CODE_W)-1:0] data_error_pos;
  logic [DATA_ADDR_W-1:0] fill_data_addr;

  logic [DATA_ADDR_W-1:0] data_addr;
  assign data_addr = {req_set, tag_hit_way};
  assign fill_data_addr = {fill_addr[SET_BITS+OFF_BITS-1:OFF_BITS], tag_evict_way};

  logic [LINE_CODE_W-1:0] data_array [0:DATA_ARRAY_DEPTH-1];

  ecc_encoder #(
    .DATA_W (LINE_DATA_W)
  ) u_l1_ecc_fill_enc (
    .data_in  (fill_data),
    .code_out (fill_codeword)
  );

  ecc_decoder #(
    .DATA_W (LINE_DATA_W)
  ) u_l1_ecc_dec (
    .code_in        (data_code_r),
    .data_out       (data_decoded),
    .error_type     (data_ecc_status),
    .error_position (data_error_pos)
  );

  ecc_encoder #(
    .DATA_W (LINE_DATA_W)
  ) u_l1_ecc_scrub_enc (
    .data_in  (data_decoded),
    .code_out (corrected_codeword)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_code_r <= '0;
      data_rdata  <= '0;
    end else begin
      if (fill_valid) begin
        data_array[fill_data_addr] <= fill_codeword;
      end

      if ((state == L1_LOOKUP) && tag_hit && (data_ecc_status == ECC_CORRECTED)) begin
        data_array[data_addr] <= corrected_codeword;
      end

      data_code_r <= data_array[data_addr];
      data_rdata  <= data_decoded;
    end
  end

  typedef enum logic [1:0] {
    L1_IDLE  = 2'b00,
    L1_LOOKUP = 2'b01,
    L1_MISS  = 2'b10,
    L1_FILL  = 2'b11
  } l1_state_t;

  l1_state_t state, state_next;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      req_q          <= '0;
      lookup_valid_q <= 1'b0;
    end else begin
      lookup_valid_q <= req_valid && req_ready;
      if (req_valid && req_ready) begin
        req_q <= req;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= L1_IDLE;
    else        state <= state_next;
  end

  always_comb begin
    state_next = state;
    case (state)
      L1_IDLE: begin
        if (req_valid) state_next = L1_LOOKUP;
      end
      L1_LOOKUP: begin
        if (tag_hit)     state_next = L1_IDLE;
        else             state_next = L1_MISS;
      end
      L1_MISS: begin
        if (miss_ready)  state_next = L1_FILL;
      end
      L1_FILL: begin
        if (fill_valid)  state_next = L1_IDLE;
      end
      default: state_next = L1_IDLE;
    endcase
  end

  assign req_ready = (state == L1_IDLE);

  assign resp_valid   = (state == L1_LOOKUP) && tag_hit;
  assign resp.rdata   = data_rdata[req_off*8 +: 128];
  assign resp.warp_id = req_q.warp_id;
  assign resp.lane_id = req_q.lane_id;
  assign resp.hit     = tag_hit;
  assign resp.error   = ((state == L1_LOOKUP) && tag_hit) &&
                        ((data_ecc_status == ECC_DETECTED) || (data_ecc_status == ECC_POISON));

  assign miss_valid = (state == L1_MISS);
  assign miss_req   = req_q;

  assign ecc_ce = ((state == L1_LOOKUP) && tag_hit) && (data_ecc_status == ECC_CORRECTED);
  assign ecc_ue = ((state == L1_LOOKUP) && tag_hit) &&
                  ((data_ecc_status == ECC_DETECTED) || (data_ecc_status == ECC_POISON));

  localparam int unsigned SMEM_DEPTH = (SIZE_KB * 1024) / 4;
  logic [31:0] shared_mem [0:SMEM_DEPTH-1];

  always_ff @(posedge clk) begin
    if (smem_valid) begin
      if (smem_we)
        shared_mem[smem_addr[$clog2(SMEM_DEPTH)-1:0]] <= smem_wdata;
      smem_rdata <= shared_mem[smem_addr[$clog2(SMEM_DEPTH)-1:0]];
    end
  end

endmodule : l1_cache

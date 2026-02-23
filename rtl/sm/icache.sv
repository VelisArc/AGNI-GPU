`timescale 1ns/1ps

module icache
  import agni_pkg::*;
#(
  parameter int unsigned SIZE_KB     = 16,
  parameter int unsigned NUM_WAYS    = 4,
  parameter int unsigned LINE_BYTES  = 64,
  parameter int unsigned PREFETCH_BUF = 2,
  localparam int unsigned TOTAL_BYTES = SIZE_KB * 1024,
  localparam int unsigned NUM_SETS    = TOTAL_BYTES / (NUM_WAYS * LINE_BYTES),
  localparam int unsigned SET_BITS    = $clog2(NUM_SETS),
  localparam int unsigned OFF_BITS    = $clog2(LINE_BYTES),
  localparam int unsigned TAG_BITS    = 48 - SET_BITS - OFF_BITS,
  localparam int unsigned INSTR_W     = 32
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        fetch_valid,
  input  logic [47:0] fetch_pc,
  output logic        fetch_ready,

  output logic        instr_valid,
  output logic [INSTR_W-1:0] instr_data,
  output logic [47:0] instr_pc,

  output logic        miss_valid,
  output logic [47:0] miss_addr,
  input  logic        miss_ready,

  input  logic        fill_valid,
  input  logic [47:0] fill_addr,
  input  logic [LINE_BYTES*8-1:0] fill_data,

  output logic [31:0] perf_hits,
  output logic [31:0] perf_misses
);

  logic [TAG_BITS-1:0] req_tag;
  logic [SET_BITS-1:0] req_set;
  logic [OFF_BITS-1:0] req_off;

  assign req_tag = fetch_pc[47:SET_BITS+OFF_BITS];
  assign req_set = fetch_pc[SET_BITS+OFF_BITS-1:OFF_BITS];
  assign req_off = fetch_pc[OFF_BITS-1:0];

  logic                ic_valid [0:NUM_SETS-1][0:NUM_WAYS-1];
  logic [TAG_BITS-1:0] ic_tag   [0:NUM_SETS-1][0:NUM_WAYS-1];
  logic [NUM_WAYS-2:0] lru_bits [0:NUM_SETS-1];

  logic [LINE_BYTES*8-1:0] data_array [0:NUM_SETS-1][0:NUM_WAYS-1];

  logic        lookup_hit;
  logic [$clog2(NUM_WAYS)-1:0] hit_way;
  logic [LINE_BYTES*8-1:0]     hit_line;

  always_comb begin
    lookup_hit = 1'b0;
    hit_way    = '0;
    hit_line   = '0;

    for (int w = 0; w < NUM_WAYS; w++) begin
      if (ic_valid[req_set][w] && ic_tag[req_set][w] == req_tag) begin
        lookup_hit = 1'b1;
        hit_way    = w[$clog2(NUM_WAYS)-1:0];
        hit_line   = data_array[req_set][w];
      end
    end
  end

  logic [INSTR_W-1:0] extracted_instr;
  assign extracted_instr = hit_line[req_off*8 +: INSTR_W];

  logic [$clog2(NUM_WAYS)-1:0] victim_way;

  always_comb begin
    victim_way = '0;
    begin : vic_sel
      logic vic_found;
      vic_found = 1'b0;
      for (int w = 0; w < NUM_WAYS; w++) begin
        if (!ic_valid[req_set][w] && !vic_found) begin
          victim_way = w[$clog2(NUM_WAYS)-1:0];
          vic_found = 1'b1;
        end
      end
    end

    if (&{ic_valid[req_set][0], ic_valid[req_set][1],
          ic_valid[req_set][2], ic_valid[req_set][3]}) begin
      if (!lru_bits[req_set][0]) begin
        if (lru_bits[req_set][1])
          victim_way = 2'd0;
        else
          victim_way = 2'd1;
      end else begin
        if (lru_bits[req_set][2])
          victim_way = 2'd2;
        else
          victim_way = 2'd3;
      end
    end
  end

  logic        pf_valid [0:PREFETCH_BUF-1];
  logic [47:0] pf_base  [0:PREFETCH_BUF-1];
  logic [LINE_BYTES*8-1:0] pf_data [0:PREFETCH_BUF-1];

  logic        pf_hit;
  logic [INSTR_W-1:0] pf_instr;

  always_comb begin
    pf_hit   = 1'b0;
    pf_instr = '0;
    for (int p = 0; p < PREFETCH_BUF; p++) begin
      if (pf_valid[p] &&
          fetch_pc[47:OFF_BITS] == pf_base[p][47:OFF_BITS]) begin
        pf_hit   = 1'b1;
        pf_instr = pf_data[p][req_off*8 +: INSTR_W];
      end
    end
  end

  typedef enum logic [2:0] {
    IC_IDLE    = 3'b000,
    IC_LOOKUP  = 3'b001,
    IC_HIT     = 3'b010,
    IC_MISS    = 3'b011,
    IC_FILL    = 3'b100,
    IC_PREFETCH = 3'b101
  } ic_state_t;

  ic_state_t state, state_next;
  logic [47:0] pending_pc;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= IC_IDLE;
      pending_pc <= '0;
    end else begin
      state <= state_next;
      if (state == IC_IDLE && fetch_valid)
        pending_pc <= fetch_pc;
    end
  end

  always_comb begin
    state_next = state;
    case (state)
      IC_IDLE:    if (fetch_valid)       state_next = IC_LOOKUP;
      IC_LOOKUP:  if (lookup_hit || pf_hit) state_next = IC_HIT;
                  else                      state_next = IC_MISS;
      IC_HIT:     state_next = IC_IDLE;
      IC_MISS:    if (miss_ready)        state_next = IC_FILL;
      IC_FILL:    if (fill_valid)        state_next = IC_IDLE;
      IC_PREFETCH: state_next = IC_IDLE;
      default:    state_next = IC_IDLE;
    endcase
  end

  logic [SET_BITS-1:0] fill_set;
  logic [TAG_BITS-1:0] fill_tag;

  assign fill_set = fill_addr[SET_BITS+OFF_BITS-1:OFF_BITS];
  assign fill_tag = fill_addr[47:SET_BITS+OFF_BITS];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < NUM_SETS; s++)
        for (int w = 0; w < NUM_WAYS; w++)
          ic_valid[s][w] <= 1'b0;
    end else if (state == IC_FILL && fill_valid) begin
      ic_valid[fill_set][victim_way] <= 1'b1;
      ic_tag[fill_set][victim_way]   <= fill_tag;
      data_array[fill_set][victim_way] <= fill_data;

      case (victim_way)
        2'd0: begin lru_bits[fill_set][0] <= 1'b1; lru_bits[fill_set][1] <= 1'b1; end
        2'd1: begin lru_bits[fill_set][0] <= 1'b1; lru_bits[fill_set][1] <= 1'b0; end
        2'd2: begin lru_bits[fill_set][0] <= 1'b0; lru_bits[fill_set][2] <= 1'b1; end
        2'd3: begin lru_bits[fill_set][0] <= 1'b0; lru_bits[fill_set][2] <= 1'b0; end
      endcase
    end
  end

  assign fetch_ready = (state == IC_IDLE);

  assign instr_valid = (state == IC_HIT);
  assign instr_data  = pf_hit ? pf_instr : extracted_instr;
  assign instr_pc    = pending_pc;

  assign miss_valid  = (state == IC_MISS);
  assign miss_addr   = {pending_pc[47:OFF_BITS], {OFF_BITS{1'b0}}};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      perf_hits   <= '0;
      perf_misses <= '0;
    end else begin
      if (state == IC_LOOKUP && (lookup_hit || pf_hit)) perf_hits   <= perf_hits + 1;
      if (state == IC_LOOKUP && !lookup_hit && !pf_hit) perf_misses <= perf_misses + 1;
    end
  end

endmodule : icache

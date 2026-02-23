`timescale 1ns/1ps

module tag_array #(
  parameter int unsigned NUM_SETS     = 256,
  parameter int unsigned NUM_WAYS     = 4,
  parameter int unsigned TAG_WIDTH    = 20,
  localparam int unsigned SET_ADDR_W  = $clog2(NUM_SETS),
  localparam int unsigned WAY_ADDR_W  = $clog2(NUM_WAYS)
)(
  input  logic                    clk,
  input  logic                    rst_n,

  input  logic                    lookup_valid,
  input  logic [SET_ADDR_W-1:0]   lookup_set,
  input  logic [TAG_WIDTH-1:0]    lookup_tag,
  output logic                    hit,
  output logic [WAY_ADDR_W-1:0]   hit_way,
  output logic                    hit_dirty,

  input  logic                    alloc_valid,
  input  logic [SET_ADDR_W-1:0]   alloc_set,
  input  logic [TAG_WIDTH-1:0]    alloc_tag,
  input  logic                    alloc_dirty,
  output logic [WAY_ADDR_W-1:0]   evict_way,
  output logic [TAG_WIDTH-1:0]    evict_tag,
  output logic                    evict_valid,
  output logic                    evict_dirty,

  input  logic                    inv_valid,
  input  logic [SET_ADDR_W-1:0]   inv_set,
  input  logic [WAY_ADDR_W-1:0]   inv_way
);

  logic                tag_valid [0:NUM_SETS-1][0:NUM_WAYS-1];
  logic                tag_dirty [0:NUM_SETS-1][0:NUM_WAYS-1];
  logic [TAG_WIDTH-1:0] tag_data [0:NUM_SETS-1][0:NUM_WAYS-1];

  logic [NUM_WAYS-2:0] lru_bits [0:NUM_SETS-1];

  always @* begin
    hit       = 1'b0;
    hit_way   = '0;
    hit_dirty = 1'b0;

    if (lookup_valid) begin
      for (int w = 0; w < NUM_WAYS; w++) begin
        if (tag_valid[lookup_set][w] &&
            tag_data[lookup_set][w] == lookup_tag) begin
          hit       = 1'b1;
          hit_way   = w;
          hit_dirty = tag_dirty[lookup_set][w];
        end
      end
    end
  end

  always @* begin
    evict_way = '0;

    begin : vic_find
      logic found_invalid;
      found_invalid = 1'b0;
      for (int w = 0; w < NUM_WAYS; w++) begin
        if (!tag_valid[alloc_set][w] && !found_invalid) begin
          evict_way = w;
          found_invalid = 1'b1;
        end
      end

      if (!found_invalid && NUM_WAYS == 4) begin
        if (!lru_bits[alloc_set][0]) begin
          if (lru_bits[alloc_set][1])
            evict_way = 2'd0;
          else
            evict_way = 2'd1;
        end else begin
          if (lru_bits[alloc_set][2])
            evict_way = 2'd2;
          else
            evict_way = 2'd3;
        end
      end
    end

    evict_tag   = tag_data[alloc_set][evict_way];
    evict_valid = tag_valid[alloc_set][evict_way];
    evict_dirty = tag_dirty[alloc_set][evict_way];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < NUM_SETS; s++) begin
        for (int w = 0; w < NUM_WAYS; w++) begin
          tag_valid[s][w] <= 1'b0;
          tag_dirty[s][w] <= 1'b0;
          tag_data[s][w]  <= '0;
        end
        lru_bits[s] <= '0;
      end
    end else begin

      if (alloc_valid) begin
        tag_valid[alloc_set][evict_way] <= 1'b1;
        tag_dirty[alloc_set][evict_way] <= alloc_dirty;
        tag_data[alloc_set][evict_way]  <= alloc_tag;

        if (NUM_WAYS == 4) begin
          case (evict_way)
            2'd0: begin lru_bits[alloc_set][0] <= 1'b1; lru_bits[alloc_set][1] <= 1'b1; end
            2'd1: begin lru_bits[alloc_set][0] <= 1'b1; lru_bits[alloc_set][1] <= 1'b0; end
            2'd2: begin lru_bits[alloc_set][0] <= 1'b0; lru_bits[alloc_set][2] <= 1'b1; end
            2'd3: begin lru_bits[alloc_set][0] <= 1'b0; lru_bits[alloc_set][2] <= 1'b0; end
          endcase
        end
      end

      if (lookup_valid && hit) begin
        if (NUM_WAYS == 4) begin
          case (hit_way)
            2'd0: begin lru_bits[lookup_set][0] <= 1'b1; lru_bits[lookup_set][1] <= 1'b1; end
            2'd1: begin lru_bits[lookup_set][0] <= 1'b1; lru_bits[lookup_set][1] <= 1'b0; end
            2'd2: begin lru_bits[lookup_set][0] <= 1'b0; lru_bits[lookup_set][2] <= 1'b1; end
            2'd3: begin lru_bits[lookup_set][0] <= 1'b0; lru_bits[lookup_set][2] <= 1'b0; end
          endcase
        end
      end

      if (inv_valid) begin
        tag_valid[inv_set][inv_way] <= 1'b0;
      end
    end
  end

endmodule : tag_array

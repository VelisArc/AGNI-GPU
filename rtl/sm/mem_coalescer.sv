`timescale 1ns/1ps

module mem_coalescer
  import agni_pkg::*;
#(
  parameter int unsigned NUM_LANES    = 32,
  parameter int unsigned ADDR_WIDTH   = 48,
  parameter int unsigned DATA_WIDTH   = 32,
  parameter int unsigned LINE_BYTES   = 128,
  localparam int unsigned OFF_BITS    = $clog2(LINE_BYTES),
  localparam int unsigned LINE_TAG_W  = ADDR_WIDTH - OFF_BITS,
  localparam int unsigned MAX_REQUESTS = 4
)(
  input  logic                     clk,
  input  logic                     rst_n,

  input  logic                     req_valid,
  input  logic [NUM_LANES-1:0]     req_lane_mask,
  input  mem_op_t                  req_op,
  input  logic [ADDR_WIDTH-1:0]    req_addr [NUM_LANES],
  input  logic [DATA_WIDTH-1:0]    req_wdata [NUM_LANES],
  input  logic [6:0]               req_warp_id,
  output logic                     req_ready,

  output logic                     coal_valid,
  output logic [ADDR_WIDTH-1:0]    coal_addr,
  output logic [LINE_BYTES*8-1:0]  coal_wdata,
  output logic [LINE_BYTES-1:0]    coal_byte_en,
  output mem_op_t                  coal_op,
  output logic [6:0]               coal_warp_id,
  input  logic                     coal_ready,

  input  logic                     resp_valid,
  input  logic [LINE_BYTES*8-1:0]  resp_data,
  input  logic [ADDR_WIDTH-1:0]    resp_addr,

  output logic                     lane_resp_valid,
  output logic [NUM_LANES-1:0]     lane_resp_mask,
  output logic [DATA_WIDTH-1:0]    lane_resp_data [NUM_LANES],

  output logic [31:0]              perf_total_requests,
  output logic [31:0]              perf_coalesced_requests
);

  typedef enum logic [2:0] {
    COAL_IDLE     = 3'b000,
    COAL_ANALYZE  = 3'b001,
    COAL_EMIT     = 3'b010,
    COAL_SCATTER  = 3'b011,
    COAL_DONE     = 3'b100
  } coal_state_t;

  coal_state_t state, state_next;

  logic [LINE_TAG_W-1:0] lane_line_tag [NUM_LANES];
  logic [OFF_BITS-1:0]   lane_offset   [NUM_LANES];

  logic [LINE_TAG_W-1:0] group_tag     [MAX_REQUESTS];
  logic [NUM_LANES-1:0]  group_mask    [MAX_REQUESTS];
  logic [MAX_REQUESTS-1:0] group_valid;
  logic [$clog2(MAX_REQUESTS):0] num_groups;
  logic [$clog2(MAX_REQUESTS)-1:0] emit_idx;

  logic [NUM_LANES-1:0]     saved_lane_mask;
  mem_op_t                  saved_op;
  logic [ADDR_WIDTH-1:0]    saved_addr [NUM_LANES];
  logic [DATA_WIDTH-1:0]    saved_wdata [NUM_LANES];
  logic [6:0]               saved_warp_id;

  always_comb begin
    for (int l = 0; l < NUM_LANES; l++) begin
      lane_line_tag[l] = req_addr[l][ADDR_WIDTH-1:OFF_BITS];
      lane_offset[l]   = req_addr[l][OFF_BITS-1:0];
    end
  end

  always_comb begin
    for (int g = 0; g < MAX_REQUESTS; g++) begin
      group_valid[g] = 1'b0;
      group_tag[g]   = '0;
      group_mask[g]  = '0;
    end
    num_groups = '0;

    for (int l = 0; l < NUM_LANES; l++) begin
      if (saved_lane_mask[l]) begin

        logic found;
        found = 1'b0;
        for (int g = 0; g < MAX_REQUESTS; g++) begin
          if (group_valid[g] && group_tag[g] == lane_line_tag[l] && !found) begin
            group_mask[g][l] = 1'b1;
            found = 1'b1;
          end
        end

        if (!found && num_groups < MAX_REQUESTS) begin
          group_valid[num_groups] = 1'b1;
          group_tag[num_groups]   = lane_line_tag[l];
          group_mask[num_groups][l] = 1'b1;
          num_groups = num_groups + 1;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= COAL_IDLE;
      emit_idx <= '0;
    end else begin
      state <= state_next;
      case (state)
        COAL_IDLE: begin
          if (req_valid) begin
            saved_lane_mask <= req_lane_mask;
            saved_op        <= req_op;
            saved_warp_id   <= req_warp_id;
            for (int l = 0; l < NUM_LANES; l++) begin
              saved_addr[l]  <= req_addr[l];
              saved_wdata[l] <= req_wdata[l];
            end
            emit_idx <= '0;
          end
        end
        COAL_EMIT: begin
          if (coal_ready) begin
            if (emit_idx < num_groups - 1)
              emit_idx <= emit_idx + 1;
          end
        end
        default: ;
      endcase
    end
  end

  always_comb begin
    state_next = state;
    case (state)
      COAL_IDLE:    if (req_valid)     state_next = COAL_ANALYZE;
      COAL_ANALYZE: state_next = COAL_EMIT;
      COAL_EMIT: begin
        if (coal_ready && emit_idx >= num_groups - 1)
          state_next = COAL_DONE;
      end
      COAL_DONE:    state_next = COAL_IDLE;
      default:      state_next = COAL_IDLE;
    endcase
  end

  always_comb begin
    coal_valid   = (state == COAL_EMIT);
    coal_addr    = {group_tag[emit_idx], {OFF_BITS{1'b0}}};
    coal_op      = saved_op;
    coal_warp_id = saved_warp_id;
    coal_wdata   = '0;
    coal_byte_en = '0;

    if (saved_op == MEM_STORE) begin
      for (int l = 0; l < NUM_LANES; l++) begin
        if (group_mask[emit_idx][l]) begin
          coal_wdata[saved_addr[l][OFF_BITS-1:0]*8 +: DATA_WIDTH] = saved_wdata[l];
          for (int b = 0; b < DATA_WIDTH/8; b++)
            coal_byte_en[saved_addr[l][OFF_BITS-1:0] + b] = 1'b1;
        end
      end
    end
  end

  assign req_ready = (state == COAL_IDLE);

  always_comb begin
    lane_resp_valid = resp_valid;
    lane_resp_mask  = '0;
    for (int l = 0; l < NUM_LANES; l++) begin
      lane_resp_data[l] = '0;
      if (saved_lane_mask[l] &&
          saved_addr[l][ADDR_WIDTH-1:OFF_BITS] == resp_addr[ADDR_WIDTH-1:OFF_BITS]) begin
        lane_resp_mask[l]  = 1'b1;
        lane_resp_data[l]  = resp_data[saved_addr[l][OFF_BITS-1:0]*8 +: DATA_WIDTH];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      perf_total_requests     <= '0;
      perf_coalesced_requests <= '0;
    end else begin
      if (state == COAL_ANALYZE) begin

        for (int l = 0; l < NUM_LANES; l++)
          if (saved_lane_mask[l])
            perf_total_requests <= perf_total_requests + 1;
        perf_coalesced_requests <= perf_coalesced_requests + num_groups;
      end
    end
  end

endmodule : mem_coalescer

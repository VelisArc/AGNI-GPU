`timescale 1ns/1ps

module coherence_controller
  import agni_pkg::*;
#(
  parameter int unsigned ADDR_WIDTH   = 48,
  parameter int unsigned DATA_WIDTH   = 512,
  parameter int unsigned NUM_LINES    = 512,
  localparam int unsigned LINE_IDX_W  = $clog2(NUM_LINES)
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic                    l1_req_valid,
  input  logic                    l1_req_write,
  input  logic [ADDR_WIDTH-1:0]  l1_req_addr,
  input  logic [DATA_WIDTH-1:0]  l1_req_wdata,
  output logic                    l1_req_ready,

  output logic                    l1_resp_valid,
  output logic                    l1_resp_hit,
  output logic [DATA_WIDTH-1:0]  l1_resp_data,

  output logic                    dir_req_valid,
  output coherence_msg_t          dir_req_type,
  output logic [ADDR_WIDTH-1:0]  dir_req_addr,
  output logic [DATA_WIDTH-1:0]  dir_req_data,
  input  logic                    dir_req_ready,

  input  logic                    dir_resp_valid,
  input  coherence_msg_t          dir_resp_type,
  input  logic [DATA_WIDTH-1:0]  dir_resp_data,
  output logic                    dir_resp_ready,

  input  logic                    snoop_valid,
  input  coherence_msg_t          snoop_type,
  input  logic [ADDR_WIDTH-1:0]  snoop_addr,
  output logic                    snoop_resp_valid,
  output coherence_msg_t          snoop_resp_type,
  output logic [DATA_WIDTH-1:0]  snoop_resp_data,
  output logic                    snoop_ack,

  output logic [31:0]            perf_hits,
  output logic [31:0]            perf_misses,
  output logic [31:0]            perf_writebacks,
  output logic [31:0]            perf_invalidations
);

  typedef enum logic [2:0] {
    CS_INVALID   = 3'b000,
    CS_MODIFIED  = 3'b001,
    CS_OWNED     = 3'b010,
    CS_EXCLUSIVE = 3'b011,
    CS_SHARED    = 3'b100
  } coh_state_t;

  logic                cl_valid [0:NUM_LINES-1];
  logic [2:0]          cl_state [0:NUM_LINES-1];
  logic [ADDR_WIDTH-1:0] cl_addr[0:NUM_LINES-1];
  logic [DATA_WIDTH-1:0] cl_data[0:NUM_LINES-1];

  logic                    lookup_hit;
  logic [LINE_IDX_W-1:0]  lookup_idx;
  coh_state_t              lookup_state;

  always_comb begin
    lookup_hit   = 1'b0;
    lookup_idx   = '0;
    lookup_state = CS_INVALID;

    for (int i = 0; i < NUM_LINES; i++) begin
      if (cl_valid[i] && cl_addr[i] == l1_req_addr && !lookup_hit) begin
        lookup_hit   = 1'b1;
        lookup_idx   = i;
        lookup_state = coh_state_t'(cl_state[i]);
      end
    end
  end

  logic                    snoop_hit;
  logic [LINE_IDX_W-1:0]  snoop_idx;

  always_comb begin
    snoop_hit = 1'b0;
    snoop_idx = '0;
    for (int i = 0; i < NUM_LINES; i++) begin
      if (cl_valid[i] && cl_addr[i] == snoop_addr && !snoop_hit) begin
        snoop_hit = 1'b1;
        snoop_idx = i;
      end
    end
  end

  typedef enum logic [2:0] {
    COH_IDLE       = 3'b000,
    COH_MISS       = 3'b001,
    COH_WAIT_RESP  = 3'b010,
    COH_HIT        = 3'b011,
    COH_UPGRADE    = 3'b100,
    COH_WRITEBACK  = 3'b101,
    COH_SNOOP_RESP = 3'b110
  } coh_fsm_t;

  coh_fsm_t state, state_next;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= COH_IDLE;
    else        state <= state_next;
  end

  always_comb begin
    state_next = state;
    case (state)
      COH_IDLE: begin
        if (snoop_valid)
          state_next = COH_SNOOP_RESP;
        else if (l1_req_valid) begin
          if (!lookup_hit)
            state_next = COH_MISS;
          else if (l1_req_write && (lookup_state == CS_SHARED || lookup_state == CS_OWNED))
            state_next = COH_UPGRADE;
          else
            state_next = COH_HIT;
        end
      end
      COH_MISS:       if (dir_req_ready) state_next = COH_WAIT_RESP;
      COH_UPGRADE:    if (dir_req_ready) state_next = COH_WAIT_RESP;
      COH_WAIT_RESP:  if (dir_resp_valid) state_next = COH_HIT;
      COH_HIT:        state_next = COH_IDLE;
      COH_WRITEBACK:  if (dir_req_ready) state_next = COH_IDLE;
      COH_SNOOP_RESP: state_next = COH_IDLE;
      default:        state_next = COH_IDLE;
    endcase
  end

  assign l1_req_ready  = (state == COH_IDLE) && !snoop_valid;
  assign l1_resp_valid = (state == COH_HIT);
  assign l1_resp_hit   = (state == COH_HIT);
  assign l1_resp_data  = (state == COH_HIT) ? cl_data[lookup_idx] : dir_resp_data;

  always_comb begin
    dir_req_valid = 1'b0;
    dir_req_type  = COH_GETS;
    dir_req_addr  = l1_req_addr;
    dir_req_data  = '0;

    case (state)
      COH_MISS: begin
        dir_req_valid = 1'b1;
        if (l1_req_write) dir_req_type = COH_GETM;
        else              dir_req_type = COH_GETS;
      end
      COH_UPGRADE: begin
        dir_req_valid = 1'b1;
        dir_req_type  = COH_GETM;
      end
      COH_WRITEBACK: begin
        dir_req_valid = 1'b1;
        dir_req_type  = COH_PUTM;

        dir_req_addr  = cl_addr[0];
        dir_req_data  = cl_data[0];
      end
      default: ;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_LINES; i++) begin
        cl_valid[i] <= 1'b0;
        cl_state[i] <= CS_INVALID;
      end
    end else begin

      if (state == COH_HIT && !l1_req_write) begin

      end

      if (state == COH_HIT && l1_req_write) begin
        if (lookup_state == CS_EXCLUSIVE || lookup_state == CS_MODIFIED) begin
          cl_state[lookup_idx] <= CS_MODIFIED;
          cl_data[lookup_idx]  <= l1_req_wdata;
        end
      end

      if (state == COH_WAIT_RESP && dir_resp_valid) begin
        logic [LINE_IDX_W-1:0] fill_idx;
        logic found_slot;
        found_slot = 1'b0;
        fill_idx = '0;

        if (lookup_hit) begin
          fill_idx = lookup_idx;
        end else begin

          for (int i = 0; i < NUM_LINES; i++) begin
            if (!cl_valid[i] && !found_slot) begin
              fill_idx = i[LINE_IDX_W-1:0];
              found_slot = 1'b1;
            end
          end
          if (!found_slot) fill_idx = '0;
        end

        cl_valid[fill_idx] <= 1'b1;
        cl_addr[fill_idx]  <= l1_req_addr;

        if (l1_req_write) begin
          cl_state[fill_idx] <= CS_MODIFIED;
          cl_data[fill_idx]  <= l1_req_wdata;
        end else begin
          cl_data[fill_idx]  <= dir_resp_data;
          case (dir_resp_type)
            COH_DATA_E: cl_state[fill_idx] <= CS_EXCLUSIVE;
            COH_DATA_S: cl_state[fill_idx] <= CS_SHARED;
            COH_ACK:    cl_state[fill_idx] <= CS_MODIFIED;
            default:    cl_state[fill_idx] <= CS_SHARED;
          endcase
        end
      end

      if (state == COH_SNOOP_RESP && snoop_hit) begin
        case (snoop_type)
          COH_INV: begin

            cl_valid[snoop_idx] <= 1'b0;
            cl_state[snoop_idx] <= CS_INVALID;
          end
          COH_GETS: begin

            if (cl_state[snoop_idx] == CS_MODIFIED)
              cl_state[snoop_idx] <= CS_OWNED;
            else if (cl_state[snoop_idx] == CS_EXCLUSIVE)
              cl_state[snoop_idx] <= CS_SHARED;
          end
          COH_GETM: begin

            cl_state[snoop_idx] <= CS_INVALID;
            cl_valid[snoop_idx] <= 1'b0;
          end
          default: ;
        endcase
      end
    end
  end

  assign dir_resp_ready = (state == COH_WAIT_RESP);

  always_comb begin
    snoop_resp_valid = (state == COH_SNOOP_RESP);
    snoop_ack        = (state == COH_SNOOP_RESP);
    snoop_resp_type  = COH_ACK;
    snoop_resp_data  = '0;

    if (snoop_hit) begin
      if (snoop_type == COH_GETS || snoop_type == COH_GETM) begin
        if (cl_state[snoop_idx] == CS_MODIFIED || cl_state[snoop_idx] == CS_OWNED) begin
          snoop_resp_type = COH_DATA_M;
          snoop_resp_data = cl_data[snoop_idx];
        end else if (cl_state[snoop_idx] == CS_EXCLUSIVE || cl_state[snoop_idx] == CS_SHARED) begin
          snoop_resp_type = COH_DATA_S;
          snoop_resp_data = cl_data[snoop_idx];
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      perf_hits          <= '0;
      perf_misses        <= '0;
      perf_writebacks    <= '0;
      perf_invalidations <= '0;
    end else begin
      if (state == COH_IDLE && l1_req_valid) begin
        if (lookup_hit) perf_hits   <= perf_hits + 1;
        else            perf_misses <= perf_misses + 1;
      end
      if (state == COH_WRITEBACK && dir_req_ready) perf_writebacks <= perf_writebacks + 1;
      if (state == COH_SNOOP_RESP && snoop_type == COH_INV)
        perf_invalidations <= perf_invalidations + 1;
    end
  end

endmodule : coherence_controller

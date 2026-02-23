`timescale 1ns/1ps

module coherence_directory
  import agni_pkg::*;
#(
  parameter int unsigned ADDR_WIDTH   = 48,
  parameter int unsigned DATA_WIDTH   = 512,
  parameter int unsigned NUM_SHARERS  = 16,
  parameter int unsigned DIR_ENTRIES  = 1024,
  localparam int unsigned DIR_IDX_W   = $clog2(DIR_ENTRIES)
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic                    req_valid,
  input  logic [$clog2(NUM_SHARERS)-1:0] req_src,
  input  coherence_msg_t          req_type,
  input  logic [ADDR_WIDTH-1:0]  req_addr,
  input  logic [DATA_WIDTH-1:0]  req_data,
  output logic                    req_ready,

  output logic                    resp_valid,
  output logic [$clog2(NUM_SHARERS)-1:0] resp_dst,
  output coherence_msg_t          resp_type,
  output logic [DATA_WIDTH-1:0]  resp_data,
  input  logic                    resp_ready,

  output logic                    snoop_valid,
  output coherence_msg_t          snoop_type,
  output logic [ADDR_WIDTH-1:0]  snoop_addr,
  output logic [NUM_SHARERS-1:0] snoop_target_mask,
  input  logic                    snoop_ready,

  input  logic                    snoop_resp_valid,
  input  coherence_msg_t          snoop_resp_type,
  input  logic [DATA_WIDTH-1:0]  snoop_resp_data,
  output logic                    snoop_resp_ready,

  output logic                    l2_rd_valid,
  output logic [ADDR_WIDTH-1:0]  l2_rd_addr,
  input  logic                    l2_rd_resp_valid,
  input  logic [DATA_WIDTH-1:0]  l2_rd_data,
  output logic                    l2_wr_valid,
  output logic [ADDR_WIDTH-1:0]  l2_wr_addr,
  output logic [DATA_WIDTH-1:0]  l2_wr_data
);

  typedef enum logic [1:0] {
    DIR_INVALID   = 2'b00,
    DIR_SHARED    = 2'b01,
    DIR_EXCLUSIVE = 2'b10
  } dir_state_t;

  logic                dir_valid   [0:DIR_ENTRIES-1];
  logic [1:0]          dir_state   [0:DIR_ENTRIES-1];
  logic [ADDR_WIDTH-1:0] dir_addr  [0:DIR_ENTRIES-1];
  logic [NUM_SHARERS-1:0] dir_sharers[0:DIR_ENTRIES-1];

  logic                  dir_hit;
  logic [DIR_IDX_W-1:0]  dir_idx;
  dir_state_t            dir_entry_state;
  logic [NUM_SHARERS-1:0] dir_entry_sharers;

  always_comb begin
    dir_hit   = 1'b0;
    dir_idx   = '0;
    dir_entry_state = DIR_INVALID;
    dir_entry_sharers = '0;

    for (int d = 0; d < DIR_ENTRIES; d++) begin
      if (dir_valid[d] && dir_addr[d] == req_addr && !dir_hit) begin
        dir_hit   = 1'b1;
        dir_idx   = d;
        dir_entry_state = dir_state_t'(dir_state[d]);
        dir_entry_sharers = dir_sharers[d];
      end
    end
  end

  logic [DIR_IDX_W-1:0] empty_idx;
  logic                  has_empty;

  always_comb begin
    empty_idx = '0;
    has_empty = 1'b0;
    for (int d = 0; d < DIR_ENTRIES; d++) begin
      if (!dir_valid[d] && !has_empty) begin
        empty_idx = d;
        has_empty = 1'b1;
      end
    end
  end

  typedef enum logic [3:0] {
    D_IDLE        = 4'h0,
    D_PROCESS     = 4'h1,
    D_SNOOP       = 4'h2,
    D_WAIT_SNOOP  = 4'h3,
    D_L2_READ     = 4'h4,
    D_WAIT_L2     = 4'h5,
    D_WRITEBACK   = 4'h6,
    D_RESPOND     = 4'h7
  } dir_fsm_t;

  dir_fsm_t state, state_next;

  logic [$clog2(NUM_SHARERS)-1:0] saved_src;
  coherence_msg_t                 saved_type;
  logic [ADDR_WIDTH-1:0]          saved_addr;
  logic [DATA_WIDTH-1:0]          saved_data;

  logic [DATA_WIDTH-1:0]          snoop_data;
  logic                           snoop_data_valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= D_IDLE;
      saved_src  <= '0;
      saved_type <= COH_GETS;
      saved_addr <= '0;
      saved_data <= '0;
      snoop_data <= '0;
      snoop_data_valid <= 1'b0;
    end else begin
      state <= state_next;
      if (state == D_IDLE && req_valid) begin
        saved_src  <= req_src;
        saved_type <= req_type;
        saved_addr <= req_addr;
        saved_data <= req_data;
      end

      if (state == D_WAIT_SNOOP && snoop_resp_valid && snoop_resp_type == COH_DATA_M) begin
        snoop_data <= snoop_resp_data;
        snoop_data_valid <= 1'b1;
      end

      if (state == D_IDLE) begin
        snoop_data_valid <= 1'b0;
      end
    end
  end

  always_comb begin
    state_next = state;
    case (state)
      D_IDLE:       if (req_valid) state_next = D_PROCESS;
      D_PROCESS: begin
        if (saved_type == COH_PUTM)
          state_next = D_WRITEBACK;
        else if (dir_hit && dir_entry_state == DIR_EXCLUSIVE)
          state_next = D_SNOOP;
        else if (dir_hit && dir_entry_state == DIR_SHARED && saved_type == COH_GETM)
          state_next = D_SNOOP;
        else
          state_next = D_L2_READ;
      end
      D_SNOOP:      if (snoop_ready) state_next = D_WAIT_SNOOP;
      D_WAIT_SNOOP: if (snoop_resp_valid) begin
        if (snoop_resp_type == COH_DATA_M)
          state_next = D_WRITEBACK;
        else
          state_next = D_RESPOND;
      end
      D_L2_READ:    state_next = D_WAIT_L2;
      D_WAIT_L2:    if (l2_rd_resp_valid) state_next = D_RESPOND;
      D_WRITEBACK:  state_next = D_RESPOND;
      D_RESPOND:    if (resp_ready) state_next = D_IDLE;
      default:      state_next = D_IDLE;
    endcase
  end

  assign req_ready = (state == D_IDLE);

  always_comb begin
    snoop_valid   = (state == D_SNOOP);
    snoop_addr    = saved_addr;
    snoop_target_mask = dir_entry_sharers & ~(1 << saved_src);

    if (saved_type == COH_GETS)
      snoop_type = COH_GETS;
    else
      snoop_type = COH_INV;
  end

  assign snoop_resp_ready = (state == D_WAIT_SNOOP);

  assign l2_rd_valid = (state == D_L2_READ);
  assign l2_rd_addr  = saved_addr;

  assign l2_wr_valid = (state == D_WRITEBACK);
  assign l2_wr_addr  = saved_addr;
  assign l2_wr_data  = (saved_type == COH_PUTM) ? saved_data : snoop_data;

  assign resp_valid = (state == D_RESPOND);
  assign resp_dst   = saved_src;
  assign resp_data  = snoop_data_valid ? snoop_data : l2_rd_data;

  always_comb begin
    if (saved_type == COH_GETM)
      resp_type = COH_DATA_E;
    else if (dir_hit && dir_entry_sharers != '0)
      resp_type = COH_DATA_S;
    else
      resp_type = COH_DATA_E;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int d = 0; d < DIR_ENTRIES; d++)
        dir_valid[d] <= 1'b0;
    end else if (state == D_RESPOND && resp_ready) begin
      logic [DIR_IDX_W-1:0] upd_idx;
      upd_idx = dir_hit ? dir_idx : empty_idx;

      if (saved_type == COH_GETM) begin
        dir_valid[upd_idx]   <= 1'b1;
        dir_state[upd_idx]   <= DIR_EXCLUSIVE;
        dir_sharers[upd_idx] <= (1 << saved_src);
        dir_addr[upd_idx]    <= saved_addr;
      end else if (saved_type == COH_GETS) begin
        dir_valid[upd_idx]   <= 1'b1;
        dir_state[upd_idx]   <= DIR_SHARED;
        dir_sharers[upd_idx] <= dir_hit ? (dir_entry_sharers | (1 << saved_src)) : (1 << saved_src);
        dir_addr[upd_idx]    <= saved_addr;
      end else if (saved_type == COH_PUTM) begin

        if (dir_sharers[dir_idx] == (1 << saved_src)) begin
          dir_valid[dir_idx] <= 1'b0;
        end else begin
          dir_state[dir_idx] <= DIR_SHARED;
        end
      end
    end
  end

endmodule : coherence_directory

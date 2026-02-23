`timescale 1ns/1ps

module hbm4_controller
  import agni_pkg::*;
#(
  parameter int unsigned CTRL_ID    = 0,
  parameter int unsigned BUS_WIDTH  = 512,
  parameter int unsigned QUEUE_DEPTH = 64,

  parameter int unsigned tRC   = 48,
  parameter int unsigned tRCD  = 14,
  parameter int unsigned tRP   = 14,
  parameter int unsigned tCL   = 14,
  parameter int unsigned tRFC  = 260,
  parameter int unsigned tREFI = 3900
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        req_valid,
  input  logic [47:0] req_addr,
  input  logic        req_we,
  input  logic [BUS_WIDTH-1:0] req_wdata,
  output logic        req_ready,

  output logic        resp_valid,
  output logic [BUS_WIDTH-1:0] resp_data,
  output ecc_error_t  resp_ecc_status,

  output logic        hbm_ck,
  output logic        hbm_cke,
  output logic [1:0]  hbm_cmd,
  output logic [17:0] hbm_addr,
  output logic [3:0]  hbm_ba,
  output logic [BUS_WIDTH-1:0] hbm_dq_out,
  input  logic [BUS_WIDTH-1:0] hbm_dq_in,
  output logic        hbm_dq_oe,

  input  logic [7:0]  hbm_temp,

  output logic [31:0] ecc_ce_count,
  output logic [31:0] ecc_ue_count
);

  logic [13:0] row_addr;
  logic [5:0]  col_addr;
  logic [3:0]  bank_addr;

  assign row_addr  = req_addr[27:14];
  assign col_addr  = req_addr[13:8];
  assign bank_addr = req_addr[7:4];

  logic                  reqq_valid [0:QUEUE_DEPTH-1];
  logic [47:0]           reqq_addr  [0:QUEUE_DEPTH-1];
  logic                  reqq_we    [0:QUEUE_DEPTH-1];
  logic [BUS_WIDTH-1:0]  reqq_wdata [0:QUEUE_DEPTH-1];
  logic [13:0]           reqq_row   [0:QUEUE_DEPTH-1];
  logic [3:0]            reqq_bank  [0:QUEUE_DEPTH-1];
  logic [5:0]            reqq_col   [0:QUEUE_DEPTH-1];
  logic [$clog2(QUEUE_DEPTH)-1:0] q_head, q_tail;
  logic [$clog2(QUEUE_DEPTH):0]   q_count;

  assign req_ready = (q_count < QUEUE_DEPTH);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      q_tail  <= '0;
      q_count <= '0;
      for (int i = 0; i < QUEUE_DEPTH; i++) begin
        reqq_valid[i] <= 1'b0;
      end
    end else begin
      if (req_valid && req_ready) begin
        reqq_valid[q_tail] <= 1'b1;
        reqq_addr[q_tail]  <= req_addr;
        reqq_we[q_tail]    <= req_we;
        reqq_wdata[q_tail] <= req_wdata;
        reqq_row[q_tail]   <= row_addr;
        reqq_bank[q_tail]  <= bank_addr;
        reqq_col[q_tail]   <= col_addr;
        q_tail <= q_tail + 1'b1;
        if (!(state == MC_ISSUE))
          q_count <= q_count + 1'b1;
      end
      if (state == MC_ISSUE) begin
        reqq_valid[q_head] <= 1'b0;
      end
      if (state == MC_ISSUE && !(req_valid && req_ready))
        q_count <= q_count - 1'b1;
    end
  end

  typedef enum logic [1:0] {
    BANK_IDLE    = 2'b00,
    BANK_ACTIVE  = 2'b01,
    BANK_PRECHARGE = 2'b10,
    BANK_REFRESH = 2'b11
  } bank_state_t;

  bank_state_t bank_state [0:15];
  logic [13:0] bank_open_row [0:15];
  logic [15:0] bank_timer    [0:15];

  logic [15:0] refresh_counter;
  logic        refresh_needed;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      refresh_counter <= '0;
      refresh_needed  <= 1'b0;
    end else begin
      if (refresh_counter >= tREFI[15:0]) begin
        refresh_counter <= '0;
        refresh_needed  <= 1'b1;
      end else begin
        refresh_counter <= refresh_counter + 1'b1;
      end

      if (state == MC_REFRESH)
        refresh_needed <= 1'b0;
    end
  end

  typedef enum logic [3:0] {
    MC_IDLE     = 4'b0000,
    MC_ACTIVATE = 4'b0001,
    MC_READ     = 4'b0010,
    MC_WRITE    = 4'b0011,
    MC_PRECHARGE = 4'b0100,
    MC_REFRESH  = 4'b0101,
    MC_ISSUE    = 4'b0110,
    MC_WAIT     = 4'b0111
  } mc_state_t;

  mc_state_t state, state_next;
  logic [15:0] wait_counter;
  logic        current_req_valid;
  logic [47:0] current_req_addr;
  logic        current_req_we;
  logic [BUS_WIDTH-1:0] current_req_wdata;
  logic [13:0] current_req_row;
  logic [3:0]  current_req_bank;
  logic [5:0]  current_req_col;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= MC_IDLE;
      wait_counter <= '0;
      q_head       <= '0;
      for (int b = 0; b < 16; b++) begin
        bank_state[b]    <= BANK_IDLE;
        bank_open_row[b] <= '0;
      end
    end else begin
      state <= state_next;

      case (state)
        MC_ACTIVATE: begin
          bank_state[current_req_bank]    <= BANK_ACTIVE;
          bank_open_row[current_req_bank] <= current_req_row;
          wait_counter <= tRCD[15:0];
        end
        MC_PRECHARGE: begin
          bank_state[current_req_bank] <= BANK_PRECHARGE;
          wait_counter <= tRP[15:0];
        end
        MC_READ: begin
          wait_counter <= tCL[15:0];
        end
        MC_WRITE: begin
          wait_counter <= 16'd4;
        end
        MC_REFRESH: begin
          wait_counter <= tRFC[15:0];
        end
        MC_WAIT: begin
          if (wait_counter > 0)
            wait_counter <= wait_counter - 1'b1;
        end
        MC_ISSUE: begin
          q_head <= q_head + 1'b1;
        end
        default: ;
      endcase
    end
  end

  always_comb begin
    current_req_valid = reqq_valid[q_head];
    current_req_addr  = reqq_addr[q_head];
    current_req_we    = reqq_we[q_head];
    current_req_wdata = reqq_wdata[q_head];
    current_req_row   = reqq_row[q_head];
    current_req_bank  = reqq_bank[q_head];
    current_req_col   = reqq_col[q_head];

    state_next = state;
    case (state)
      MC_IDLE: begin
        if (refresh_needed)
          state_next = MC_REFRESH;
        else if (q_count > 0)
          state_next = MC_ISSUE;
      end
      MC_ISSUE: begin

        if (bank_state[current_req_bank] == BANK_ACTIVE &&
            bank_open_row[current_req_bank] == current_req_row) begin

          if (current_req_we)
            state_next = MC_WRITE;
          else
            state_next = MC_READ;
        end else if (bank_state[current_req_bank] == BANK_ACTIVE) begin

          state_next = MC_PRECHARGE;
        end else begin

          state_next = MC_ACTIVATE;
        end
      end
      MC_ACTIVATE: state_next = MC_WAIT;
      MC_PRECHARGE: state_next = MC_WAIT;
      MC_READ:  state_next = MC_WAIT;
      MC_WRITE: state_next = MC_WAIT;
      MC_REFRESH: state_next = MC_WAIT;
      MC_WAIT: begin
        if (wait_counter == 0) begin
          if (bank_state[current_req_bank] == BANK_PRECHARGE)
            state_next = MC_ACTIVATE;
          else
            state_next = MC_IDLE;
        end
      end
      default: state_next = MC_IDLE;
    endcase
  end

  logic [319:0] ecc_encoded;
  logic [255:0] ecc_decoded;
  ecc_error_t   ecc_status;

  chipkill_ecc u_chipkill (
    .clk             (clk),
    .rst_n           (rst_n),
    .enc_valid       (state == MC_WRITE),
    .enc_data_in     (current_req_wdata[255:0]),
    .enc_code_out    (ecc_encoded),
    .enc_done        (),
    .dec_valid       (hbm_dq_oe == 1'b0 && wait_counter == 0),
    .dec_code_in     ({64'b0, hbm_dq_in[255:0]}),
    .dec_data_out    (ecc_decoded),
    .dec_error       (ecc_status),
    .dec_failed_symbol(),
    .dec_done        ()
  );

  assign hbm_ck     = clk;
  assign hbm_cke    = (state != MC_IDLE);
  assign hbm_dq_oe  = (state == MC_WRITE);
  assign hbm_dq_out = current_req_wdata;
  assign hbm_addr   = (state == MC_ACTIVATE) ? {4'b0, current_req_row} :
                       {12'b0, current_req_col};
  assign hbm_ba     = current_req_bank;
  assign hbm_cmd    = (state == MC_ACTIVATE) ? 2'b01 :
                       (state == MC_READ)     ? 2'b10 :
                       (state == MC_WRITE)    ? 2'b11 :
                       (state == MC_PRECHARGE)? 2'b00 : 2'b00;

  assign resp_valid      = (state == MC_WAIT) && (wait_counter == 0) && !current_req_we;
  assign resp_data       = hbm_dq_in;
  assign resp_ecc_status = ecc_status;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ecc_ce_count <= '0;
      ecc_ue_count <= '0;
    end else begin
      if (resp_valid && ecc_status == ECC_CORRECTED)
        ecc_ce_count <= ecc_ce_count + 1'b1;
      if (resp_valid && ecc_status == ECC_DETECTED)
        ecc_ue_count <= ecc_ue_count + 1'b1;
    end
  end

endmodule : hbm4_controller

`timescale 1ns/1ps

module fetch_unit
  import agni_pkg::*;
#(
  parameter int unsigned MAX_WARPS = 64,
  parameter int unsigned PC_WIDTH  = 48,
  parameter int unsigned INSTR_W   = 32
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic                    sched_valid,
  input  logic [$clog2(MAX_WARPS)-1:0] sched_warp_id,
  output logic                    sched_ready,

  input  logic                    branch_redirect,
  input  logic [$clog2(MAX_WARPS)-1:0] branch_warp_id,
  input  logic [PC_WIDTH-1:0]    branch_target_pc,

  input  logic                    warp_start_valid,
  input  logic [$clog2(MAX_WARPS)-1:0] warp_start_id,
  input  logic [PC_WIDTH-1:0]    warp_start_pc,
  input  logic                    warp_exit_valid,
  input  logic [$clog2(MAX_WARPS)-1:0] warp_exit_id,

  output logic        icache_req_valid,
  output logic [47:0] icache_req_pc,
  input  logic        icache_req_ready,
  input  logic        icache_resp_valid,
  input  logic [INSTR_W-1:0] icache_resp_data,
  input  logic [47:0] icache_resp_pc,

  output logic        decode_valid,
  output warp_instr_t decode_instr,
  output logic [$clog2(MAX_WARPS)-1:0] decode_warp_id
);

  logic [PC_WIDTH-1:0] warp_pc [0:MAX_WARPS-1];
  logic [MAX_WARPS-1:0] warp_valid;

  typedef enum logic [1:0] {
    FETCH_IDLE     = 2'b00,
    FETCH_REQUEST  = 2'b01,
    FETCH_WAIT     = 2'b10,
    FETCH_DECODE   = 2'b11
  } fetch_state_t;

  fetch_state_t f_state, f_state_next;
  logic [$clog2(MAX_WARPS)-1:0] f_warp_id;
  logic [PC_WIDTH-1:0] f_pc;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      f_state   <= FETCH_IDLE;
      f_warp_id <= '0;
      f_pc      <= '0;
    end else begin
      f_state <= f_state_next;
      if (f_state == FETCH_IDLE && sched_valid) begin
        f_warp_id <= sched_warp_id;
        f_pc      <= warp_pc[sched_warp_id];
      end
    end
  end

  always_comb begin
    f_state_next = f_state;
    case (f_state)
      FETCH_IDLE:    if (sched_valid)                   f_state_next = FETCH_REQUEST;
      FETCH_REQUEST: if (icache_req_ready)              f_state_next = FETCH_WAIT;
      FETCH_WAIT:    if (icache_resp_valid)              f_state_next = FETCH_DECODE;
      FETCH_DECODE:  f_state_next = FETCH_IDLE;
      default:       f_state_next = FETCH_IDLE;
    endcase
  end

  assign sched_ready       = (f_state == FETCH_IDLE);
  assign icache_req_valid  = (f_state == FETCH_REQUEST);
  assign icache_req_pc     = f_pc;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      warp_valid <= '0;
      for (int i = 0; i < MAX_WARPS; i++)
        warp_pc[i] <= '0;
    end else begin

      if (warp_start_valid) begin
        warp_pc[warp_start_id]    <= warp_start_pc;
        warp_valid[warp_start_id] <= 1'b1;
      end

      if (warp_exit_valid) begin
        warp_valid[warp_exit_id] <= 1'b0;
      end

      if (branch_redirect) begin
        warp_pc[branch_warp_id] <= branch_target_pc;
      end

      else if (f_state == FETCH_DECODE) begin
        warp_pc[f_warp_id] <= f_pc + 4;
      end
    end
  end

  logic [INSTR_W-1:0] raw_instr;
  assign raw_instr = icache_resp_data;

  warp_instr_t decoded;

  always_comb begin
    decoded = '0;

    decoded.opcode     = alu_op_t'(raw_instr[31:27]);
    decoded.dst_reg    = raw_instr[26:22];
    decoded.src0_reg   = raw_instr[21:17];
    decoded.src1_reg   = raw_instr[16:12];
    decoded.src2_reg   = raw_instr[11:7];
    decoded.precision  = precision_t'(raw_instr[6:5]);
    decoded.predicated = raw_instr[4];
    decoded.warp_id    = {{(7-$clog2(MAX_WARPS)){1'b0}}, f_warp_id};
    decoded.immediate  = '0;

    if (raw_instr[31]) begin

      decoded.immediate = {{15{raw_instr[16]}}, raw_instr[16:0]};
      decoded.src1_reg  = '0;
      decoded.src2_reg  = '0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      decode_valid   <= 1'b0;
      decode_instr   <= '0;
      decode_warp_id <= '0;
    end else begin
      decode_valid <= (f_state == FETCH_DECODE) && icache_resp_valid;
      if (f_state == FETCH_DECODE && icache_resp_valid) begin
        decode_instr   <= decoded;
        decode_warp_id <= f_warp_id;
      end
    end
  end

endmodule : fetch_unit

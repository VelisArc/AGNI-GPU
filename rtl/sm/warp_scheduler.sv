`timescale 1ns/1ps

module warp_scheduler
  import agni_pkg::*;
#(
  parameter int unsigned MAX_WARPS     = 16,
  parameter int unsigned WARP_ID_BASE  = 0,
  parameter int unsigned NUM_SCHEDULERS = 4
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic [MAX_WARPS-1:0]     warp_active,
  input  logic [MAX_WARPS-1:0]     warp_at_barrier,

  output logic                     fetch_req,
  output logic [$clog2(MAX_WARPS)-1:0] fetch_warp_id,
  input  logic                     fetched_valid,
  input  warp_instr_t              fetched_instr,

  output logic                     dispatch_valid,
  output warp_instr_t              dispatch_instr,
  output logic                     dispatch_ready,

  input  logic                     wb_valid,
  input  logic [6:0]               wb_warp_id,
  input  logic [4:0]               wb_dst_reg
);

  typedef enum logic [2:0] {
    WARP_IDLE       = 3'b000,
    WARP_FETCH      = 3'b001,
    WARP_READY      = 3'b010,
    WARP_ISSUED     = 3'b011,
    WARP_STALLED    = 3'b100,
    WARP_BARRIER    = 3'b101,
    WARP_DONE       = 3'b110
  } warp_state_t;

  warp_state_t warp_state [0:MAX_WARPS-1];

  alu_op_t      ib_opcode    [0:MAX_WARPS-1];
  logic [4:0]   ib_dst_reg   [0:MAX_WARPS-1];
  logic [4:0]   ib_src0_reg  [0:MAX_WARPS-1];
  logic [4:0]   ib_src1_reg  [0:MAX_WARPS-1];
  logic [4:0]   ib_src2_reg  [0:MAX_WARPS-1];
  precision_t   ib_precision [0:MAX_WARPS-1];
  logic         ib_predicated[0:MAX_WARPS-1];
  logic [6:0]   ib_warp_id   [0:MAX_WARPS-1];
  logic [31:0]  ib_immediate [0:MAX_WARPS-1];
  logic [MAX_WARPS-1:0] instr_buf_valid;

  logic [31:0] scoreboard [0:MAX_WARPS-1];

  logic [MAX_WARPS-1:0] warp_hazard;

  always_comb begin
    for (int i = 0; i < MAX_WARPS; i++) begin
      warp_hazard[i] = scoreboard[i][ib_src0_reg[i]] |
                        scoreboard[i][ib_src1_reg[i]] |
                        scoreboard[i][ib_src2_reg[i]];
    end
  end

  logic [MAX_WARPS-1:0] warp_ready;

  always_comb begin
    for (int i = 0; i < MAX_WARPS; i++) begin
      warp_ready[i] = warp_active[i] &&
                       instr_buf_valid[i] &&
                       (warp_state[i] == WARP_READY) &&
                       !warp_at_barrier[i] &&
                       !warp_hazard[i];
    end
  end

  logic [15:0] warp_age [0:MAX_WARPS-1];

  logic [$clog2(MAX_WARPS)-1:0] selected_warp;
  logic                          any_ready;

  always_comb begin
    selected_warp = '0;
    any_ready     = 1'b0;

    for (int i = 0; i < MAX_WARPS; i++) begin
      if (warp_ready[i] && !any_ready) begin
        selected_warp = i;
        any_ready     = 1'b1;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < MAX_WARPS; i++) begin
        warp_state[i]     <= WARP_IDLE;
        instr_buf_valid[i] <= 1'b0;
        scoreboard[i]     <= '0;
        warp_age[i]       <= '0;
      end
    end else begin

      if (wb_valid) begin : wb_blk
        logic [$clog2(MAX_WARPS)-1:0] wb_local;
        wb_local = wb_warp_id[$clog2(MAX_WARPS)-1:0] - WARP_ID_BASE[$clog2(MAX_WARPS)-1:0];
        if (wb_local < MAX_WARPS) begin
          scoreboard[wb_local][wb_dst_reg] <= 1'b0;
        end
      end

      for (int i = 0; i < MAX_WARPS; i++) begin
        if (!warp_active[i]) begin
          warp_state[i]     <= WARP_IDLE;
          instr_buf_valid[i] <= 1'b0;
          scoreboard[i]     <= '0;
          warp_age[i]       <= '0;
        end else begin

          if (warp_state[i] != WARP_IDLE && warp_state[i] != WARP_DONE)
            warp_age[i] <= warp_age[i] + 1'b1;

          case (warp_state[i])
            WARP_IDLE: begin
              if (warp_active[i])
                warp_state[i] <= WARP_FETCH;
            end

            WARP_FETCH: begin
              if (fetched_valid && fetch_warp_id == i[$clog2(MAX_WARPS)-1:0]) begin
                ib_opcode[i]     <= fetched_instr.opcode;
                ib_dst_reg[i]    <= fetched_instr.dst_reg;
                ib_src0_reg[i]   <= fetched_instr.src0_reg;
                ib_src1_reg[i]   <= fetched_instr.src1_reg;
                ib_src2_reg[i]   <= fetched_instr.src2_reg;
                ib_precision[i]  <= fetched_instr.precision;
                ib_predicated[i] <= fetched_instr.predicated;
                ib_warp_id[i]    <= fetched_instr.warp_id;
                ib_immediate[i]  <= fetched_instr.immediate;
                instr_buf_valid[i] <= 1'b1;
                warp_state[i]      <= WARP_READY;
              end
            end

            WARP_READY: begin
              if (warp_at_barrier[i]) begin
                warp_state[i] <= WARP_BARRIER;
              end else if (any_ready && selected_warp == i[$clog2(MAX_WARPS)-1:0]) begin
                warp_state[i]      <= WARP_ISSUED;
                instr_buf_valid[i] <= 1'b0;
                warp_age[i]        <= '0;

                scoreboard[i][ib_dst_reg[i]] <= 1'b1;
              end
            end

            WARP_ISSUED: begin
              warp_state[i] <= WARP_FETCH;
            end

            WARP_BARRIER: begin
              if (!warp_at_barrier[i])
                warp_state[i] <= WARP_FETCH;
            end

            WARP_STALLED: begin
              if (!warp_hazard[i])
                warp_state[i] <= WARP_READY;
            end

            default: warp_state[i] <= WARP_IDLE;
          endcase
        end
      end
    end
  end

  logic [MAX_WARPS-1:0] needs_fetch;

  always_comb begin
    for (int i = 0; i < MAX_WARPS; i++)
      needs_fetch[i] = (warp_state[i] == WARP_FETCH);
  end

  always_comb begin
    fetch_req     = |needs_fetch;
    fetch_warp_id = '0;
    begin : fetch_sel_blk
      logic fetch_found;
      fetch_found = 1'b0;
      for (int i = 0; i < MAX_WARPS; i++) begin
        if (needs_fetch[i] && !fetch_found) begin
          fetch_warp_id = i;
          fetch_found = 1'b1;
        end
      end
    end
  end

  warp_instr_t dispatch_instr_r;

  always_comb begin
    dispatch_instr_r.opcode     = ib_opcode[selected_warp];
    dispatch_instr_r.dst_reg    = ib_dst_reg[selected_warp];
    dispatch_instr_r.src0_reg   = ib_src0_reg[selected_warp];
    dispatch_instr_r.src1_reg   = ib_src1_reg[selected_warp];
    dispatch_instr_r.src2_reg   = ib_src2_reg[selected_warp];
    dispatch_instr_r.precision  = ib_precision[selected_warp];
    dispatch_instr_r.predicated = ib_predicated[selected_warp];
    dispatch_instr_r.warp_id    = ib_warp_id[selected_warp];
    dispatch_instr_r.immediate  = ib_immediate[selected_warp];
  end

  assign dispatch_valid = any_ready;
  assign dispatch_instr = any_ready ? dispatch_instr_r : '0;
  assign dispatch_ready = any_ready;

endmodule : warp_scheduler

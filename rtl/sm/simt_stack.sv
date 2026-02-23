`timescale 1ns/1ps

module simt_stack
  import agni_pkg::*;
#(
  parameter int unsigned WARP_LANES  = 32,
  parameter int unsigned STACK_DEPTH = 32,
  parameter int unsigned PC_WIDTH    = 48
)(
  input  logic                    clk,
  input  logic                    rst_n,

  input  logic                    branch_valid,
  input  logic                    branch_divergent,
  input  logic                    branch_uniform,
  input  logic [WARP_LANES-1:0]  branch_taken_mask,
  input  logic [PC_WIDTH-1:0]    branch_target_pc,
  input  logic [PC_WIDTH-1:0]    branch_fall_through,
  input  logic [PC_WIDTH-1:0]    branch_reconverge_pc,

  input  logic [PC_WIDTH-1:0]    current_pc,
  input  logic                    sync_instruction,

  output logic [WARP_LANES-1:0]  active_mask,
  output logic [PC_WIDTH-1:0]    next_pc,
  output logic                    reconverge_trigger,

  output logic                    warp_active,
  output logic [$clog2(STACK_DEPTH):0] stack_depth,
  output logic                    stack_overflow,
  output logic                    stack_underflow
);

  logic                    stk_valid         [0:STACK_DEPTH-1];
  logic [WARP_LANES-1:0]  stk_active_mask   [0:STACK_DEPTH-1];
  logic [PC_WIDTH-1:0]    stk_reconverge_pc [0:STACK_DEPTH-1];
  logic [PC_WIDTH-1:0]    stk_next_path_pc  [0:STACK_DEPTH-1];
  logic [WARP_LANES-1:0]  stk_pending_mask  [0:STACK_DEPTH-1];
  logic                    stk_both_done     [0:STACK_DEPTH-1];

  logic [$clog2(STACK_DEPTH)-1:0] sp;
  logic [$clog2(STACK_DEPTH):0]   depth;

  logic [WARP_LANES-1:0] cur_active_mask;
  logic [PC_WIDTH-1:0]   cur_pc;

  logic reconverge_match;
  logic top_valid;
  logic [$clog2(STACK_DEPTH)-1:0] top_idx;

  assign top_idx          = sp - 1;
  assign top_valid        = (depth > 0) && stk_valid[top_idx];
  assign reconverge_match = top_valid && (current_pc == stk_reconverge_pc[top_idx]);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sp              <= '0;
      depth           <= '0;
      cur_active_mask <= {WARP_LANES{1'b1}};
      cur_pc          <= '0;
      stack_overflow  <= 1'b0;
      stack_underflow <= 1'b0;
      for (int i = 0; i < STACK_DEPTH; i++)
        stk_valid[i] <= 1'b0;
    end else begin
      stack_overflow  <= 1'b0;
      stack_underflow <= 1'b0;

      if (branch_valid && branch_divergent) begin
        if (depth >= STACK_DEPTH) begin
          stack_overflow <= 1'b1;
        end else begin

          stk_valid[sp]         <= 1'b1;
          stk_active_mask[sp]   <= cur_active_mask;
          stk_reconverge_pc[sp] <= branch_reconverge_pc;
          stk_next_path_pc[sp]  <= branch_fall_through;
          stk_pending_mask[sp]  <= cur_active_mask & ~branch_taken_mask;
          stk_both_done[sp]     <= 1'b0;

          cur_active_mask <= cur_active_mask & branch_taken_mask;
          cur_pc          <= branch_target_pc;

          sp    <= sp + 1;
          depth <= depth + 1;
        end
      end

      else if (branch_valid && branch_uniform) begin
        if (|branch_taken_mask)
          cur_pc <= branch_target_pc;
        else
          cur_pc <= branch_fall_through;
      end

      else if (reconverge_match || sync_instruction) begin
        if (depth == 0) begin
          stack_underflow <= 1'b0;
        end else begin
          if (!stk_both_done[top_idx]) begin

            stk_both_done[top_idx] <= 1'b1;
            cur_active_mask        <= stk_pending_mask[top_idx];
            cur_pc                 <= stk_next_path_pc[top_idx];
          end else begin

            cur_active_mask       <= stk_active_mask[top_idx];
            cur_pc                <= stk_reconverge_pc[top_idx];
            stk_valid[top_idx]    <= 1'b0;
            sp    <= sp - 1;
            depth <= depth - 1;
          end
        end
      end
    end
  end

  assign active_mask        = cur_active_mask;
  assign next_pc            = cur_pc;
  assign warp_active        = |cur_active_mask;
  assign stack_depth        = depth;
  assign reconverge_trigger = reconverge_match || sync_instruction;

endmodule : simt_stack

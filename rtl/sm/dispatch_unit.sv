`timescale 1ns/1ps

module dispatch_unit
  import agni_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  logic [3:0]        sched_valid,
  input  alu_op_t            si_opcode    [4],
  input  logic [4:0]         si_dst_reg   [4],
  input  logic [4:0]         si_src0_reg  [4],
  input  logic [4:0]         si_src1_reg  [4],
  input  logic [4:0]         si_src2_reg  [4],
  input  precision_t         si_precision [4],
  input  logic               si_predicated[4],
  input  logic [6:0]         si_warp_id   [4],
  input  logic [31:0]        si_immediate [4],

  input  logic              fp32_ready,
  input  logic              int32_ready,
  input  logic              tc_ready,
  input  logic              sfu_ready,
  input  logic              lsu_ready,

  output logic              fp32_dispatch_valid,
  output alu_op_t           fp32_opcode,
  output logic [31:0]       fp32_src0,
  output logic [31:0]       fp32_src1,
  output logic [31:0]       fp32_src2,
  output logic [6:0]        fp32_warp_id,
  output logic [4:0]        fp32_lane_id,
  output logic [4:0]        fp32_dst_reg,

  output logic              int32_dispatch_valid,
  output alu_op_t           int32_opcode,
  output logic [31:0]       int32_src0,
  output logic [31:0]       int32_src1,
  output logic [6:0]        int32_warp_id,
  output logic [4:0]        int32_lane_id,
  output logic [4:0]        int32_dst_reg,

  output logic              sfu_dispatch_valid,
  output sfu_op_t           sfu_opcode,
  output logic [31:0]       sfu_operand,
  output logic [6:0]        sfu_warp_id,
  output logic [4:0]        sfu_lane_id,
  output logic [4:0]        sfu_dst_reg,

  output logic              tc_dispatch_valid,
  output tc_op_t            tc_opcode,
  output precision_t        tc_precision,

  output logic              lsu_dispatch_valid,
  output mem_op_t           lsu_opcode,
  output logic [47:0]       lsu_addr,
  output logic [6:0]        lsu_warp_id,

  output logic [3:0]        sched_stall
);

  typedef enum logic [2:0] {
    UNIT_FP32  = 3'b000,
    UNIT_INT32 = 3'b001,
    UNIT_SFU   = 3'b010,
    UNIT_TC    = 3'b011,
    UNIT_LSU   = 3'b100,
    UNIT_NONE  = 3'b111
  } exec_unit_t;

  function automatic exec_unit_t classify_op(
    input alu_op_t   opcode,
    input precision_t prec
  );
    case (opcode)
      ALU_ADD, ALU_SUB, ALU_MUL, ALU_FMA,
      ALU_CMP_EQ, ALU_CMP_LT, ALU_CMP_LE,
      ALU_MIN, ALU_MAX, ALU_ABS, ALU_NEG: begin
        if (prec == PREC_FP32 || prec == PREC_FP16 || prec == PREC_BF16)
          return UNIT_FP32;
        else
          return UNIT_INT32;
      end
      ALU_AND, ALU_OR, ALU_XOR,
      ALU_SHL, ALU_SHR, ALU_SHRA,
      ALU_MOD:
        return UNIT_INT32;
      ALU_DIV:
        return UNIT_SFU;
      ALU_CVT:
        return UNIT_FP32;
      ALU_NOP:
        return UNIT_NONE;
      default:
        return UNIT_INT32;
    endcase
  endfunction

  logic [1:0] rr_priority;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rr_priority <= '0;
    else
      rr_priority <= rr_priority + 1'b1;
  end

  exec_unit_t target_unit [4];

  always_comb begin
    for (int i = 0; i < 4; i++) begin
      if (sched_valid[i])
        target_unit[i] = classify_op(si_opcode[i], si_precision[i]);
      else
        target_unit[i] = UNIT_NONE;
    end

    fp32_dispatch_valid  = 1'b0;
    int32_dispatch_valid = 1'b0;
    sfu_dispatch_valid   = 1'b0;
    tc_dispatch_valid    = 1'b0;
    lsu_dispatch_valid   = 1'b0;
    sched_stall          = '0;

    fp32_opcode  = ALU_NOP;
    fp32_src0    = '0; fp32_src1 = '0; fp32_src2 = '0;
    fp32_warp_id = '0; fp32_lane_id = '0;
    fp32_dst_reg = '0;

    int32_opcode = ALU_NOP;
    int32_src0   = '0; int32_src1 = '0;
    int32_warp_id = '0; int32_lane_id = '0;
    int32_dst_reg = '0;

    sfu_opcode  = SFU_RCP;
    sfu_operand = '0; sfu_warp_id = '0; sfu_lane_id = '0;
    sfu_dst_reg = '0;

    tc_opcode    = TC_MMA;
    tc_precision = PREC_FP16;

    lsu_opcode   = MEM_LOAD;
    lsu_addr     = '0; lsu_warp_id = '0;

    for (int i = 0; i < 4; i++) begin : dispatch_loop
      int idx;
      idx = (i + rr_priority) & 2'b11;

      if (sched_valid[idx]) begin
        case (target_unit[idx])
          UNIT_FP32: begin
            if (fp32_ready && !fp32_dispatch_valid) begin
              fp32_dispatch_valid = 1'b1;
              fp32_opcode  = alu_op_t'(si_opcode[idx]);
              fp32_src0    = {27'd0, si_src0_reg[idx]};
              fp32_src1    = {27'd0, si_src1_reg[idx]};
              fp32_src2    = si_immediate[idx];
              fp32_warp_id = si_warp_id[idx];
              fp32_lane_id = 5'd0;
              fp32_dst_reg = si_dst_reg[idx];
            end else begin
              sched_stall[idx] = 1'b1;
            end
          end

          UNIT_INT32: begin
            if (int32_ready && !int32_dispatch_valid) begin
              int32_dispatch_valid = 1'b1;
              int32_opcode  = alu_op_t'(si_opcode[idx]);
              int32_src0    = {27'd0, si_src0_reg[idx]};
              int32_src1    = (si_immediate[idx] != '0) ? si_immediate[idx] :
                              {27'd0, si_src1_reg[idx]};
              int32_warp_id = si_warp_id[idx];
              int32_lane_id = 5'd0;
              int32_dst_reg = si_dst_reg[idx];
            end else begin
              sched_stall[idx] = 1'b1;
            end
          end

          UNIT_SFU: begin
            if (sfu_ready && !sfu_dispatch_valid) begin
              sfu_dispatch_valid = 1'b1;
              sfu_opcode = SFU_RCP;
              sfu_operand = (si_immediate[idx] != '0) ? si_immediate[idx] :
                            {27'd0, si_src0_reg[idx]};
              sfu_warp_id = si_warp_id[idx];
              sfu_lane_id = 5'd0;
              sfu_dst_reg = si_dst_reg[idx];
            end else begin
              sched_stall[idx] = 1'b1;
            end
          end

          UNIT_TC: begin
            if (tc_ready && !tc_dispatch_valid) begin
              tc_dispatch_valid = 1'b1;
              tc_precision = precision_t'(si_precision[idx]);
            end else begin
              sched_stall[idx] = 1'b1;
            end
          end

          UNIT_LSU: begin
            if (lsu_ready && !lsu_dispatch_valid) begin
              lsu_dispatch_valid = 1'b1;
              lsu_warp_id = si_warp_id[idx];
            end else begin
              sched_stall[idx] = 1'b1;
            end
          end

          UNIT_NONE: ;

          default: ;
        endcase
      end
    end
  end

endmodule : dispatch_unit

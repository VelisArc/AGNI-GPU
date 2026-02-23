`timescale 1ns/1ps

`ifndef AGNI_PKG_IMPORTED
`define AGNI_PKG_IMPORTED
`endif

module fp32_alu
  import agni_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        valid_in,
  input  alu_op_t     opcode,
  input  logic [31:0] src0,
  input  logic [31:0] src1,
  input  logic [31:0] src2,
  input  logic [6:0]  warp_id_in,
  input  logic [4:0]  lane_id_in,

  output logic        valid_out,
  output logic [31:0] result,
  output logic [4:0]  fp_flags,
  output logic [6:0]  warp_id_out,
  output logic [4:0]  lane_id_out
);

  localparam logic [31:0] FP32_ONE  = 32'h3F800000;
  localparam logic [31:0] FP32_ZERO = 32'h00000000;

  logic [31:0] fma_a, fma_b, fma_c;
  logic        fma_valid_in;
  logic        fma_valid_out;
  logic [31:0] fma_result;
  logic [4:0]  fma_flags;

  always @* begin
    fma_a        = src0;
    fma_b        = src1;
    fma_c        = src2;
    fma_valid_in = valid_in;

    case (opcode)
      ALU_ADD: begin
        fma_a = FP32_ONE;
        fma_b = src0;
        fma_c = src1;
      end
      ALU_SUB: begin
        fma_a = FP32_ONE;
        fma_b = src0;
        fma_c = {~src1[31], src1[30:0]};
      end
      ALU_MUL: begin
        fma_a = src0;
        fma_b = src1;
        fma_c = FP32_ZERO;
      end
      ALU_FMA: begin
        fma_a = src0;
        fma_b = src1;
        fma_c = src2;
      end

      ALU_CMP_EQ, ALU_CMP_LT, ALU_CMP_LE,
      ALU_MIN, ALU_MAX, ALU_ABS, ALU_NEG: begin
        fma_valid_in = 1'b0;
      end
      default: begin
        fma_valid_in = 1'b0;
      end
    endcase
  end

  fma_unit u_fma (
    .clk           (clk),
    .rst_n         (rst_n),
    .valid_in      (fma_valid_in),
    .operand_a     (fma_a),
    .operand_b     (fma_b),
    .operand_c     (fma_c),
    .rounding_mode (2'b00),
    .valid_out     (fma_valid_out),
    .result        (fma_result),
    .flags         (fma_flags)
  );

  logic        cmp_valid;
  logic [31:0] cmp_result;
  logic [4:0]  cmp_flags;

  logic [2:0]  bypass_valid_pipe;
  logic [31:0] bypass_result_pipe [0:2];
  logic [4:0]  bypass_flags_pipe  [0:2];
  logic [6:0]  warp_pipe [0:2];
  logic [4:0]  lane_pipe [0:2];
  logic [2:0]  use_bypass_pipe;

  always @* begin
    cmp_valid  = 1'b0;
    cmp_result = '0;
    cmp_flags  = '0;

    if (valid_in) begin
      case (opcode)
        ALU_CMP_EQ: begin
          cmp_valid  = 1'b1;
          cmp_result = (src0 == src1) ? 32'hFFFFFFFF : 32'h0;
        end
        ALU_CMP_LT: begin
          cmp_valid  = 1'b1;

          if (src0[31] != src1[31])
            cmp_result = src0[31] ? 32'hFFFFFFFF : 32'h0;
          else if (src0[31])
            cmp_result = (src0[30:0] > src1[30:0]) ? 32'hFFFFFFFF : 32'h0;
          else
            cmp_result = (src0[30:0] < src1[30:0]) ? 32'hFFFFFFFF : 32'h0;
        end
        ALU_CMP_LE: begin
          cmp_valid  = 1'b1;
          cmp_result = (src0 == src1) ? 32'hFFFFFFFF :
                       (src0[31] && !src1[31]) ? 32'hFFFFFFFF :
                       (!src0[31] && src1[31]) ? 32'h0 :
                       (src0[31]) ? ((src0[30:0] >= src1[30:0]) ? 32'hFFFFFFFF : 32'h0) :
                                    ((src0[30:0] <= src1[30:0]) ? 32'hFFFFFFFF : 32'h0);
        end
        ALU_MIN: begin
          cmp_valid  = 1'b1;

          if (src0[31] && !src1[31])
            cmp_result = src0;
          else if (!src0[31] && src1[31])
            cmp_result = src1;
          else if (src0[31])
            cmp_result = (src0[30:0] > src1[30:0]) ? src0 : src1;
          else
            cmp_result = (src0[30:0] < src1[30:0]) ? src0 : src1;
        end
        ALU_MAX: begin
          cmp_valid  = 1'b1;
          if (src0[31] && !src1[31])
            cmp_result = src1;
          else if (!src0[31] && src1[31])
            cmp_result = src0;
          else if (src0[31])
            cmp_result = (src0[30:0] < src1[30:0]) ? src0 : src1;
          else
            cmp_result = (src0[30:0] > src1[30:0]) ? src0 : src1;
        end
        ALU_ABS: begin
          cmp_valid  = 1'b1;
          cmp_result = {1'b0, src0[30:0]};
        end
        ALU_NEG: begin
          cmp_valid  = 1'b1;
          cmp_result = {~src0[31], src0[30:0]};
        end
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bypass_valid_pipe  <= '0;
      use_bypass_pipe    <= '0;
    end else begin

      bypass_valid_pipe[0]  <= cmp_valid;
      bypass_result_pipe[0] <= cmp_result;
      bypass_flags_pipe[0]  <= cmp_flags;
      use_bypass_pipe[0]    <= cmp_valid;
      warp_pipe[0]          <= warp_id_in;
      lane_pipe[0]          <= lane_id_in;

      bypass_valid_pipe[1]  <= bypass_valid_pipe[0];
      bypass_result_pipe[1] <= bypass_result_pipe[0];
      bypass_flags_pipe[1]  <= bypass_flags_pipe[0];
      use_bypass_pipe[1]    <= use_bypass_pipe[0];
      warp_pipe[1]          <= warp_pipe[0];
      lane_pipe[1]          <= lane_pipe[0];

      bypass_valid_pipe[2]  <= bypass_valid_pipe[1];
      bypass_result_pipe[2] <= bypass_result_pipe[1];
      bypass_flags_pipe[2]  <= bypass_flags_pipe[1];
      use_bypass_pipe[2]    <= use_bypass_pipe[1];
      warp_pipe[2]          <= warp_pipe[1];
      lane_pipe[2]          <= lane_pipe[1];
    end
  end

  logic [6:0] fma_warp_pipe [0:2];
  logic [4:0] fma_lane_pipe [0:2];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin

    end else begin
      fma_warp_pipe[0] <= warp_id_in;
      fma_lane_pipe[0] <= lane_id_in;
      for (int i = 1; i < 3; i++) begin
        fma_warp_pipe[i] <= fma_warp_pipe[i-1];
        fma_lane_pipe[i] <= fma_lane_pipe[i-1];
      end
    end
  end

  assign valid_out   = fma_valid_out | bypass_valid_pipe[2];
  assign result      = use_bypass_pipe[2] ? bypass_result_pipe[2] : fma_result;
  assign fp_flags    = use_bypass_pipe[2] ? bypass_flags_pipe[2]  : fma_flags;
  assign warp_id_out = use_bypass_pipe[2] ? warp_pipe[2]          : fma_warp_pipe[2];
  assign lane_id_out = use_bypass_pipe[2] ? lane_pipe[2]          : fma_lane_pipe[2];

endmodule : fp32_alu

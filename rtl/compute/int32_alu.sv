`timescale 1ns/1ps

module int32_alu
  import agni_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        valid_in,
  input  alu_op_t     opcode,
  input  logic [31:0] src0,
  input  logic [31:0] src1,
  input  logic [6:0]  warp_id_in,
  input  logic [4:0]  lane_id_in,

  output logic        valid_out,
  output logic [31:0] result,
  output logic        overflow,
  output logic        zero_flag,
  output logic        negative_flag,
  output logic [6:0]  warp_id_out,
  output logic [4:0]  lane_id_out
);

  logic [31:0] alu_result;
  logic        ov, zf, nf;
  logic [4:0]  shamt;
  logic        src0_sign;

  assign shamt    = src1[4:0];
  assign src0_sign = src0[31];
  assign zf       = (alu_result == '0);
  assign nf       = alu_result[31];

  always_comb begin
    alu_result = '0;
    ov = 1'b0;

    case (opcode)
      ALU_ADD: begin
        {ov, alu_result} = {1'b0, src0} + {1'b0, src1};
      end

      ALU_SUB: begin
        {ov, alu_result} = {1'b0, src0} - {1'b0, src1};
      end

      ALU_MUL: begin

        alu_result = src0 * src1;
      end

      ALU_AND: begin
        alu_result = src0 & src1;
      end

      ALU_OR: begin
        alu_result = src0 | src1;
      end

      ALU_XOR: begin
        alu_result = src0 ^ src1;
      end

      ALU_SHL: begin
        alu_result = src0 << shamt;
      end

      ALU_SHR: begin
        alu_result = src0 >> shamt;
      end

      ALU_SHRA: begin
        alu_result = $signed(src0) >>> shamt;
      end

      ALU_CMP_EQ: begin
        alu_result = (src0 == src1) ? 32'hFFFFFFFF : 32'h0;
      end

      ALU_CMP_LT: begin
        alu_result = ($signed(src0) < $signed(src1)) ? 32'hFFFFFFFF : 32'h0;
      end

      ALU_CMP_LE: begin
        alu_result = ($signed(src0) <= $signed(src1)) ? 32'hFFFFFFFF : 32'h0;
      end

      ALU_MIN: begin
        alu_result = ($signed(src0) < $signed(src1)) ? src0 : src1;
      end

      ALU_MAX: begin
        alu_result = ($signed(src0) > $signed(src1)) ? src0 : src1;
      end

      ALU_ABS: begin
        alu_result = src0_sign ? (~src0 + 32'd1) : src0;
      end

      ALU_NEG: begin
        alu_result = ~src0 + 32'd1;
      end

      ALU_MOD: begin

        if (src1 != '0)
          alu_result = src0 % src1;
        else
          alu_result = '0;
      end

      ALU_NOP: begin
        alu_result = src0;
      end

      default: begin
        alu_result = '0;
      end
    endcase

  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_out     <= 1'b0;
      result        <= '0;
      overflow      <= 1'b0;
      zero_flag     <= 1'b0;
      negative_flag <= 1'b0;
      warp_id_out   <= '0;
      lane_id_out   <= '0;
    end else begin
      valid_out     <= valid_in;
      result        <= alu_result;
      overflow      <= ov;
      zero_flag     <= zf;
      negative_flag <= nf;
      warp_id_out   <= warp_id_in;
      lane_id_out   <= lane_id_in;
    end
  end

endmodule : int32_alu

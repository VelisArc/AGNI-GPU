`timescale 1ns/1ps

module sfu
  import agni_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        valid_in,
  input  sfu_op_t     opcode,
  input  logic [31:0] operand,
  input  logic [6:0]  warp_id_in,
  input  logic [4:0]  lane_id_in,

  output logic        valid_out,
  output logic [31:0] result,
  output logic [6:0]  warp_id_out,
  output logic [4:0]  lane_id_out
);

  localparam logic [31:0] FP32_ZERO    = 32'h00000000;
  localparam logic [31:0] FP32_ONE     = 32'h3F800000;
  localparam logic [31:0] FP32_HALF    = 32'h3F000000;
  localparam logic [31:0] FP32_NEG_ONE = 32'hBF800000;

  function automatic logic [31:0] approx_rcp_bits(input logic [31:0] x);
    logic [7:0]  exp_in;
    logic [22:0] man_in;
    exp_in = x[30:23];
    man_in = x[22:0];
    if (exp_in == 8'd0)
      return {x[31], 8'hFF, 23'd0};
    return {x[31], (8'd253 - exp_in), ~man_in};
  endfunction

  function automatic logic [31:0] approx_rsqrt_bits(input logic [31:0] x);
    if (x[31] || (x[30:23] == 8'd0))
      return FP32_ZERO;
    return 32'h5F375A86 - (x >> 1);
  endfunction

  function automatic logic [31:0] approx_sqrt_bits(input logic [31:0] x);
    int signed exp_unbiased;
    int signed exp_half;
    logic [7:0] exp_out;
    logic [22:0] man_out;
    if (x[31] || (x[30:23] == 8'd0))
      return FP32_ZERO;

    exp_unbiased = $signed({1'b0, x[30:23]}) - 127;
    exp_half     = exp_unbiased >>> 1;
    exp_out      = exp_half + 127;
    man_out      = x[22:0] >> 1;
    if (exp_unbiased[0])
      man_out = man_out + 23'h1A827A;
    return {1'b0, exp_out, man_out};
  endfunction

  function automatic logic [31:0] approx_exp_bits(input logic [31:0] x);
    int signed exp_delta;
    int signed exp_scaled;
    int signed exp_raw;
    logic [7:0] exp_out;
    logic [22:0] man_out;
    exp_delta = $signed({1'b0, x[30:23]}) - 127;
    if (x[31])
      exp_scaled = -(exp_delta * 3 >>> 1);
    else
      exp_scaled =  (exp_delta * 3 >>> 1);

    exp_raw = 127 + exp_scaled;
    if (exp_raw < 1)
      exp_out = 8'd1;
    else if (exp_raw > 254)
      exp_out = 8'd254;
    else
      exp_out = exp_raw[7:0];

    man_out = x[22:0] >> 1;
    return {1'b0, exp_out, man_out};
  endfunction

  function automatic logic [31:0] approx_log_bits(input logic [31:0] x);
    logic sign_out;
    logic [7:0] exp_out;
    logic [22:0] man_out;
    if (x[31] || (x[30:23] == 8'd0))
      return 32'hFF800000;
    if (x == FP32_ONE)
      return FP32_ZERO;

    sign_out = (x[30:23] < 8'd127);
    if (sign_out)
      exp_out = 8'd127 + ((8'd127 - x[30:23]) >> 1);
    else
      exp_out = 8'd127 + ((x[30:23] - 8'd127) >> 1);

    man_out = x[22:0] >> 1;
    return {sign_out, exp_out, man_out};
  endfunction

  function automatic logic [31:0] approx_sin_bits(input logic [31:0] x);
    logic [31:0] abs_x;
    abs_x = {1'b0, x[30:0]};
    if (abs_x[30:23] <= 8'd127)
      return x;
    return x[31] ? FP32_NEG_ONE : FP32_ONE;
  endfunction

  function automatic logic [31:0] approx_cos_bits(input logic [31:0] x);
    logic [31:0] abs_x;
    abs_x = {1'b0, x[30:0]};
    if (abs_x[30:23] <= 8'd126)
      return FP32_ONE;
    else if (abs_x[30:23] <= 8'd127)
      return FP32_HALF;
    return FP32_ZERO;
  endfunction

  localparam int unsigned ROM_DEPTH = 256;
  localparam int unsigned ROM_ADDR_W = 8;

  logic [ROM_ADDR_W-1:0] s0_rom_addr;
  logic [15:0]           s0_dx;
  logic                  s0_sign;
  logic [7:0]            s0_exp;
  logic [22:0]           s0_man;

  always @* begin
    s0_sign = operand[31];
    s0_exp  = operand[30:23];
    s0_man  = operand[22:0];

    s0_rom_addr = s0_man[22:15];
    s0_dx       = {s0_man[14:0], 1'b0};
  end

  logic        s1_valid;
  sfu_op_t     s1_opcode;
  logic [31:0] s1_C0;
  logic [15:0] s1_C1;
  logic [15:0] s1_C2;
  logic [15:0] s1_dx;
  logic        s1_sign;
  logic [7:0]  s1_exp;
  logic [6:0]  s1_warp_id;
  logic [4:0]  s1_lane_id;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_valid <= 1'b0;
    end else begin
      s1_valid   <= valid_in;
      s1_opcode  <= opcode;
      s1_dx      <= s0_dx;
      s1_sign    <= s0_sign;
      s1_exp     <= s0_exp;
      s1_warp_id <= warp_id_in;
      s1_lane_id <= lane_id_in;

      case (opcode)
        SFU_SIN: begin
          s1_C0 <= approx_sin_bits(operand);
          s1_C1 <= 16'h0;
          s1_C2 <= 16'h0;
        end
        SFU_COS: begin
          s1_C0 <= approx_cos_bits(operand);
          s1_C1 <= 16'h0;
          s1_C2 <= 16'h0;
        end
        SFU_EXP: begin
          s1_C0 <= approx_exp_bits(operand);
          s1_C1 <= 16'h0;
          s1_C2 <= 16'h0;
        end
        SFU_LOG: begin
          s1_C0 <= approx_log_bits(operand);
          s1_C1 <= 16'h0;
          s1_C2 <= 16'h0;
        end
        SFU_RSQRT: begin
          s1_C0 <= approx_rsqrt_bits(operand);
          s1_C1 <= 16'h0;
          s1_C2 <= 16'h0;
        end
        SFU_SQRT: begin
          s1_C0 <= approx_sqrt_bits(operand);
          s1_C1 <= 16'h0;
          s1_C2 <= 16'h0;
        end
        SFU_RCP: begin
          s1_C0 <= approx_rcp_bits(operand);
          s1_C1 <= 16'h0;
          s1_C2 <= 16'h0;
        end
        default: begin
          s1_C0 <= FP32_ZERO;
          s1_C1 <= 16'h0;
          s1_C2 <= 16'h0;
        end
      endcase
    end
  end

  logic        s2_valid;
  logic [31:0] s2_approx;
  sfu_op_t     s2_opcode;
  logic [31:0] s2_original;
  logic [6:0]  s2_warp_id;
  logic [4:0]  s2_lane_id;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s2_valid <= 1'b0;
    end else begin
      s2_valid    <= s1_valid;
      s2_opcode   <= s1_opcode;
      s2_warp_id  <= s1_warp_id;
      s2_lane_id  <= s1_lane_id;

      s2_approx   <= s1_C0;
    end
  end

  logic        s3_valid;
  logic [31:0] s3_result;
  logic [6:0]  s3_warp_id;
  logic [4:0]  s3_lane_id;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s3_valid <= 1'b0;
    end else begin
      s3_valid    <= s2_valid;
      s3_warp_id  <= s2_warp_id;
      s3_lane_id  <= s2_lane_id;

      s3_result   <= s2_approx;
    end
  end

  assign valid_out   = s3_valid;
  assign result      = s3_result;
  assign warp_id_out = s3_warp_id;
  assign lane_id_out = s3_lane_id;

endmodule : sfu

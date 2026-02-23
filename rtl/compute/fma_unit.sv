`timescale 1ns/1ps

module fma_unit (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        valid_in,
  input  logic [31:0] operand_a,
  input  logic [31:0] operand_b,
  input  logic [31:0] operand_c,
  input  logic [1:0]  rounding_mode,

  output logic        valid_out,
  output logic [31:0] result,
  output logic [4:0]  flags
);

  localparam int unsigned EXP_W  = 8;
  localparam int unsigned MAN_W  = 23;
  localparam int unsigned BIAS   = 127;

  logic        s0_sign_a, s0_sign_b, s0_sign_c;
  logic [EXP_W-1:0]  s0_exp_a, s0_exp_b, s0_exp_c;
  logic [MAN_W:0]    s0_man_a, s0_man_b, s0_man_c;
  logic        s0_a_is_zero, s0_b_is_zero, s0_c_is_zero;
  logic        s0_a_is_inf, s0_b_is_inf, s0_c_is_inf;
  logic        s0_a_is_nan, s0_b_is_nan, s0_c_is_nan;

  always @* begin
    s0_sign_a = operand_a[31];
    s0_sign_b = operand_b[31];
    s0_sign_c = operand_c[31];

    s0_exp_a  = operand_a[30:23];
    s0_exp_b  = operand_b[30:23];
    s0_exp_c  = operand_c[30:23];

    s0_man_a  = {|s0_exp_a, operand_a[22:0]};
    s0_man_b  = {|s0_exp_b, operand_b[22:0]};
    s0_man_c  = {|s0_exp_c, operand_c[22:0]};

    s0_a_is_zero = (s0_exp_a == '0) && (operand_a[22:0] == '0);
    s0_b_is_zero = (s0_exp_b == '0) && (operand_b[22:0] == '0);
    s0_c_is_zero = (s0_exp_c == '0) && (operand_c[22:0] == '0);

    s0_a_is_inf  = (s0_exp_a == 8'hFF) && (operand_a[22:0] == '0);
    s0_b_is_inf  = (s0_exp_b == 8'hFF) && (operand_b[22:0] == '0);
    s0_c_is_inf  = (s0_exp_c == 8'hFF) && (operand_c[22:0] == '0);

    s0_a_is_nan  = (s0_exp_a == 8'hFF) && (operand_a[22:0] != '0);
    s0_b_is_nan  = (s0_exp_b == 8'hFF) && (operand_b[22:0] != '0);
    s0_c_is_nan  = (s0_exp_c == 8'hFF) && (operand_c[22:0] != '0);
  end

  logic               s1_valid;
  logic               s1_prod_sign;
  logic [9:0]         s1_prod_exp;
  logic [47:0]        s1_prod_man;
  logic               s1_add_sign;
  logic [9:0]         s1_add_exp;
  logic [MAN_W:0]     s1_add_man;
  logic               s1_is_special;
  logic [31:0]        s1_special_result;
  logic [4:0]         s1_special_flags;
  logic [1:0]         s1_rmode;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_valid <= 1'b0;
    end else begin
      s1_valid     <= valid_in;
      s1_rmode     <= rounding_mode;
      s1_prod_sign <= s0_sign_a ^ s0_sign_b;
      s1_prod_exp  <= {2'b0, s0_exp_a} + {2'b0, s0_exp_b} - 10'd127;
      s1_prod_man  <= s0_man_a * s0_man_b;
      s1_add_sign  <= s0_sign_c;
      s1_add_exp   <= {2'b0, s0_exp_c};
      s1_add_man   <= s0_man_c;

      if (s0_a_is_nan || s0_b_is_nan || s0_c_is_nan) begin
        s1_is_special     <= 1'b1;
        s1_special_result <= 32'h7FC00000;
        s1_special_flags  <= 5'b10000;
      end else if ((s0_a_is_inf && s0_b_is_zero) || (s0_b_is_inf && s0_a_is_zero)) begin
        s1_is_special     <= 1'b1;
        s1_special_result <= 32'h7FC00000;
        s1_special_flags  <= 5'b10000;
      end else if (s0_a_is_inf || s0_b_is_inf) begin
        s1_is_special     <= 1'b1;
        s1_special_result <= {s0_sign_a ^ s0_sign_b, 8'hFF, 23'b0};
        s1_special_flags  <= 5'b0;
      end else if (s0_c_is_inf) begin
        s1_is_special     <= 1'b1;
        s1_special_result <= operand_c;
        s1_special_flags  <= 5'b0;
      end else begin
        s1_is_special     <= 1'b0;
        s1_special_result <= '0;
        s1_special_flags  <= '0;
      end
    end
  end

  logic          s2_valid;
  logic          s2_result_sign;
  logic [9:0]    s2_result_exp;
  logic [49:0]   s2_result_man;
  logic          s2_is_special;
  logic [31:0]   s2_special_result;
  logic [4:0]    s2_special_flags;
  logic [1:0]    s2_rmode;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s2_valid <= 1'b0;
    end else begin
      s2_valid           <= s1_valid;
      s2_is_special      <= s1_is_special;
      s2_special_result  <= s1_special_result;
      s2_special_flags   <= s1_special_flags;
      s2_rmode           <= s1_rmode;

      if (!s1_is_special) begin

        logic signed [10:0] exp_diff;
        logic [49:0] aligned_c;
        logic [49:0] product_ext;

        exp_diff    = $signed({1'b0, s1_prod_exp}) - $signed({1'b0, s1_add_exp});
        product_ext = {1'b0, s1_prod_man, 1'b0};

        if (exp_diff >= 0) begin
          aligned_c = {1'b0, s1_add_man, 25'b0} >> exp_diff;
          s2_result_exp <= s1_prod_exp;
        end else begin
          aligned_c     = {1'b0, s1_add_man, 25'b0};
          product_ext   = product_ext >> (-exp_diff);
          s2_result_exp <= s1_add_exp;
        end

        if (s1_prod_sign == s1_add_sign) begin
          s2_result_man  <= product_ext + aligned_c;
          s2_result_sign <= s1_prod_sign;
        end else begin
          if (product_ext >= aligned_c) begin
            s2_result_man  <= product_ext - aligned_c;
            s2_result_sign <= s1_prod_sign;
          end else begin
            s2_result_man  <= aligned_c - product_ext;
            s2_result_sign <= s1_add_sign;
          end
        end
      end
    end
  end

  logic [31:0] s3_result;
  logic [4:0]  s3_flags;
  logic        s3_valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s3_valid <= 1'b0;
    end else begin
      s3_valid <= s2_valid;

      if (s2_is_special) begin
        s3_result <= s2_special_result;
        s3_flags  <= s2_special_flags;
      end else if (s2_result_man == '0) begin

        s3_result <= {s2_result_sign, 31'b0};
        s3_flags  <= 5'b0;
      end else begin

        logic [5:0]  lzc;
        logic [49:0] norm_man;
        logic [9:0]  norm_exp;
        logic [22:0] final_man;
        logic [7:0]  final_exp;

        lzc = '0;
        begin : lzc_loop
          logic lzc_found;
          lzc_found = 1'b0;
          for (int i = 49; i >= 0; i--) begin
            if (s2_result_man[i] && !lzc_found) begin
              lzc = 49 - i;
              lzc_found = 1'b1;
            end
          end
        end

        norm_man = s2_result_man << lzc;
        norm_exp = s2_result_exp - {4'b0, lzc} + 10'd25;

        final_man = norm_man[48:26];
        if (norm_man[25] && (norm_man[26] || |norm_man[24:0])) begin
          {final_exp, final_man} = {norm_exp[7:0], norm_man[48:26]} + 1'b1;
        end else begin
          final_exp = norm_exp[7:0];
        end

        if (norm_exp >= 10'd255) begin
          s3_result <= {s2_result_sign, 8'hFF, 23'b0};
          s3_flags  <= 5'b01100;
        end else if (norm_exp <= 10'd0) begin
          s3_result <= {s2_result_sign, 31'b0};
          s3_flags  <= 5'b00110;
        end else begin
          s3_result <= {s2_result_sign, final_exp, final_man};
          s3_flags  <= (|norm_man[25:0]) ? 5'b00010 : 5'b0;
        end
      end
    end
  end

  assign valid_out = s3_valid;
  assign result    = s3_result;
  assign flags     = s3_flags;

endmodule : fma_unit

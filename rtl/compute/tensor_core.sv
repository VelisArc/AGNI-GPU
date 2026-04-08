`timescale 1ns/1ps

module tensor_core
  import agni_pkg::*;
#(

  parameter int unsigned TILE_M = 16,
  parameter int unsigned TILE_N = 16,
  parameter int unsigned TILE_K = 16
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        valid_in,
  input  tc_op_t      opcode,
  input  precision_t  precision,

  input  logic [15:0] mat_a [0:TILE_M-1][0:TILE_K-1],

  input  logic [15:0] mat_b [0:TILE_K-1][0:TILE_N-1],

  input  logic [31:0] mat_c [0:TILE_M-1][0:TILE_N-1],

  output logic        valid_out,
  output logic [31:0] mat_d [0:TILE_M-1][0:TILE_N-1]
);

  logic [31:0] accum [0:TILE_M-1][0:TILE_N-1];
  logic [$clog2(TILE_K):0] k_counter;

  function automatic logic [31:0] fp16_mul_to_fp32(
    input logic [15:0] a,
    input logic [15:0] b
  );
    logic        sign;
    logic [4:0]  exp_a, exp_b;
    logic [10:0] man_a, man_b;
    logic [21:0] product;
    logic [8:0]  result_exp;
    logic [22:0] result_man;

    sign  = a[15] ^ b[15];
    exp_a = a[14:10];
    exp_b = b[14:10];

    if ((exp_a == 5'd0) || (exp_b == 5'd0))
      return 32'h00000000;

    man_a = {1'b1, a[9:0]};
    man_b = {1'b1, b[9:0]};

    product = man_a * man_b;

    if (product == '0) begin
      return 32'h00000000;
    end else begin
      result_exp = {4'b0, exp_a} + {4'b0, exp_b} - 9'd30 + 9'd127;
      if (product[21]) begin
        result_man = {product[20:0], 2'b0};
        result_exp = result_exp + 1'b1;
      end else begin
        result_man = {product[19:0], 3'b0};
      end
      return {sign, result_exp[7:0], result_man};
    end
  endfunction

  function automatic logic [31:0] fp32_add(
    input logic [31:0] a,
    input logic [31:0] b
  );

    logic        sign_a, sign_b, sign_r;
    logic [7:0]  exp_a, exp_b, exp_r;
    logic [23:0] man_a, man_b;
    logic [24:0] sum;
    logic signed [8:0] exp_diff;

    if (a == 32'h0) return b;
    if (b == 32'h0) return a;

    sign_a = a[31]; exp_a = a[30:23]; man_a = {1'b1, a[22:0]};
    sign_b = b[31]; exp_b = b[30:23]; man_b = {1'b1, b[22:0]};

    exp_diff = $signed({1'b0, exp_a}) - $signed({1'b0, exp_b});
    if (exp_diff < 0) begin
      man_a = man_a >> (-exp_diff);
      exp_r = exp_b;
    end else begin
      man_b = man_b >> exp_diff;
      exp_r = exp_a;
    end

    if (sign_a == sign_b) begin
      sum    = {1'b0, man_a} + {1'b0, man_b};
      sign_r = sign_a;
    end else begin
      if (man_a >= man_b) begin
        sum    = {1'b0, man_a} - {1'b0, man_b};
        sign_r = sign_a;
      end else begin
        sum    = {1'b0, man_b} - {1'b0, man_a};
        sign_r = sign_b;
      end
    end

    if (sum[24]) begin
      exp_r = exp_r + 1'b1;
      return {sign_r, exp_r, sum[23:1]};
    end else if (sum == '0) begin
      return 32'h0;
    end else begin
      return {sign_r, exp_r, sum[22:0]};
    end
  endfunction

  typedef enum logic [1:0] {
    TC_IDLE    = 2'b00,
    TC_COMPUTE = 2'b01,
    TC_OUTPUT  = 2'b10
  } tc_state_t;

  tc_state_t state, state_next;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      state <= TC_IDLE;
    else
      state <= state_next;
  end

  always_comb begin
    state_next = state;
    case (state)
      TC_IDLE: begin
        if (valid_in && opcode == TC_MMA)
          state_next = TC_COMPUTE;
      end
      TC_COMPUTE: begin
        if (k_counter == TILE_K)
          state_next = TC_OUTPUT;
      end
      TC_OUTPUT: begin
        state_next = TC_IDLE;
      end
      default: state_next = TC_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      k_counter <= '0;
    end else begin
      case (state)
        TC_IDLE:    k_counter <= '0;
        TC_COMPUTE: begin
          if (k_counter < TILE_K)
            k_counter <= k_counter + 1'b1;
        end
        TC_OUTPUT:  k_counter <= '0;
        default:    k_counter <= '0;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int m = 0; m < TILE_M; m++) begin
        for (int n = 0; n < TILE_N; n++) begin
          accum[m][n] <= '0;
        end
      end
    end else begin
      case (state)
        TC_IDLE: begin

          if (valid_in && opcode == TC_MMA) begin
            for (int m = 0; m < TILE_M; m++)
              for (int n = 0; n < TILE_N; n++)
                accum[m][n] <= mat_c[m][n];
          end
        end

        TC_COMPUTE: begin

          if (k_counter < TILE_K) begin
            for (int m = 0; m < TILE_M; m++) begin
              for (int n = 0; n < TILE_N; n++) begin
                accum[m][n] <= fp32_add(
                  accum[m][n],
                  fp16_mul_to_fp32(
                    mat_a[m][k_counter[$clog2(TILE_K)-1:0]],
                    mat_b[k_counter[$clog2(TILE_K)-1:0]][n]
                  )
                );
              end
            end
          end
        end

        default: ;
      endcase
    end
  end

  assign valid_out = (state == TC_OUTPUT);

  genvar gm, gn;
  generate
    for (gm = 0; gm < TILE_M; gm++) begin : g_out_m
      for (gn = 0; gn < TILE_N; gn++) begin : g_out_n
        assign mat_d[gm][gn] = accum[gm][gn];
      end
    end
  endgenerate

  int unsigned mma_count;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      mma_count <= 0;
    else if (state == TC_OUTPUT)
      mma_count <= mma_count + 1;
  end

endmodule : tensor_core

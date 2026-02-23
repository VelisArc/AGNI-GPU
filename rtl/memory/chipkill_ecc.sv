`timescale 1ns/1ps

module chipkill_ecc
  import agni_pkg::*;
#(
  parameter int unsigned DATA_W   = 256,
  parameter int unsigned SYMBOL_W = 32,
  parameter int unsigned SYMBOLS  = DATA_W / SYMBOL_W,
  parameter int unsigned REDUND   = 2,
  localparam int unsigned CODE_W  = DATA_W + (REDUND * SYMBOL_W)
)(
  input  logic             clk,
  input  logic             rst_n,

  input  logic             enc_valid,
  input  logic [DATA_W-1:0] enc_data_in,
  output logic [CODE_W-1:0] enc_code_out,
  output logic             enc_done,

  input  logic             dec_valid,
  input  logic [CODE_W-1:0] dec_code_in,
  output logic [DATA_W-1:0] dec_data_out,
  output ecc_error_t       dec_error,
  output logic [3:0]       dec_failed_symbol,
  output logic             dec_done
);

  localparam int unsigned TOTAL_SYMBOLS = SYMBOLS + REDUND;

  localparam logic [32:0] GF_POLY = 33'h10000008D;

  function automatic logic [31:0] gf_mul(
    input logic [31:0] a,
    input logic [31:0] b
  );
    logic [63:0] product;
    product = 64'b0;
    for (int i = 0; i < 32; i++) begin
      if (b[i])
        product ^= ({32'b0, a} << i);
    end

    for (int i = 63; i >= 32; i--) begin
      if (product[i])
        product ^= (GF_POLY << (i - 32));
    end
    return product[31:0];
  endfunction

  function automatic logic [31:0] gf_add(
    input logic [31:0] a,
    input logic [31:0] b
  );
    return a ^ b;
  endfunction

  logic [SYMBOL_W-1:0] data_symbols [0:SYMBOLS-1];
  logic [SYMBOL_W-1:0] parity_0, parity_1;

  always @* begin

    for (int i = 0; i < SYMBOLS; i++)
      data_symbols[i] = enc_data_in[i*SYMBOL_W +: SYMBOL_W];

    parity_0 = '0;
    parity_1 = '0;

    for (int i = 0; i < SYMBOLS; i++) begin

      parity_0 = gf_add(parity_0, data_symbols[i]);

      parity_1 = gf_add(parity_1, {data_symbols[i][30:0], data_symbols[i][31]});
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      enc_done <= 1'b0;
    end else begin
      enc_done <= enc_valid;
      if (enc_valid)
        enc_code_out <= {parity_1, parity_0, enc_data_in};
    end
  end

  logic [SYMBOL_W-1:0] rx_symbols [0:TOTAL_SYMBOLS-1];
  logic [SYMBOL_W-1:0] syndrome_0, syndrome_1;
  logic                has_error;
  logic [3:0]          error_loc;
  logic [SYMBOL_W-1:0] error_val;

  always @* begin

    for (int i = 0; i < TOTAL_SYMBOLS; i++)
      rx_symbols[i] = dec_code_in[i*SYMBOL_W +: SYMBOL_W];

    syndrome_0 = '0;
    syndrome_1 = '0;

    for (int i = 0; i < TOTAL_SYMBOLS; i++) begin
      syndrome_0 = gf_add(syndrome_0, rx_symbols[i]);
      syndrome_1 = gf_add(syndrome_1, {rx_symbols[i][30:0], rx_symbols[i][31]});
    end

    has_error = |syndrome_0 || |syndrome_1;

    error_loc = 4'b0;
    error_val = syndrome_0;

    if (has_error) begin

      for (int i = 0; i < TOTAL_SYMBOLS; i++) begin
        logic [SYMBOL_W-1:0] test_s0, test_s1;
        test_s0 = '0;
        test_s1 = '0;
        for (int j = 0; j < TOTAL_SYMBOLS; j++) begin
          if (j != i) begin
            test_s0 = gf_add(test_s0, rx_symbols[j]);
            test_s1 = gf_add(test_s1, {rx_symbols[j][30:0], rx_symbols[j][31]});
          end
        end

      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dec_done  <= 1'b0;
      dec_error <= ECC_NONE;
    end else begin
      dec_done <= dec_valid;
      if (dec_valid) begin
        if (!has_error) begin
          dec_data_out     <= dec_code_in[DATA_W-1:0];
          dec_error        <= ECC_NONE;
          dec_failed_symbol <= 4'b0;
        end else begin

          logic [DATA_W-1:0] corrected;
          corrected = dec_code_in[DATA_W-1:0];
          if (error_loc < SYMBOLS) begin
            corrected[error_loc*SYMBOL_W +: SYMBOL_W] =
              gf_add(rx_symbols[error_loc], error_val);
          end
          dec_data_out      <= corrected;
          dec_error         <= ECC_CORRECTED;
          dec_failed_symbol <= error_loc;
        end
      end
    end
  end

endmodule : chipkill_ecc

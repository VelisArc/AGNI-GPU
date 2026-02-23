`timescale 1ns/1ps

module register_file
  import agni_pkg::*;
#(
  parameter int unsigned NUM_BANKS  = 32,
  parameter int unsigned REGS_TOTAL = 65536,
  parameter int unsigned REG_WIDTH  = 32,
  parameter int unsigned RD_PORTS   = 4,
  parameter int unsigned WR_PORTS   = 2,
  localparam int unsigned REGS_PER_BANK = REGS_TOTAL / NUM_BANKS,
  localparam int unsigned BANK_ADDR_W   = $clog2(REGS_PER_BANK),
  localparam int unsigned BANK_SEL_W    = $clog2(NUM_BANKS),
  localparam int unsigned ADDR_W        = $clog2(REGS_TOTAL)
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic [RD_PORTS-1:0]              rd_en,
  input  logic [ADDR_W-1:0]               rd_addr [RD_PORTS],
  output logic [REG_WIDTH-1:0]            rd_data [RD_PORTS],
  output logic [RD_PORTS-1:0]              rd_valid,

  input  logic [WR_PORTS-1:0]              wr_en,
  input  logic [ADDR_W-1:0]               wr_addr [WR_PORTS],
  input  logic [REG_WIDTH-1:0]            wr_data [WR_PORTS],

  output logic                             ecc_ce_flag,
  output logic                             ecc_ue_flag
);

  function automatic logic [BANK_SEL_W-1:0] get_bank(input logic [ADDR_W-1:0] addr);
    return addr[BANK_SEL_W-1:0];
  endfunction

  function automatic logic [BANK_ADDR_W-1:0] get_offset(input logic [ADDR_W-1:0] addr);
    return addr[ADDR_W-1:BANK_SEL_W];
  endfunction

  logic [NUM_BANKS-1:0]           bank_en;
  logic [NUM_BANKS-1:0]           bank_we;
  logic [BANK_ADDR_W-1:0]        bank_addr   [NUM_BANKS];
  logic [REG_WIDTH-1:0]          bank_wdata  [NUM_BANKS];
  logic [REG_WIDTH-1:0]          bank_rdata  [NUM_BANKS];
  logic [NUM_BANKS-1:0]           bank_ecc_ce;
  logic [NUM_BANKS-1:0]           bank_ecc_ue;

  genvar gi;
  generate
    for (gi = 0; gi < NUM_BANKS; gi++) begin : g_bank
      ram_sp #(
        .WIDTH  (REG_WIDTH),
        .DEPTH  (REGS_PER_BANK),
        .ECC_EN (1'b1)
      ) u_bank (
        .clk       (clk),
        .en        (bank_en[gi]),
        .we        (bank_we[gi]),
        .addr      (bank_addr[gi]),
        .wdata     (bank_wdata[gi]),
        .rdata     (bank_rdata[gi]),
        .ecc_error (bank_ecc_ce[gi]),
        .ecc_ue    (bank_ecc_ue[gi])
      );
    end
  endgenerate

  logic [NUM_BANKS-1:0] bank_busy;

  always @* begin

    bank_en    = '0;
    bank_we    = '0;
    bank_busy  = '0;
    for (int b = 0; b < NUM_BANKS; b++) begin
      bank_addr[b]  = '0;
      bank_wdata[b] = '0;
    end
    for (int r = 0; r < RD_PORTS; r++) begin
      rd_data[r]  = '0;
      rd_valid[r] = 1'b0;
    end

    for (int w = 0; w < WR_PORTS; w++) begin
      if (wr_en[w]) begin
        logic [BANK_SEL_W-1:0] b;
        b = get_bank(wr_addr[w]);
        if (!bank_busy[b]) begin
          bank_en[b]    = 1'b1;
          bank_we[b]    = 1'b1;
          bank_addr[b]  = get_offset(wr_addr[w]);
          bank_wdata[b] = wr_data[w];
          bank_busy[b]  = 1'b1;
        end
      end
    end

    for (int r = 0; r < RD_PORTS; r++) begin
      if (rd_en[r]) begin
        logic [BANK_SEL_W-1:0] b;
        b = get_bank(rd_addr[r]);
        if (!bank_busy[b]) begin
          bank_en[b]    = 1'b1;
          bank_addr[b]  = get_offset(rd_addr[r]);
          bank_busy[b]  = 1'b1;
          rd_valid[r]   = 1'b1;
        end

      end
    end
  end

  always_ff @(posedge clk) begin
    for (int r = 0; r < RD_PORTS; r++) begin
      if (rd_en[r]) begin
        rd_data[r] <= bank_rdata[get_bank(rd_addr[r])];
      end
    end
  end

  assign ecc_ce_flag = |bank_ecc_ce;
  assign ecc_ue_flag = |bank_ecc_ue;

  always @(posedge clk) begin
    if (rst_n && ecc_ue_flag)
      $error("REGFILE: Uncorrectable ECC error detected!");
    if (rst_n && ecc_ce_flag)
      $warning("REGFILE: Correctable ECC error — bit flipped and corrected");
  end

endmodule : register_file

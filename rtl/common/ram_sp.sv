`timescale 1ns/1ps

module ram_sp #(
  parameter int unsigned WIDTH   = 32,
  parameter int unsigned DEPTH   = 1024,
  parameter bit          ECC_EN  = 1'b0,
  localparam int unsigned ADDR_W = $clog2(DEPTH)
)(
  input  logic              clk,
  input  logic              en,
  input  logic              we,
  input  logic [ADDR_W-1:0] addr,
  input  logic [WIDTH-1:0]  wdata,
  output logic [WIDTH-1:0]  rdata,
  output logic              ecc_error,
  output logic              ecc_ue
);

  localparam int unsigned PARITY_BITS = ECC_EN ? ($clog2(WIDTH) + 2) : 0;
  localparam int unsigned STORE_WIDTH = WIDTH + PARITY_BITS;

  logic [STORE_WIDTH-1:0] mem [0:DEPTH-1];

  logic [STORE_WIDTH-1:0] encoded_data;
  logic [STORE_WIDTH-1:0] raw_read = '0;
  logic [WIDTH-1:0]       decoded_data;
  logic                   ecc_ce, ecc_ue_int;

  generate
    if (ECC_EN) begin : g_ecc

      always @* begin
        encoded_data[WIDTH-1:0] = wdata;

        encoded_data[WIDTH]     = ^wdata;
        encoded_data[WIDTH+1]   = ^wdata[15:0];
        encoded_data[WIDTH+2]   = ^wdata[23:8];
        encoded_data[WIDTH+3]   = ^wdata[31:16];
        encoded_data[WIDTH+4]   = ^wdata[7:0] ^ ^wdata[23:16];
        encoded_data[WIDTH+5]   = ^wdata[3:0] ^ ^wdata[11:8] ^ ^wdata[19:16] ^ ^wdata[27:24];
        if (PARITY_BITS > 6)
          encoded_data[WIDTH+6] = 1'b0;
      end

      always @* begin
        logic [PARITY_BITS-1:0] syndrome;
        syndrome = '0;
        syndrome[0] = ^raw_read[WIDTH+1] ^ ^raw_read[15:0];
        syndrome[1] = ^raw_read[WIDTH+2] ^ ^raw_read[23:8];
        syndrome[2] = ^raw_read[WIDTH+3] ^ ^raw_read[31:16];
        syndrome[3] = ^raw_read[WIDTH+4] ^ ^raw_read[7:0] ^ ^raw_read[23:16];
        syndrome[4] = ^raw_read[WIDTH+5] ^ ^raw_read[3:0] ^ ^raw_read[11:8] ^
                       ^raw_read[19:16] ^ ^raw_read[27:24];
        syndrome[5] = ^raw_read;

        decoded_data = raw_read[WIDTH-1:0];
        ecc_ce       = 1'b0;
        ecc_ue_int   = 1'b0;

        if (^raw_read === 1'bx) begin
          decoded_data = '0;
        end else if (|syndrome[PARITY_BITS-2:0]) begin
          if (syndrome[5]) begin

            ecc_ce = 1'b1;
            for (int b = 0; b < WIDTH; b++) begin
              if (b[PARITY_BITS-2:0] == syndrome[PARITY_BITS-2:0])
                decoded_data[b] = ~raw_read[b];
            end
          end else begin

            ecc_ue_int = 1'b1;
          end
        end
      end
    end else begin : g_no_ecc
      assign encoded_data = wdata;
      assign decoded_data = raw_read[WIDTH-1:0];
      assign ecc_ce       = 1'b0;
      assign ecc_ue_int   = 1'b0;
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (en) begin
      if (we) begin
        mem[addr] <= encoded_data;
      end
      raw_read <= mem[addr];
    end
  end

  assign rdata     = decoded_data;
  assign ecc_error = ECC_EN ? ecc_ce : 1'b0;
  assign ecc_ue    = ECC_EN ? ecc_ue_int : 1'b0;

endmodule : ram_sp

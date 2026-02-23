`timescale 1ns/1ps

module noc_mesh
  import agni_pkg::*;
#(
  parameter int unsigned ROWS = NOC_MESH_ROWS,
  parameter int unsigned COLS = NOC_MESH_COLS,
  parameter int unsigned FLIT_W = NOC_FLIT_WIDTH
)(
  input  logic clk,
  input  logic rst_n,

  input  logic [ROWS*COLS-1:0]       local_valid_in,
  input  logic [FLIT_W-1:0]          local_flit_in  [ROWS*COLS],
  output logic [ROWS*COLS-1:0]       local_valid_out,
  output logic [FLIT_W-1:0]          local_flit_out [ROWS*COLS]
);

  logic [ROWS*COLS-1:0] ns_valid, sn_valid;
  logic [FLIT_W-1:0]   ns_flit [ROWS*COLS];
  logic [FLIT_W-1:0]   sn_flit [ROWS*COLS];
  logic [ROWS*COLS-1:0] ns_credit, sn_credit;

  logic [ROWS*COLS-1:0] ew_valid, we_valid;
  logic [FLIT_W-1:0]   ew_flit [ROWS*COLS];
  logic [FLIT_W-1:0]   we_flit [ROWS*COLS];
  logic [ROWS*COLS-1:0] ew_credit, we_credit;

  genvar gr, gc;
  generate
    for (gr = 0; gr < ROWS; gr++) begin : g_row
      for (gc = 0; gc < COLS; gc++) begin : g_col
        localparam int unsigned IDX = gr * COLS + gc;

        logic [4:0]  r_valid_in, r_valid_out;
        logic [FLIT_W-1:0] r_flit_in_0, r_flit_in_1, r_flit_in_2, r_flit_in_3, r_flit_in_4;
        logic [FLIT_W-1:0] r_flit_out_0, r_flit_out_1, r_flit_out_2, r_flit_out_3, r_flit_out_4;
        logic [4:0]  r_credit_in, r_credit_out;

        noc_router #(
          .ROUTER_ID (IDX),
          .ROUTER_X  (gc),
          .ROUTER_Y  (gr),
          .MESH_COLS (COLS),
          .MESH_ROWS (ROWS)
        ) u_router (
          .clk             (clk),
          .rst_n           (rst_n),
          .port_valid_in   (r_valid_in),
          .port_flit_in_0  (r_flit_in_0),
          .port_flit_in_1  (r_flit_in_1),
          .port_flit_in_2  (r_flit_in_2),
          .port_flit_in_3  (r_flit_in_3),
          .port_flit_in_4  (r_flit_in_4),
          .port_valid_out  (r_valid_out),
          .port_flit_out_0 (r_flit_out_0),
          .port_flit_out_1 (r_flit_out_1),
          .port_flit_out_2 (r_flit_out_2),
          .port_flit_out_3 (r_flit_out_3),
          .port_flit_out_4 (r_flit_out_4),
          .credit_in       (r_credit_in),
          .credit_out      (r_credit_out)
        );

        assign r_valid_in[4]        = local_valid_in[IDX];
        assign r_flit_in_4          = local_flit_in[IDX];
        assign local_valid_out[IDX] = r_valid_out[4];
        assign local_flit_out[IDX]  = r_flit_out_4;

        if (gr > 0) begin : g_north_conn
          assign r_valid_in[0] = sn_valid[(gr-1)*COLS + gc];
          assign r_flit_in_0   = sn_flit[(gr-1)*COLS + gc];
          assign ns_valid[IDX] = r_valid_out[0];
          assign ns_flit[IDX]  = r_flit_out_0;
        end else begin : g_north_term
          assign r_valid_in[0] = 1'b0;
          assign r_flit_in_0   = '0;
        end

        if (gr < ROWS - 1) begin : g_south_conn
          assign r_valid_in[1] = ns_valid[(gr+1)*COLS + gc];
          assign r_flit_in_1   = ns_flit[(gr+1)*COLS + gc];
          assign sn_valid[IDX] = r_valid_out[1];
          assign sn_flit[IDX]  = r_flit_out_1;
        end else begin : g_south_term
          assign r_valid_in[1] = 1'b0;
          assign r_flit_in_1   = '0;
        end

        if (gc < COLS - 1) begin : g_east_conn
          assign r_valid_in[2]  = we_valid[gr*COLS + gc + 1];
          assign r_flit_in_2    = we_flit[gr*COLS + gc + 1];
          assign ew_valid[IDX]  = r_valid_out[2];
          assign ew_flit[IDX]   = r_flit_out_2;
        end else begin : g_east_term
          assign r_valid_in[2] = 1'b0;
          assign r_flit_in_2   = '0;
        end

        if (gc > 0) begin : g_west_conn
          assign r_valid_in[3]  = ew_valid[gr*COLS + gc - 1];
          assign r_flit_in_3    = ew_flit[gr*COLS + gc - 1];
          assign we_valid[IDX]  = r_valid_out[3];
          assign we_flit[IDX]   = r_flit_out_3;
        end else begin : g_west_term
          assign r_valid_in[3] = 1'b0;
          assign r_flit_in_3   = '0;
        end

        assign r_credit_in = 5'b11111;

      end
    end
  endgenerate

endmodule : noc_mesh

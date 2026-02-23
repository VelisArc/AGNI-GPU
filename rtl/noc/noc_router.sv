`timescale 1ns/1ps

module noc_router
  import agni_pkg::*;
#(
  parameter int unsigned ROUTER_ID   = 0,
  parameter int unsigned ROUTER_X    = 0,
  parameter int unsigned ROUTER_Y    = 0,
  parameter int unsigned MESH_COLS   = 8,
  parameter int unsigned MESH_ROWS   = 4,
  parameter int unsigned FLIT_W      = NOC_FLIT_WIDTH,
  parameter int unsigned NUM_VC      = NOC_VC_COUNT,
  parameter int unsigned BUF_DEPTH   = 8
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic [4:0]         port_valid_in,
  input  logic [FLIT_W-1:0]  port_flit_in_0,
  input  logic [FLIT_W-1:0]  port_flit_in_1,
  input  logic [FLIT_W-1:0]  port_flit_in_2,
  input  logic [FLIT_W-1:0]  port_flit_in_3,
  input  logic [FLIT_W-1:0]  port_flit_in_4,

  output logic [4:0]         port_valid_out,
  output logic [FLIT_W-1:0]  port_flit_out_0,
  output logic [FLIT_W-1:0]  port_flit_out_1,
  output logic [FLIT_W-1:0]  port_flit_out_2,
  output logic [FLIT_W-1:0]  port_flit_out_3,
  output logic [FLIT_W-1:0]  port_flit_out_4,

  output logic [4:0]         credit_out,
  input  logic [4:0]         credit_in
);

  localparam int unsigned NORTH = 0;
  localparam int unsigned SOUTH = 1;
  localparam int unsigned EAST  = 2;
  localparam int unsigned WEST  = 3;
  localparam int unsigned LOCAL = 4;

  logic [FLIT_W-1:0] flit_in [5];
  assign flit_in[0] = port_flit_in_0;
  assign flit_in[1] = port_flit_in_1;
  assign flit_in[2] = port_flit_in_2;
  assign flit_in[3] = port_flit_in_3;
  assign flit_in[4] = port_flit_in_4;

  localparam int unsigned STRUCT_W = $bits(noc_flit_t);

  logic [1:0]  in_flit_type [5];
  logic [3:0]  in_src_id    [5];
  logic [3:0]  in_dst_id    [5];
  logic [1:0]  in_vc_id     [5];

  genvar gi;
  generate
    for (gi = 0; gi < 5; gi++) begin : g_decode_in
      assign in_flit_type[gi] = flit_in[gi][FLIT_W-1  -: 2];
      assign in_src_id[gi]    = flit_in[gi][FLIT_W-3  -: 4];
      assign in_dst_id[gi]    = flit_in[gi][FLIT_W-7  -: 4];
      assign in_vc_id[gi]     = flit_in[gi][FLIT_W-11 -: 2];
    end
  endgenerate

  logic [FLIT_W-1:0] vcb_data [0:4][0:NUM_VC-1][0:BUF_DEPTH-1];

  logic [$clog2(BUF_DEPTH)-1:0] vc_head  [0:4][0:NUM_VC-1];
  logic [$clog2(BUF_DEPTH)-1:0] vc_tail  [0:4][0:NUM_VC-1];
  logic [$clog2(BUF_DEPTH):0]   vc_count [0:4][0:NUM_VC-1];

  function automatic logic [2:0] route_xy(input logic [3:0] dst_id);
    logic [3:0] dst_x, dst_y;
    dst_x = dst_id % MESH_COLS;
    dst_y = dst_id / MESH_COLS;

    if (dst_x == ROUTER_X && dst_y == ROUTER_Y) return LOCAL;
    if (dst_x > ROUTER_X) return EAST;
    if (dst_x < ROUTER_X) return WEST;
    if (dst_y > ROUTER_Y) return SOUTH;
    return NORTH;
  endfunction

  genvar gp, gv;
  generate
    for (gp = 0; gp < 5; gp++) begin : gen_port_buf
      for (gv = 0; gv < NUM_VC; gv++) begin : gen_vc_buf
        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            vc_head[gp][gv]  <= '0;
            vc_tail[gp][gv]  <= '0;
            vc_count[gp][gv] <= '0;
          end else begin
            if (gv == 0 && credit_out[gp] && vc_count[gp][gv] > 0) begin
              vc_head[gp][gv] <= vc_head[gp][gv] + 1'b1;
            end

            if (port_valid_in[gp] && in_vc_id[gp] == gv && vc_count[gp][gv] < BUF_DEPTH) begin
              vcb_data[gp][gv][vc_tail[gp][gv]] <= flit_in[gp];
              vc_tail[gp][gv] <= vc_tail[gp][gv] + 1'b1;
            end

            if ((port_valid_in[gp] && in_vc_id[gp] == gv && vc_count[gp][gv] < BUF_DEPTH) &&
                !(gv == 0 && credit_out[gp] && vc_count[gp][gv] > 0)) begin
              vc_count[gp][gv] <= vc_count[gp][gv] + 1'b1;
            end else if (!(port_valid_in[gp] && in_vc_id[gp] == gv && vc_count[gp][gv] < BUF_DEPTH) &&
                           (gv == 0 && credit_out[gp] && vc_count[gp][gv] > 0)) begin
              vc_count[gp][gv] <= vc_count[gp][gv] - 1'b1;
            end
          end
        end
      end
    end
  endgenerate

  logic [4:0] output_busy;
  logic [2:0] route_port [0:4];

  always @* begin
    for (int p = 0; p < 5; p++) begin
      route_port[p] = LOCAL;
      if (vc_count[p][0] > 0) begin

        route_port[p] = route_xy(vcb_data[p][0][vc_head[p][0]][FLIT_W-7 -: 4]);
      end
    end
  end

  logic [FLIT_W-1:0] flit_out [5];

  always @* begin
    port_valid_out = '0;
    credit_out     = '0;
    output_busy    = '0;

    flit_out[0] = '0;
    flit_out[1] = '0;
    flit_out[2] = '0;
    flit_out[3] = '0;
    flit_out[4] = '0;

    for (int in_p = 0; in_p < 5; in_p++) begin
      if (vc_count[in_p][0] > 0) begin
        int out_p;
        out_p = int'(route_port[in_p]);

        if (!output_busy[out_p]) begin
          port_valid_out[out_p] = 1'b1;

          if (out_p == 0) flit_out[0] = vcb_data[in_p][0][vc_head[in_p][0]];
          else if (out_p == 1) flit_out[1] = vcb_data[in_p][0][vc_head[in_p][0]];
          else if (out_p == 2) flit_out[2] = vcb_data[in_p][0][vc_head[in_p][0]];
          else if (out_p == 3) flit_out[3] = vcb_data[in_p][0][vc_head[in_p][0]];
          else if (out_p == 4) flit_out[4] = vcb_data[in_p][0][vc_head[in_p][0]];

          output_busy[out_p]    = 1'b1;
          credit_out[in_p]      = 1'b1;
        end
      end
    end
  end

  assign port_flit_out_0 = flit_out[0];
  assign port_flit_out_1 = flit_out[1];
  assign port_flit_out_2 = flit_out[2];
  assign port_flit_out_3 = flit_out[3];
  assign port_flit_out_4 = flit_out[4];

endmodule : noc_router

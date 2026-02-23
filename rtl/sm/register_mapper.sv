`timescale 1ns/1ps

module register_mapper
  import agni_pkg::*;
#(
  parameter int unsigned MAX_WARPS       = 64,
  parameter int unsigned REGS_PER_THREAD = 255,
  parameter int unsigned WARP_LANES      = 32,
  parameter int unsigned NUM_BANKS       = 32,
  parameter int unsigned TOTAL_REGS      = 65536,
  localparam int unsigned PHYS_ADDR_W    = $clog2(TOTAL_REGS),
  localparam int unsigned BANK_ADDR_W    = $clog2(TOTAL_REGS / NUM_BANKS),
  localparam int unsigned BANK_IDX_W     = $clog2(NUM_BANKS)
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic                    cta_launch_valid,
  input  logic [$clog2(MAX_WARPS)-1:0] cta_first_warp,
  input  logic [5:0]             cta_num_warps,
  input  logic [7:0]             cta_regs_per_thread,
  output logic                   cta_launch_ready,
  output logic [PHYS_ADDR_W-1:0] cta_base_addr,

  input  logic                    cta_exit_valid,
  input  logic [$clog2(MAX_WARPS)-1:0] cta_exit_first_warp,
  input  logic [5:0]             cta_exit_num_warps,

  input  logic                    map_valid,
  input  logic [$clog2(MAX_WARPS)-1:0] map_warp_id,
  input  logic [4:0]             map_lane_id,
  input  logic [7:0]             map_logical_reg,
  output logic [BANK_IDX_W-1:0]  map_bank,
  output logic [BANK_ADDR_W-1:0] map_bank_addr,
  output logic                   map_valid_out,

  output logic [PHYS_ADDR_W-1:0] total_regs_used,
  output logic [PHYS_ADDR_W-1:0] total_regs_free,
  output logic [$clog2(MAX_WARPS):0] active_warps
);

  logic                    wt_valid          [0:MAX_WARPS-1];
  logic [PHYS_ADDR_W-1:0]  wt_base_addr     [0:MAX_WARPS-1];
  logic [7:0]              wt_regs_per_thr  [0:MAX_WARPS-1];
  logic [15:0]             wt_block_size    [0:MAX_WARPS-1];

  logic [PHYS_ADDR_W-1:0] alloc_pointer;
  logic [PHYS_ADDR_W-1:0] regs_in_use;
  logic [$clog2(MAX_WARPS):0] num_active;

  logic [15:0] required_regs;
  assign required_regs = cta_num_warps * cta_regs_per_thread * WARP_LANES;
  assign cta_launch_ready = (alloc_pointer + required_regs <= TOTAL_REGS);
  assign cta_base_addr = alloc_pointer;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      alloc_pointer <= '0;
      regs_in_use   <= '0;
      num_active    <= '0;
      for (int w = 0; w < MAX_WARPS; w++)
        wt_valid[w] <= 1'b0;
    end else begin

      if (cta_launch_valid && cta_launch_ready) begin
        for (int w = 0; w < 64; w++) begin
          if (w >= cta_first_warp && w < cta_first_warp + cta_num_warps) begin
            wt_valid[w]         <= 1'b1;
            wt_base_addr[w]     <= alloc_pointer +
                                    (w - cta_first_warp) * cta_regs_per_thread * WARP_LANES;
            wt_regs_per_thr[w]  <= cta_regs_per_thread;
            wt_block_size[w]    <= cta_regs_per_thread * WARP_LANES;
          end
        end
        alloc_pointer <= alloc_pointer + required_regs;
        regs_in_use   <= regs_in_use + required_regs;
        num_active    <= num_active + cta_num_warps;
      end

      if (cta_exit_valid) begin
        for (int w = 0; w < 64; w++) begin
          if (w >= cta_exit_first_warp && w < cta_exit_first_warp + cta_exit_num_warps) begin
            regs_in_use <= regs_in_use - wt_block_size[w];
            wt_valid[w] <= 1'b0;
            num_active <= num_active - 1;
          end
        end
      end
    end
  end

  logic [PHYS_ADDR_W-1:0] phys_addr;

  always_comb begin
    phys_addr = '0;
    map_bank      = '0;
    map_bank_addr = '0;
    map_valid_out = 1'b0;

    if (map_valid && wt_valid[map_warp_id]) begin
      phys_addr = wt_base_addr[map_warp_id] +
                  (map_logical_reg * WARP_LANES) +
                  map_lane_id;

      map_bank      = phys_addr[BANK_IDX_W-1:0] ^ map_warp_id[BANK_IDX_W-1:0];
      map_bank_addr = phys_addr[PHYS_ADDR_W-1:BANK_IDX_W];
      map_valid_out = 1'b1;
    end
  end

  assign total_regs_used = regs_in_use;
  assign total_regs_free = TOTAL_REGS - regs_in_use;
  assign active_warps    = num_active;

endmodule : register_mapper

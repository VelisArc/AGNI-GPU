`timescale 1ns/1ps

module tlb #(
  parameter int unsigned NUM_ENTRIES     = 64,
  parameter int unsigned VA_WIDTH        = 48,
  parameter int unsigned PA_WIDTH        = 44,
  parameter int unsigned ASID_WIDTH      = 16,
  parameter int unsigned PAGE_4KB_BITS   = 12,
  parameter int unsigned PAGE_2MB_BITS   = 21
)(
  input  logic                    clk,
  input  logic                    rst_n,

  input  logic                    lookup_valid,
  input  logic [VA_WIDTH-1:0]    lookup_va,
  input  logic [ASID_WIDTH-1:0]  lookup_asid,
  input  logic                    lookup_is_write,
  input  logic                    lookup_is_exec,
  input  logic                    lookup_is_user,

  output logic                    resp_hit,
  output logic [PA_WIDTH-1:0]    resp_pa,
  output logic                    resp_page_fault,
  output logic                    resp_perm_fault,

  input  logic                    fill_valid,
  input  logic                    fill_huge,
  input  logic                    fill_global,
  input  logic [ASID_WIDTH-1:0]  fill_asid,
  input  logic [VA_WIDTH-1:0]    fill_vpn,
  input  logic [PA_WIDTH-1:0]    fill_ppn,
  input  logic                    fill_readable,
  input  logic                    fill_writable,
  input  logic                    fill_executable,
  input  logic                    fill_user,

  input  logic                    inv_valid,
  input  logic [VA_WIDTH-1:0]    inv_vpn,
  input  logic [ASID_WIDTH-1:0]  inv_asid,
  input  logic                    inv_all,
  input  logic                    inv_asid_all,

  output logic [31:0]            perf_hits,
  output logic [31:0]            perf_misses
);

  logic                    tlb_valid      [0:NUM_ENTRIES-1];
  logic                    tlb_huge       [0:NUM_ENTRIES-1];
  logic                    tlb_global     [0:NUM_ENTRIES-1];
  logic [ASID_WIDTH-1:0]   tlb_asid       [0:NUM_ENTRIES-1];
  logic [VA_WIDTH-1:0]     tlb_vpn        [0:NUM_ENTRIES-1];
  logic [PA_WIDTH-1:0]     tlb_ppn        [0:NUM_ENTRIES-1];
  logic                    tlb_readable   [0:NUM_ENTRIES-1];
  logic                    tlb_writable   [0:NUM_ENTRIES-1];
  logic                    tlb_executable [0:NUM_ENTRIES-1];
  logic                    tlb_user       [0:NUM_ENTRIES-1];
  logic [5:0]              tlb_age        [0:NUM_ENTRIES-1];

  logic [VA_WIDTH-PAGE_4KB_BITS-1:0] lookup_vpn_4k;
  logic [VA_WIDTH-PAGE_2MB_BITS-1:0] lookup_vpn_2m;

  assign lookup_vpn_4k = lookup_va[VA_WIDTH-1:PAGE_4KB_BITS];
  assign lookup_vpn_2m = lookup_va[VA_WIDTH-1:PAGE_2MB_BITS];

  logic [NUM_ENTRIES-1:0] match_vec;
  logic [$clog2(NUM_ENTRIES)-1:0] match_idx;
  logic any_match, permission_fault;

  always_comb begin
    match_vec        = '0;
    match_idx        = '0;
    any_match        = 1'b0;
    permission_fault = 1'b0;

    for (int e = 0; e < NUM_ENTRIES; e++) begin
      if (tlb_valid[e]) begin
        logic vpn_match;
        logic asid_match;

        if (tlb_huge[e])
          vpn_match = (tlb_vpn[e][VA_WIDTH-1:PAGE_2MB_BITS] == lookup_vpn_2m);
        else
          vpn_match = (tlb_vpn[e][VA_WIDTH-1:PAGE_4KB_BITS] == lookup_vpn_4k);

        asid_match = tlb_global[e] || (tlb_asid[e] == lookup_asid);

        if (vpn_match && asid_match) begin
          match_vec[e] = 1'b1;
          any_match    = 1'b1;
          match_idx    = e[$clog2(NUM_ENTRIES)-1:0];

          if (lookup_is_write && !tlb_writable[e]) permission_fault = 1'b1;
          if (lookup_is_exec  && !tlb_executable[e]) permission_fault = 1'b1;
          if (lookup_is_user  && !tlb_user[e])      permission_fault = 1'b1;
        end
      end
    end
  end

  assign resp_hit        = lookup_valid && any_match && !permission_fault;
  assign resp_page_fault = lookup_valid && (!any_match);
  assign resp_perm_fault = lookup_valid && any_match && permission_fault;

  always_comb begin
    resp_pa = '0;
    if (any_match) begin
      if (tlb_huge[match_idx])
        resp_pa = {tlb_ppn[match_idx][PA_WIDTH-1:PAGE_2MB_BITS], lookup_va[PAGE_2MB_BITS-1:0]};
      else
        resp_pa = {tlb_ppn[match_idx][PA_WIDTH-1:PAGE_4KB_BITS], lookup_va[PAGE_4KB_BITS-1:0]};
    end
  end

  logic [$clog2(NUM_ENTRIES)-1:0] victim_idx;

  always_comb begin
    victim_idx = '0;
    begin : vic_sel_blk
      logic vic_found;
      logic [5:0] max_age_val;
      vic_found = 1'b0;
      max_age_val = '0;

      for (int i = 0; i < NUM_ENTRIES; i++) begin
        if (!tlb_valid[i] && !vic_found) begin
          victim_idx = i[$clog2(NUM_ENTRIES)-1:0];
          vic_found  = 1'b1;
        end
      end

      if (!vic_found) begin
        for (int i = 0; i < NUM_ENTRIES; i++) begin
          if (tlb_age[i] >= max_age_val) begin
            max_age_val = tlb_age[i];
            victim_idx  = i[$clog2(NUM_ENTRIES)-1:0];
          end
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_ENTRIES; i++) begin
        tlb_valid[i] <= 1'b0;
        tlb_age[i]   <= '0;
      end
      perf_hits   <= '0;
      perf_misses <= '0;
    end else begin

      if (inv_valid) begin
        for (int i = 0; i < NUM_ENTRIES; i++) begin
          if (inv_all) begin
            tlb_valid[i] <= 1'b0;
          end else if (inv_asid_all && tlb_asid[i] == inv_asid && !tlb_global[i]) begin
            tlb_valid[i] <= 1'b0;
          end else if (tlb_valid[i] && !tlb_global[i]) begin
            logic vpn_match;
            if (tlb_huge[i])
              vpn_match = (tlb_vpn[i][VA_WIDTH-1:PAGE_2MB_BITS] == inv_vpn[VA_WIDTH-1:PAGE_2MB_BITS]);
            else
              vpn_match = (tlb_vpn[i][VA_WIDTH-1:PAGE_4KB_BITS] == inv_vpn[VA_WIDTH-1:PAGE_4KB_BITS]);

            if (vpn_match && tlb_asid[i] == inv_asid) begin
              tlb_valid[i] <= 1'b0;
            end
          end
        end
      end

      if (fill_valid) begin
        tlb_valid[victim_idx]      <= 1'b1;
        tlb_huge[victim_idx]       <= fill_huge;
        tlb_global[victim_idx]     <= fill_global;
        tlb_asid[victim_idx]       <= fill_asid;
        tlb_vpn[victim_idx]        <= fill_vpn;
        tlb_ppn[victim_idx]        <= fill_ppn;
        tlb_readable[victim_idx]   <= fill_readable;
        tlb_writable[victim_idx]   <= fill_writable;
        tlb_executable[victim_idx] <= fill_executable;
        tlb_user[victim_idx]       <= fill_user;
        tlb_age[victim_idx]        <= '0;

        for (int i = 0; i < NUM_ENTRIES; i++) begin
          if (i != victim_idx && tlb_valid[i] && tlb_age[i] != 6'h3F)
            tlb_age[i] <= tlb_age[i] + 1'b1;
        end
      end else if (lookup_valid && any_match) begin

        tlb_age[match_idx] <= '0;
        for (int i = 0; i < NUM_ENTRIES; i++) begin
          if (i != match_idx && tlb_valid[i] && tlb_age[i] < tlb_age[match_idx])
            tlb_age[i] <= tlb_age[i] + 1'b1;
        end
      end

      if (lookup_valid) begin
        if (any_match && !permission_fault) perf_hits   <= perf_hits + 1;
        else                                perf_misses <= perf_misses + 1;
      end
    end
  end

endmodule : tlb

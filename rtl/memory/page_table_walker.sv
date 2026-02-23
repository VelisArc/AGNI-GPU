`timescale 1ns/1ps

module page_table_walker #(
  parameter int unsigned VA_WIDTH       = 48,
  parameter int unsigned PA_WIDTH       = 44,
  parameter int unsigned PTE_WIDTH      = 64,
  parameter int unsigned LEVELS         = 4,
  parameter int unsigned PDE_CACHE_SIZE = 16
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic                    walk_req_valid,
  input  logic [VA_WIDTH-1:0]    walk_req_va,
  input  logic [15:0]            walk_req_asid,
  input  logic [PA_WIDTH-1:0]    cr3_base,
  output logic                    walk_req_ready,

  output logic                    walk_resp_valid,
  output logic [VA_WIDTH-1:0]    walk_resp_va,
  output logic [PA_WIDTH-1:0]    walk_resp_pa,
  output logic [15:0]            walk_resp_asid,
  output logic                    walk_resp_huge,
  output logic                    walk_resp_global,
  output logic                    walk_resp_fault,
  output logic [3:0]             walk_resp_permissions,

  output logic                    mem_rd_req,
  output logic [PA_WIDTH-1:0]    mem_rd_addr,
  input  logic                    mem_rd_ready,
  input  logic                    mem_rd_resp_valid,
  input  logic [PTE_WIDTH-1:0]   mem_rd_data,

  output logic [31:0]            perf_walks,
  output logic [31:0]            perf_pde_cache_hits
);

  logic [8:0] va_index [0:3];
  assign va_index[0] = saved_va[47:39];
  assign va_index[1] = saved_va[38:30];
  assign va_index[2] = saved_va[29:21];
  assign va_index[3] = saved_va[20:12];

  logic pte_present, pte_writable, pte_user, pte_huge, pte_global, pte_dirty;
  logic [PA_WIDTH-1:0] pte_ppn;

  assign pte_present  = mem_rd_data[0];
  assign pte_writable = mem_rd_data[1];
  assign pte_user     = mem_rd_data[2];
  assign pte_huge     = mem_rd_data[7];
  assign pte_global   = mem_rd_data[8];
  assign pte_dirty    = mem_rd_data[6];
  assign pte_ppn      = {mem_rd_data[PA_WIDTH-1:12], 12'b0};

  logic                   pde_valid      [0:PDE_CACHE_SIZE-1];
  logic [VA_WIDTH-1:0]    pde_vpn_prefix [0:PDE_CACHE_SIZE-1];
  logic [PA_WIDTH-1:0]    pde_pa         [0:PDE_CACHE_SIZE-1];
  logic [15:0]            pde_asid       [0:PDE_CACHE_SIZE-1];

  logic pde_hit;
  logic [1:0] pde_hit_level;
  logic [PA_WIDTH-1:0] pde_hit_addr;

  always_comb begin
    pde_hit       = 1'b0;
    pde_hit_level = '0;
    pde_hit_addr  = '0;

    for (int c = 0; c < PDE_CACHE_SIZE; c++) begin
      if (pde_valid[c] && pde_asid[c] == walk_req_asid) begin

        if (pde_vpn_prefix[c][VA_WIDTH-1:30] == walk_req_va[VA_WIDTH-1:30]) begin
          pde_hit       = 1'b1;
          pde_hit_level = 2'd2;
          pde_hit_addr  = pde_pa[c];
        end
      end
    end
  end

  typedef enum logic [2:0] {
    WALK_IDLE     = 3'b000,
    WALK_REQ      = 3'b001,
    WALK_WAIT     = 3'b010,
    WALK_PROCESS  = 3'b011,
    WALK_DONE     = 3'b100,
    WALK_FAULT    = 3'b101
  } walk_state_t;

  walk_state_t state, state_next;
  logic [1:0] current_level;
  logic [PA_WIDTH-1:0] current_table_base;

  logic [VA_WIDTH-1:0] saved_va;
  logic [15:0]         saved_asid;
  logic                found_huge;
  logic [3:0]          accumulated_perms;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state              <= WALK_IDLE;
      current_level      <= '0;
      current_table_base <= '0;
      saved_va           <= '0;
      saved_asid         <= '0;
      found_huge         <= 1'b0;
      accumulated_perms  <= 4'b1111;
    end else begin
      state <= state_next;

      case (state)
        WALK_IDLE: begin
          if (walk_req_valid) begin
            saved_va   <= walk_req_va;
            saved_asid <= walk_req_asid;
            found_huge <= 1'b0;
            accumulated_perms <= 4'b1111;

            if (pde_hit) begin
              current_level      <= pde_hit_level;
              current_table_base <= pde_hit_addr;
            end else begin
              current_level      <= 2'd0;
              current_table_base <= cr3_base;
            end
          end
        end
        WALK_PROCESS: begin
          if (state_next == WALK_FAULT) begin

          end else if (state_next == WALK_DONE) begin

          end else begin

            current_level      <= current_level + 1;
            current_table_base <= pte_ppn;
            found_huge         <= pte_huge;

            accumulated_perms  <= accumulated_perms & {pte_user, 1'b1, pte_writable, 1'b1};
          end
        end
        default: ;
      endcase
    end
  end

  logic [PA_WIDTH-1:0] walk_addr;
  assign walk_addr = current_table_base + {va_index[current_level], 3'b000};

  always_comb begin
    state_next = state;
    case (state)
      WALK_IDLE:    if (walk_req_valid) state_next = WALK_REQ;
      WALK_REQ:     if (mem_rd_ready)   state_next = WALK_WAIT;
      WALK_WAIT:    if (mem_rd_resp_valid) state_next = WALK_PROCESS;
      WALK_PROCESS: begin
        if (!pte_present)
          state_next = WALK_FAULT;
        else if (pte_huge || current_level == 2'd3)
          state_next = WALK_DONE;
        else
          state_next = WALK_REQ;
      end
      WALK_DONE:    state_next = WALK_IDLE;
      WALK_FAULT:   state_next = WALK_IDLE;
      default:      state_next = WALK_IDLE;
    endcase
  end

  assign walk_req_ready = (state == WALK_IDLE);

  assign mem_rd_req  = (state == WALK_REQ);
  assign mem_rd_addr = walk_addr;

  assign walk_resp_valid       = (state == WALK_DONE) || (state == WALK_FAULT);
  assign walk_resp_va          = saved_va;
  assign walk_resp_asid        = saved_asid;
  assign walk_resp_huge        = found_huge;
  assign walk_resp_global      = pte_global;
  assign walk_resp_fault       = (state == WALK_FAULT);
  assign walk_resp_permissions = accumulated_perms & {pte_user, 1'b1, pte_writable, 1'b1};

  always_comb begin
    walk_resp_pa = '0;
    if (state == WALK_DONE) begin
      if (found_huge)
        walk_resp_pa = {pte_ppn[PA_WIDTH-1:21], 21'b0};
      else
        walk_resp_pa = pte_ppn;
    end
  end

  logic [$clog2(PDE_CACHE_SIZE)-1:0] pde_fill_idx;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < PDE_CACHE_SIZE; i++) pde_valid[i] <= 1'b0;
      pde_fill_idx <= '0;
    end else if (state == WALK_PROCESS && state_next != WALK_FAULT && current_level == 2'd1) begin

      pde_valid[pde_fill_idx]      <= 1'b1;
      pde_vpn_prefix[pde_fill_idx] <= saved_va;
      pde_pa[pde_fill_idx]         <= pte_ppn;
      pde_asid[pde_fill_idx]       <= saved_asid;
      pde_fill_idx <= pde_fill_idx + 1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      perf_walks          <= '0;
      perf_pde_cache_hits <= '0;
    end else begin
      if (state == WALK_IDLE && walk_req_valid) perf_walks <= perf_walks + 1;
      if (state == WALK_IDLE && walk_req_valid && pde_hit)
        perf_pde_cache_hits <= perf_pde_cache_hits + 1;
    end
  end

endmodule : page_table_walker

`timescale 1ns/1ps

module streaming_multiprocessor
  import agni_pkg::*;
#(
  parameter int unsigned SM_ID = 0
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        block_alloc_valid,
  input  logic [4:0]  block_id,
  input  logic [5:0]  num_warps,
  output logic        block_alloc_ready,

  output logic        mem_req_valid,
  output cache_req_t  mem_req,
  input  logic        mem_req_ready,
  input  logic        mem_resp_valid,
  input  cache_resp_t mem_resp,

  output logic [31:0] perf_active_warps,
  output logic [31:0] perf_instructions_issued,

  output logic        ecc_ce_out,
  output logic        ecc_ue_out
);

  logic [MAX_WARPS_PER_SM-1:0] warp_active;
  logic [MAX_WARPS_PER_SM-1:0] warp_at_barrier;

  always @* begin
    perf_active_warps = '0;
    for (int i = 0; i < MAX_WARPS_PER_SM; i++)
      perf_active_warps += {31'b0, warp_active[i]};
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      warp_active     <= '0;
      warp_at_barrier <= '0;
    end else begin
      if (block_alloc_valid && block_alloc_ready) begin

        for (int i = 0; i < MAX_WARPS_PER_SM; i++) begin
          if (i < int'(num_warps) && !warp_active[i])
            warp_active[i] <= 1'b1;
        end
      end
    end
  end

  assign block_alloc_ready = (perf_active_warps < 32'd60);

  logic [3:0]        sched_dispatch_valid;
  warp_instr_t       sched_dispatch_instr_0;
  warp_instr_t       sched_dispatch_instr_1;
  warp_instr_t       sched_dispatch_instr_2;
  warp_instr_t       sched_dispatch_instr_3;
  logic [3:0]        sched_dispatch_ready;
  logic [3:0]        sched_stall;

  alu_op_t            si_opcode    [4];
  logic [4:0]         si_dst_reg   [4];
  logic [4:0]         si_src0_reg  [4];
  logic [4:0]         si_src1_reg  [4];
  logic [4:0]         si_src2_reg  [4];
  precision_t         si_precision [4];
  logic               si_predicated[4];
  logic [6:0]         si_warp_id   [4];
  logic [31:0]        si_immediate [4];

  always @* begin
    si_opcode[0]     = sched_dispatch_instr_0.opcode;
    si_dst_reg[0]    = sched_dispatch_instr_0.dst_reg;
    si_src0_reg[0]   = sched_dispatch_instr_0.src0_reg;
    si_src1_reg[0]   = sched_dispatch_instr_0.src1_reg;
    si_src2_reg[0]   = sched_dispatch_instr_0.src2_reg;
    si_precision[0]  = sched_dispatch_instr_0.precision;
    si_predicated[0] = sched_dispatch_instr_0.predicated;
    si_warp_id[0]    = sched_dispatch_instr_0.warp_id;
    si_immediate[0]  = sched_dispatch_instr_0.immediate;

    si_opcode[1]     = sched_dispatch_instr_1.opcode;
    si_dst_reg[1]    = sched_dispatch_instr_1.dst_reg;
    si_src0_reg[1]   = sched_dispatch_instr_1.src0_reg;
    si_src1_reg[1]   = sched_dispatch_instr_1.src1_reg;
    si_src2_reg[1]   = sched_dispatch_instr_1.src2_reg;
    si_precision[1]  = sched_dispatch_instr_1.precision;
    si_predicated[1] = sched_dispatch_instr_1.predicated;
    si_warp_id[1]    = sched_dispatch_instr_1.warp_id;
    si_immediate[1]  = sched_dispatch_instr_1.immediate;

    si_opcode[2]     = sched_dispatch_instr_2.opcode;
    si_dst_reg[2]    = sched_dispatch_instr_2.dst_reg;
    si_src0_reg[2]   = sched_dispatch_instr_2.src0_reg;
    si_src1_reg[2]   = sched_dispatch_instr_2.src1_reg;
    si_src2_reg[2]   = sched_dispatch_instr_2.src2_reg;
    si_precision[2]  = sched_dispatch_instr_2.precision;
    si_predicated[2] = sched_dispatch_instr_2.predicated;
    si_warp_id[2]    = sched_dispatch_instr_2.warp_id;
    si_immediate[2]  = sched_dispatch_instr_2.immediate;

    si_opcode[3]     = sched_dispatch_instr_3.opcode;
    si_dst_reg[3]    = sched_dispatch_instr_3.dst_reg;
    si_src0_reg[3]   = sched_dispatch_instr_3.src0_reg;
    si_src1_reg[3]   = sched_dispatch_instr_3.src1_reg;
    si_src2_reg[3]   = sched_dispatch_instr_3.src2_reg;
    si_precision[3]  = sched_dispatch_instr_3.precision;
    si_predicated[3] = sched_dispatch_instr_3.predicated;
    si_warp_id[3]    = sched_dispatch_instr_3.warp_id;
    si_immediate[3]  = sched_dispatch_instr_3.immediate;
  end

  logic              wb_valid;
  logic [6:0]        wb_warp_id;
  logic [4:0]        wb_dst_reg;

  function automatic warp_instr_t make_sched_nop(input logic [6:0] warp_id);
    warp_instr_t instr;
    instr = '0;
    instr.opcode    = ALU_NOP;
    instr.precision = PREC_INT32;
    instr.warp_id   = warp_id;
    return instr;
  endfunction

  genvar gs;
  generate
    for (gs = 0; gs < WARP_SCHEDULERS; gs++) begin : g_sched
      warp_instr_t sched_di;
      logic        sched_fetch_req;
      logic [3:0]  sched_fetch_warp_id;
      warp_instr_t sched_fetched_instr;

      assign sched_fetched_instr = make_sched_nop((gs * 16) + sched_fetch_warp_id);

      warp_scheduler #(
        .MAX_WARPS    (16),
        .WARP_ID_BASE (gs * 16)
      ) u_sched (
        .clk            (clk),
        .rst_n          (rst_n),
        .warp_active    (warp_active[gs*16 +: 16]),
        .warp_at_barrier(warp_at_barrier[gs*16 +: 16]),
        .fetch_req      (sched_fetch_req),
        .fetch_warp_id  (sched_fetch_warp_id),
        .fetched_instr  (sched_fetched_instr),
        .fetched_valid  (sched_fetch_req),
        .wb_valid       (wb_valid),
        .wb_warp_id     (wb_warp_id),
        .wb_dst_reg     (wb_dst_reg),
        .dispatch_valid (sched_dispatch_valid[gs]),
        .dispatch_instr (sched_di),
        .dispatch_ready (sched_dispatch_ready[gs])
      );

      if (gs == 0) begin : g_si0
        assign sched_dispatch_instr_0 = sched_di;
      end
      if (gs == 1) begin : g_si1
        assign sched_dispatch_instr_1 = sched_di;
      end
      if (gs == 2) begin : g_si2
        assign sched_dispatch_instr_2 = sched_di;
      end
      if (gs == 3) begin : g_si3
        assign sched_dispatch_instr_3 = sched_di;
      end
    end
  endgenerate

  logic              fp32_dispatch_valid;
  alu_op_t           fp32_opcode;
  logic [31:0]       fp32_src0, fp32_src1, fp32_src2;
  logic [6:0]        fp32_warp_id;
  logic [4:0]        fp32_lane_id;
  logic [4:0]        fp32_dst_reg;

  logic              int32_dispatch_valid;
  alu_op_t           int32_opcode;
  logic [31:0]       int32_src0, int32_src1;
  logic [6:0]        int32_warp_id;
  logic [4:0]        int32_lane_id;
  logic [4:0]        int32_dst_reg;

  logic              sfu_dispatch_valid;
  sfu_op_t           sfu_opcode;
  logic [31:0]       sfu_operand;
  logic [6:0]        sfu_warp_id;
  logic [4:0]        sfu_lane_id;
  logic [4:0]        sfu_dst_reg;

  logic              tc_dispatch_valid;
  tc_op_t            tc_opcode;
  precision_t        tc_precision;

  logic              lsu_dispatch_valid;
  mem_op_t           lsu_opcode;
  logic [47:0]       lsu_addr;
  logic [6:0]        lsu_warp_id;

  dispatch_unit u_dispatch (
    .clk                  (clk),
    .rst_n                (rst_n),
    .sched_valid          (sched_dispatch_valid),
    .si_opcode            (si_opcode),
    .si_dst_reg           (si_dst_reg),
    .si_src0_reg          (si_src0_reg),
    .si_src1_reg          (si_src1_reg),
    .si_src2_reg          (si_src2_reg),
    .si_precision         (si_precision),
    .si_predicated        (si_predicated),
    .si_warp_id           (si_warp_id),
    .si_immediate         (si_immediate),
    .fp32_ready           (1'b1),
    .int32_ready          (1'b1),
    .tc_ready             (1'b1),
    .sfu_ready            (1'b1),
    .lsu_ready            (1'b1),
    .fp32_dispatch_valid  (fp32_dispatch_valid),
    .fp32_opcode          (fp32_opcode),
    .fp32_src0            (fp32_src0),
    .fp32_src1            (fp32_src1),
    .fp32_src2            (fp32_src2),
    .fp32_warp_id         (fp32_warp_id),
    .fp32_lane_id         (fp32_lane_id),
    .fp32_dst_reg         (fp32_dst_reg),
    .int32_dispatch_valid (int32_dispatch_valid),
    .int32_opcode         (int32_opcode),
    .int32_src0           (int32_src0),
    .int32_src1           (int32_src1),
    .int32_warp_id        (int32_warp_id),
    .int32_lane_id        (int32_lane_id),
    .int32_dst_reg        (int32_dst_reg),
    .sfu_dispatch_valid   (sfu_dispatch_valid),
    .sfu_opcode           (sfu_opcode),
    .sfu_operand          (sfu_operand),
    .sfu_warp_id          (sfu_warp_id),
    .sfu_lane_id          (sfu_lane_id),
    .sfu_dst_reg          (sfu_dst_reg),
    .tc_dispatch_valid    (tc_dispatch_valid),
    .tc_opcode            (tc_opcode),
    .tc_precision         (tc_precision),
    .lsu_dispatch_valid   (lsu_dispatch_valid),
    .lsu_opcode           (lsu_opcode),
    .lsu_addr             (lsu_addr),
    .lsu_warp_id          (lsu_warp_id),
    .sched_stall          (sched_stall)
  );

  logic [3:0]       rf_rd_en;
  logic [15:0]      rf_rd_addr [4];
  logic [31:0]      rf_rd_data [4];
  logic [3:0]       rf_rd_valid;
  logic [1:0]       rf_wr_en;
  logic [15:0]      rf_wr_addr [2];
  logic [31:0]      rf_wr_data [2];
  logic             rf_ecc_ce, rf_ecc_ue;

  always_comb begin
    rf_rd_en = '0;
    for (int i = 0; i < 4; i++) begin
      rf_rd_addr[i] = '0;
    end

    rf_wr_addr[0] = {4'b0, wb_warp_id, wb_dst_reg};
    rf_wr_addr[1] = '0;
  end

  register_file u_regfile (
    .clk        (clk),
    .rst_n      (rst_n),
    .rd_en      (rf_rd_en),
    .rd_addr    (rf_rd_addr),
    .rd_data    (rf_rd_data),
    .rd_valid   (rf_rd_valid),
    .wr_en      (rf_wr_en),
    .wr_addr    (rf_wr_addr),
    .wr_data    (rf_wr_data),
    .ecc_ce_flag(rf_ecc_ce),
    .ecc_ue_flag(rf_ecc_ue)
  );

  logic        fp32_result_valid;
  logic [31:0] fp32_result;
  logic [4:0]  fp32_flags;
  logic [6:0]  fp32_result_warp;
  logic [4:0]  fp32_result_lane;

  fp32_alu u_fp32_alu (
    .clk         (clk),
    .rst_n       (rst_n),
    .valid_in    (fp32_dispatch_valid),
    .opcode      (fp32_opcode),
    .src0        (fp32_src0),
    .src1        (fp32_src1),
    .src2        (fp32_src2),
    .warp_id_in  (fp32_warp_id),
    .lane_id_in  (fp32_lane_id),
    .valid_out   (fp32_result_valid),
    .result      (fp32_result),
    .fp_flags    (fp32_flags),
    .warp_id_out (fp32_result_warp),
    .lane_id_out (fp32_result_lane)
  );

  logic        int32_result_valid;
  logic [31:0] int32_result;
  logic [6:0]  int32_result_warp;
  logic [4:0]  int32_result_lane;

  int32_alu u_int32_alu (
    .clk           (clk),
    .rst_n         (rst_n),
    .valid_in      (int32_dispatch_valid),
    .opcode        (int32_opcode),
    .src0          (int32_src0),
    .src1          (int32_src1),
    .warp_id_in    (int32_warp_id),
    .lane_id_in    (int32_lane_id),
    .valid_out     (int32_result_valid),
    .result        (int32_result),
    .overflow      (),
    .zero_flag     (),
    .negative_flag (),
    .warp_id_out   (int32_result_warp),
    .lane_id_out   (int32_result_lane)
  );

  logic        sfu_result_valid;
  logic [31:0] sfu_result;
  logic [6:0]  sfu_result_warp;
  logic [4:0]  sfu_result_lane;
  logic [4:0]  fp32_dst_pipe [0:2];
  logic [4:0]  sfu_dst_pipe  [0:2];
  logic [4:0]  int32_dst_d;

  sfu u_sfu (
    .clk         (clk),
    .rst_n       (rst_n),
    .valid_in    (sfu_dispatch_valid),
    .opcode      (sfu_opcode),
    .operand     (sfu_operand),
    .warp_id_in  (sfu_warp_id),
    .lane_id_in  (sfu_lane_id),
    .valid_out   (sfu_result_valid),
    .result      (sfu_result),
    .warp_id_out (sfu_result_warp),
    .lane_id_out (sfu_result_lane)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      int32_dst_d <= '0;
      for (int i = 0; i < 3; i++) begin
        fp32_dst_pipe[i] <= '0;
        sfu_dst_pipe[i]  <= '0;
      end
    end else begin
      int32_dst_d      <= int32_dst_reg;
      fp32_dst_pipe[0] <= fp32_dst_reg;
      fp32_dst_pipe[1] <= fp32_dst_pipe[0];
      fp32_dst_pipe[2] <= fp32_dst_pipe[1];
      sfu_dst_pipe[0]  <= sfu_dst_reg;
      sfu_dst_pipe[1]  <= sfu_dst_pipe[0];
      sfu_dst_pipe[2]  <= sfu_dst_pipe[1];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wb_valid   <= 1'b0;
      wb_warp_id <= '0;
      wb_dst_reg <= '0;
      rf_wr_en   <= '0;
      rf_wr_data[0] <= '0;
      rf_wr_data[1] <= '0;
    end else begin

      if (fp32_result_valid) begin
        wb_valid      <= 1'b1;
        wb_warp_id    <= fp32_result_warp;
        wb_dst_reg    <= fp32_dst_pipe[2];
        rf_wr_en      <= '0;
        rf_wr_en[0]   <= 1'b1;
        rf_wr_data[0] <= fp32_result;
      end else if (int32_result_valid) begin
        wb_valid      <= 1'b1;
        wb_warp_id    <= int32_result_warp;
        wb_dst_reg    <= int32_dst_d;
        rf_wr_en      <= '0;
        rf_wr_en[0]   <= 1'b1;
        rf_wr_data[0] <= int32_result;
      end else if (sfu_result_valid) begin
        wb_valid    <= 1'b1;
        wb_warp_id  <= sfu_result_warp;
        wb_dst_reg  <= sfu_dst_pipe[2];
        rf_wr_en    <= '0;
        rf_wr_en[0] <= 1'b1;
        rf_wr_data[0] <= sfu_result;
      end else begin
        wb_valid   <= 1'b0;
        wb_warp_id <= '0;
        wb_dst_reg <= '0;
        rf_wr_en   <= '0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      perf_instructions_issued <= '0;
    else if (fp32_dispatch_valid || int32_dispatch_valid ||
             sfu_dispatch_valid || tc_dispatch_valid)
      perf_instructions_issued <= perf_instructions_issued + 1'b1;
  end

  assign ecc_ce_out = rf_ecc_ce;
  assign ecc_ue_out = rf_ecc_ue;

  always_comb begin
    mem_req_valid       = lsu_dispatch_valid;
    mem_req             = '0;
    mem_req.addr        = lsu_addr;
    mem_req.op          = lsu_opcode;
    mem_req.warp_id     = lsu_warp_id;
    mem_req.lane_id     = '0;
    mem_req.wdata       = '0;
    mem_req.byte_enable = (lsu_opcode == MEM_STORE) ? 16'hFFFF : 16'h0000;
  end

endmodule : streaming_multiprocessor

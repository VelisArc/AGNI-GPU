`timescale 1ns/1ps

module operand_collector
  import agni_pkg::*;
#(
  parameter int unsigned NUM_SLOTS   = 8,
  parameter int unsigned RD_PORTS    = 4
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        alloc_valid,
  input  warp_instr_t alloc_instr,
  output logic        alloc_ready,

  output logic [RD_PORTS-1:0]         rf_rd_en,
  output logic [15:0]                 rf_rd_addr [RD_PORTS],
  input  logic [31:0]                 rf_rd_data [RD_PORTS],
  input  logic [RD_PORTS-1:0]         rf_rd_valid,

  output logic        collected_valid,
  output warp_instr_t collected_instr,
  output logic [31:0] collected_src0,
  output logic [31:0] collected_src1,
  output logic [31:0] collected_src2
);

  logic        sl_valid     [0:NUM_SLOTS-1];

  alu_op_t     sl_opcode    [0:NUM_SLOTS-1];
  logic [4:0]  sl_dst_reg   [0:NUM_SLOTS-1];
  logic [4:0]  sl_src0_reg  [0:NUM_SLOTS-1];
  logic [4:0]  sl_src1_reg  [0:NUM_SLOTS-1];
  logic [4:0]  sl_src2_reg  [0:NUM_SLOTS-1];
  precision_t  sl_precision [0:NUM_SLOTS-1];
  logic        sl_predicated[0:NUM_SLOTS-1];
  logic [6:0]  sl_warp_id   [0:NUM_SLOTS-1];
  logic [31:0] sl_immediate [0:NUM_SLOTS-1];

  logic [31:0] sl_src0_data [0:NUM_SLOTS-1];
  logic [31:0] sl_src1_data [0:NUM_SLOTS-1];
  logic [31:0] sl_src2_data [0:NUM_SLOTS-1];
  logic        sl_src0_rdy  [0:NUM_SLOTS-1];
  logic        sl_src1_rdy  [0:NUM_SLOTS-1];
  logic        sl_src2_rdy  [0:NUM_SLOTS-1];

  logic [NUM_SLOTS-1:0] slot_free;
  logic [$clog2(NUM_SLOTS)-1:0] free_slot_id;
  logic any_free;

  always @* begin
    for (int i = 0; i < NUM_SLOTS; i++)
      slot_free[i] = !sl_valid[i];

    any_free     = |slot_free;
    alloc_ready  = any_free;
    free_slot_id = '0;
    for (int i = 0; i < NUM_SLOTS; i++) begin
      if (slot_free[i] && free_slot_id == '0 && i > 0) begin
        free_slot_id = i[$clog2(NUM_SLOTS)-1:0];
      end else if (slot_free[0]) begin
        free_slot_id = '0;
      end
    end
  end

  logic [NUM_SLOTS-1:0] needs_read;
  logic [NUM_SLOTS-1:0] slot_collected;
  logic [$clog2(NUM_SLOTS)-1:0] collected_slot_id;
  logic any_collected;

  always @* begin
    for (int i = 0; i < NUM_SLOTS; i++) begin
      needs_read[i]     = sl_valid[i] && (!sl_src0_rdy[i] || !sl_src1_rdy[i] || !sl_src2_rdy[i]);
      slot_collected[i] = sl_valid[i] && sl_src0_rdy[i] && sl_src1_rdy[i] && sl_src2_rdy[i];
    end

    any_collected     = |slot_collected;
    collected_slot_id = '0;
    begin : coll_sel_blk
      logic coll_found;
      coll_found = 1'b0;
      for (int i = 0; i < NUM_SLOTS; i++) begin
        if (slot_collected[i] && !coll_found) begin
          collected_slot_id = i[$clog2(NUM_SLOTS)-1:0];
          coll_found = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_SLOTS; i++) begin
        sl_valid[i]    <= 1'b0;
        sl_src0_rdy[i] <= 1'b0;
        sl_src1_rdy[i] <= 1'b0;
        sl_src2_rdy[i] <= 1'b0;
      end
    end else begin

      if (alloc_valid && any_free) begin
        sl_valid[free_slot_id]      <= 1'b1;
        sl_opcode[free_slot_id]     <= alloc_instr.opcode;
        sl_dst_reg[free_slot_id]    <= alloc_instr.dst_reg;
        sl_src0_reg[free_slot_id]   <= alloc_instr.src0_reg;
        sl_src1_reg[free_slot_id]   <= alloc_instr.src1_reg;
        sl_src2_reg[free_slot_id]   <= alloc_instr.src2_reg;
        sl_precision[free_slot_id]  <= alloc_instr.precision;
        sl_predicated[free_slot_id] <= alloc_instr.predicated;
        sl_warp_id[free_slot_id]    <= alloc_instr.warp_id;
        sl_immediate[free_slot_id]  <= alloc_instr.immediate;
        sl_src0_rdy[free_slot_id]   <= (alloc_instr.opcode == ALU_NOP);
        sl_src1_rdy[free_slot_id]   <= (alloc_instr.opcode == ALU_NOP ||
                                         alloc_instr.opcode == ALU_ABS ||
                                         alloc_instr.opcode == ALU_NEG);
        sl_src2_rdy[free_slot_id]   <= (alloc_instr.opcode != ALU_FMA);
      end

      for (int p = 0; p < RD_PORTS; p++) begin
        if (rf_rd_valid[p]) begin
          for (int s = 0; s < NUM_SLOTS; s++) begin
            if (sl_valid[s]) begin
              if (!sl_src0_rdy[s] && rf_rd_addr[p] == {11'b0, sl_src0_reg[s]}) begin
                sl_src0_data[s] <= rf_rd_data[p];
                sl_src0_rdy[s]  <= 1'b1;
              end
              if (!sl_src1_rdy[s] && rf_rd_addr[p] == {11'b0, sl_src1_reg[s]}) begin
                sl_src1_data[s] <= rf_rd_data[p];
                sl_src1_rdy[s]  <= 1'b1;
              end
              if (!sl_src2_rdy[s] && rf_rd_addr[p] == {11'b0, sl_src2_reg[s]}) begin
                sl_src2_data[s] <= rf_rd_data[p];
                sl_src2_rdy[s]  <= 1'b1;
              end
            end
          end
        end
      end

      if (any_collected) begin
        sl_valid[collected_slot_id] <= 1'b0;
      end
    end
  end

  always @* begin
    rf_rd_en = '0;
    for (int p = 0; p < RD_PORTS; p++)
      rf_rd_addr[p] = '0;

    begin : rd_req_blk
      int port_idx;
      port_idx = 0;
      for (int s = 0; s < NUM_SLOTS; s++) begin
        if (needs_read[s] && port_idx < RD_PORTS) begin
          if (!sl_src0_rdy[s] && port_idx < RD_PORTS) begin
            rf_rd_en[port_idx]   = 1'b1;
            rf_rd_addr[port_idx] = {11'b0, sl_src0_reg[s]};
            port_idx = port_idx + 1;
          end
          if (!sl_src1_rdy[s] && port_idx < RD_PORTS) begin
            rf_rd_en[port_idx]   = 1'b1;
            rf_rd_addr[port_idx] = {11'b0, sl_src1_reg[s]};
            port_idx = port_idx + 1;
          end
        end
      end
    end
  end

  warp_instr_t collected_instr_r;

  always @* begin
    collected_instr_r.opcode     = sl_opcode[collected_slot_id];
    collected_instr_r.dst_reg    = sl_dst_reg[collected_slot_id];
    collected_instr_r.src0_reg   = sl_src0_reg[collected_slot_id];
    collected_instr_r.src1_reg   = sl_src1_reg[collected_slot_id];
    collected_instr_r.src2_reg   = sl_src2_reg[collected_slot_id];
    collected_instr_r.precision  = sl_precision[collected_slot_id];
    collected_instr_r.predicated = sl_predicated[collected_slot_id];
    collected_instr_r.warp_id    = sl_warp_id[collected_slot_id];
    collected_instr_r.immediate  = sl_immediate[collected_slot_id];
  end

  assign collected_valid = any_collected;
  assign collected_instr = any_collected ? collected_instr_r : '0;
  assign collected_src0  = any_collected ? sl_src0_data[collected_slot_id] : '0;
  assign collected_src1  = any_collected ? sl_src1_data[collected_slot_id] : '0;
  assign collected_src2  = any_collected ? sl_src2_data[collected_slot_id] : '0;

endmodule : operand_collector

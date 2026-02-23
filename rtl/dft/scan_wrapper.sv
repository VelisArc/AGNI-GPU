`timescale 1ns/1ps

module scan_wrapper
  import agni_pkg::*;
#(
  parameter int unsigned SCAN_CHAINS    = 8,
  parameter int unsigned BSR_WIDTH      = 256,
  parameter int unsigned BIST_MEM_WORDS = 1024,
  parameter int unsigned BIST_DATA_W    = 64
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        tck,
  input  logic        tms,
  input  logic        tdi,
  output logic        tdo,
  input  logic        trst_n,

  input  logic        scan_enable,
  input  logic [SCAN_CHAINS-1:0] scan_in,
  output logic [SCAN_CHAINS-1:0] scan_out,

  input  logic        bist_start,
  output logic        bist_done,
  output logic        bist_pass,
  output logic [31:0] bist_fail_addr,
  output logic [31:0] bist_fail_count,

  output logic                    bist_mem_en,
  output logic                    bist_mem_we,
  output logic [$clog2(BIST_MEM_WORDS)-1:0] bist_mem_addr,
  output logic [BIST_DATA_W-1:0] bist_mem_wdata,
  input  logic [BIST_DATA_W-1:0] bist_mem_rdata,

  output logic [BSR_WIDTH-1:0]   bsr_out,
  input  logic [BSR_WIDTH-1:0]   bsr_in,

  output logic        dft_mode,
  output logic        bist_mode
);

  typedef enum logic [3:0] {
    TAP_RESET      = 4'h0,
    TAP_IDLE       = 4'h1,
    TAP_SEL_DR     = 4'h2,
    TAP_CAPTURE_DR = 4'h3,
    TAP_SHIFT_DR   = 4'h4,
    TAP_EXIT1_DR   = 4'h5,
    TAP_PAUSE_DR   = 4'h6,
    TAP_EXIT2_DR   = 4'h7,
    TAP_UPDATE_DR  = 4'h8,
    TAP_SEL_IR     = 4'h9,
    TAP_CAPTURE_IR = 4'hA,
    TAP_SHIFT_IR   = 4'hB,
    TAP_EXIT1_IR   = 4'hC,
    TAP_PAUSE_IR   = 4'hD,
    TAP_EXIT2_IR   = 4'hE,
    TAP_UPDATE_IR  = 4'hF
  } tap_state_t;

  tap_state_t tap_state, tap_next;

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)
      tap_state <= TAP_RESET;
    else
      tap_state <= tap_next;
  end

  always_comb begin
    tap_next = TAP_RESET;

    case (tap_state)
      TAP_RESET:      if (tms) tap_next = TAP_RESET;     else tap_next = TAP_IDLE;
      TAP_IDLE:       if (tms) tap_next = TAP_SEL_DR;     else tap_next = TAP_IDLE;
      TAP_SEL_DR:     if (tms) tap_next = TAP_SEL_IR;     else tap_next = TAP_CAPTURE_DR;
      TAP_CAPTURE_DR: if (tms) tap_next = TAP_EXIT1_DR;   else tap_next = TAP_SHIFT_DR;
      TAP_SHIFT_DR:   if (tms) tap_next = TAP_EXIT1_DR;   else tap_next = TAP_SHIFT_DR;
      TAP_EXIT1_DR:   if (tms) tap_next = TAP_UPDATE_DR;  else tap_next = TAP_PAUSE_DR;
      TAP_PAUSE_DR:   if (tms) tap_next = TAP_EXIT2_DR;   else tap_next = TAP_PAUSE_DR;
      TAP_EXIT2_DR:   if (tms) tap_next = TAP_UPDATE_DR;  else tap_next = TAP_SHIFT_DR;
      TAP_UPDATE_DR:  if (tms) tap_next = TAP_SEL_DR;     else tap_next = TAP_IDLE;
      TAP_SEL_IR:     if (tms) tap_next = TAP_RESET;      else tap_next = TAP_CAPTURE_IR;
      TAP_CAPTURE_IR: if (tms) tap_next = TAP_EXIT1_IR;   else tap_next = TAP_SHIFT_IR;
      TAP_SHIFT_IR:   if (tms) tap_next = TAP_EXIT1_IR;   else tap_next = TAP_SHIFT_IR;
      TAP_EXIT1_IR:   if (tms) tap_next = TAP_UPDATE_IR;  else tap_next = TAP_PAUSE_IR;
      TAP_PAUSE_IR:   if (tms) tap_next = TAP_EXIT2_IR;   else tap_next = TAP_PAUSE_IR;
      TAP_EXIT2_IR:   if (tms) tap_next = TAP_UPDATE_IR;  else tap_next = TAP_SHIFT_IR;
      TAP_UPDATE_IR:  if (tms) tap_next = TAP_SEL_DR;     else tap_next = TAP_IDLE;
      default:        tap_next = TAP_RESET;
    endcase
  end

  localparam IR_WIDTH = 4;
  localparam IR_BYPASS   = 4'b1111;
  localparam IR_IDCODE   = 4'b0001;
  localparam IR_EXTEST   = 4'b0000;
  localparam IR_SCAN     = 4'b0010;
  localparam IR_BIST     = 4'b0011;

  logic [IR_WIDTH-1:0] ir_shift, ir_latch;

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      ir_shift <= IR_IDCODE;
      ir_latch <= IR_IDCODE;
    end else begin
      if (tap_state == TAP_CAPTURE_IR)
        ir_shift <= 4'b0001;
      else if (tap_state == TAP_SHIFT_IR)
        ir_shift <= {tdi, ir_shift[IR_WIDTH-1:1]};
      else if (tap_state == TAP_UPDATE_IR)
        ir_latch <= ir_shift;
    end
  end

  localparam [31:0] IDCODE = 32'hA6E1_2026;

  logic [31:0] idcode_shift;

  always_ff @(posedge tck) begin
    if (tap_state == TAP_CAPTURE_DR && ir_latch == IR_IDCODE)
      idcode_shift <= IDCODE;
    else if (tap_state == TAP_SHIFT_DR && ir_latch == IR_IDCODE)
      idcode_shift <= {tdi, idcode_shift[31:1]};
  end

  logic bypass_reg;

  always_ff @(posedge tck) begin
    if (tap_state == TAP_CAPTURE_DR && ir_latch == IR_BYPASS)
      bypass_reg <= 1'b0;
    else if (tap_state == TAP_SHIFT_DR && ir_latch == IR_BYPASS)
      bypass_reg <= tdi;
  end

  logic [BSR_WIDTH-1:0] bsr_shift;

  always_ff @(posedge tck) begin
    if (tap_state == TAP_CAPTURE_DR && ir_latch == IR_EXTEST)
      bsr_shift <= bsr_in;
    else if (tap_state == TAP_SHIFT_DR && ir_latch == IR_EXTEST)
      bsr_shift <= {tdi, bsr_shift[BSR_WIDTH-1:1]};
    else if (tap_state == TAP_UPDATE_DR && ir_latch == IR_EXTEST)
      ;
  end

  assign bsr_out = (ir_latch == IR_EXTEST && tap_state == TAP_UPDATE_DR) ? bsr_shift : bsr_in;

  always_comb begin
    case (ir_latch)
      IR_IDCODE: tdo = idcode_shift[0];
      IR_EXTEST: tdo = bsr_shift[0];
      IR_BYPASS: tdo = bypass_reg;
      IR_SCAN:   tdo = scan_out[0];
      default:   tdo = bypass_reg;
    endcase
  end

  typedef enum logic [2:0] {
    BIST_IDLE     = 3'b000,
    BIST_W0_UP    = 3'b001,
    BIST_R0W1_UP  = 3'b010,
    BIST_R1W0_UP  = 3'b011,
    BIST_R0W1_DN  = 3'b100,
    BIST_R1W0_DN  = 3'b101,
    BIST_R0_UP    = 3'b110,
    BIST_COMPLETE = 3'b111
  } bist_state_t;

  bist_state_t bist_fsm;
  logic [$clog2(BIST_MEM_WORDS)-1:0] bist_addr;
  logic                               bist_direction;
  logic                               bist_phase;
  logic [BIST_DATA_W-1:0]            bist_expected;
  logic                               bist_err;

  assign bist_done = (bist_fsm == BIST_COMPLETE);
  assign bist_mode = (bist_fsm != BIST_IDLE);
  assign bist_err  = bist_mem_en && !bist_mem_we && (bist_mem_rdata !== bist_expected);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bist_fsm        <= BIST_IDLE;
      bist_addr       <= '0;
      bist_phase      <= 1'b0;
      bist_pass       <= 1'b1;
      bist_fail_addr  <= '0;
      bist_fail_count <= '0;
    end else begin
      case (bist_fsm)
        BIST_IDLE: begin
          if (bist_start) begin
            bist_fsm        <= BIST_W0_UP;
            bist_addr       <= '0;
            bist_pass       <= 1'b1;
            bist_fail_count <= '0;
          end
        end

        BIST_W0_UP: begin
          if (bist_addr == BIST_MEM_WORDS - 1) begin
            bist_fsm  <= BIST_R0W1_UP;
            bist_addr <= '0;
            bist_phase <= 1'b0;
          end else begin
            bist_addr <= bist_addr + 1;
          end
        end

        BIST_R0W1_UP, BIST_R1W0_UP: begin
          if (bist_phase == 0) begin

            bist_phase <= 1'b1;
            if (bist_err) begin
              bist_pass <= 1'b0;
              if (bist_fail_count == 0) bist_fail_addr <= bist_addr;
              bist_fail_count <= bist_fail_count + 1;
            end
          end else begin

            bist_phase <= 1'b0;
            if (bist_addr == BIST_MEM_WORDS - 1) begin
              bist_addr <= '0;
              bist_fsm <= (bist_fsm == BIST_R0W1_UP) ? BIST_R1W0_UP : BIST_R0W1_DN;
            end else begin
              bist_addr <= bist_addr + 1;
            end
          end
        end

        BIST_R0W1_DN, BIST_R1W0_DN: begin
          if (bist_phase == 0) begin
            bist_phase <= 1'b1;
            if (bist_err) begin
              bist_pass <= 1'b0;
              if (bist_fail_count == 0) bist_fail_addr <= bist_addr;
              bist_fail_count <= bist_fail_count + 1;
            end
          end else begin
            bist_phase <= 1'b0;
            if (bist_addr == 0) begin
              bist_addr <= '0;
              bist_fsm  <= (bist_fsm == BIST_R0W1_DN) ? BIST_R1W0_DN : BIST_R0_UP;
            end else begin
              bist_addr <= bist_addr - 1;
            end
          end
        end

        BIST_R0_UP: begin
          if (bist_err) begin
            bist_pass <= 1'b0;
            bist_fail_count <= bist_fail_count + 1;
          end
          if (bist_addr == BIST_MEM_WORDS - 1)
            bist_fsm <= BIST_COMPLETE;
          else
            bist_addr <= bist_addr + 1;
        end

        BIST_COMPLETE: begin
          if (!bist_start) bist_fsm <= BIST_IDLE;
        end
      endcase
    end
  end

  always_comb begin
    bist_mem_en    = (bist_fsm != BIST_IDLE && bist_fsm != BIST_COMPLETE);
    bist_mem_addr  = bist_addr;
    bist_mem_wdata = '0;
    bist_mem_we    = 1'b0;
    bist_expected  = '0;

    case (bist_fsm)
      BIST_W0_UP: begin
        bist_mem_we = 1'b1;
        bist_mem_wdata = '0;
      end
      BIST_R0W1_UP: begin
        bist_mem_we = bist_phase;
        bist_mem_wdata = {BIST_DATA_W{1'b1}};
        bist_expected  = '0;
      end
      BIST_R1W0_UP: begin
        bist_mem_we = bist_phase;
        bist_mem_wdata = '0;
        bist_expected  = {BIST_DATA_W{1'b1}};
      end
      BIST_R0W1_DN: begin
        bist_mem_we = bist_phase;
        bist_mem_wdata = {BIST_DATA_W{1'b1}};
        bist_expected  = '0;
      end
      BIST_R1W0_DN: begin
        bist_mem_we = bist_phase;
        bist_mem_wdata = '0;
        bist_expected  = {BIST_DATA_W{1'b1}};
      end
      BIST_R0_UP: begin
        bist_expected = '0;
      end
      default: ;
    endcase
  end

  assign scan_out = scan_in;

  assign dft_mode = scan_enable || (tap_state != TAP_RESET && tap_state != TAP_IDLE);

endmodule : scan_wrapper

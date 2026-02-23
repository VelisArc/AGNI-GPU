

`timescale 1ns/1ps

module nvlink_phy
  import agni_pkg::*;
#(
  parameter int unsigned NUM_LANES    = 18,
  parameter int unsigned FLIT_WIDTH   = 128,
  parameter int unsigned CREDIT_DEPTH = 32
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic [NUM_LANES-1:0] rx_p, rx_n,
  output logic [NUM_LANES-1:0] tx_p, tx_n,

  input  logic                    tx_flit_valid,
  input  logic [FLIT_WIDTH-1:0]  tx_flit_data,
  input  logic [3:0]             tx_flit_vc,
  output logic                    tx_flit_ready,

  output logic                    rx_flit_valid,
  output logic [FLIT_WIDTH-1:0]  rx_flit_data,
  output logic [3:0]             rx_flit_vc,
  input  logic                    rx_flit_ready,

  output logic        link_up,
  output logic [4:0]  active_lanes,
  output logic [31:0] link_bw_gbps,

  output logic [$clog2(CREDIT_DEPTH):0] tx_credits_available,
  input  logic                          tx_credit_return,

  output logic        link_error,
  output logic [7:0]  error_syndrome,
  output logic [31:0] error_count,

  input  logic [1:0]  power_state,
  output logic        in_low_power
);

  typedef enum logic [2:0] {
    NVL_OFF          = 3'b000,
    NVL_DETECT       = 3'b001,
    NVL_TRAINING     = 3'b010,
    NVL_CALIBRATE    = 3'b011,
    NVL_ACTIVE       = 3'b100,
    NVL_LOW_POWER    = 3'b101,
    NVL_RECOVERY     = 3'b110,
    NVL_ERROR        = 3'b111
  } nvl_state_t;

  nvl_state_t state, state_next;
  logic [15:0] train_counter;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= NVL_OFF;
      train_counter <= '0;
    end else begin
      state <= state_next;
      if (state != state_next)
        train_counter <= '0;
      else
        train_counter <= train_counter + 1;
    end
  end

  always_comb begin
    state_next = state;
    case (state)
      NVL_OFF:       if (power_state != 2'd2) state_next = NVL_DETECT;
      NVL_DETECT:    if (train_counter > 50)  state_next = NVL_TRAINING;
      NVL_TRAINING:  if (train_counter > 200) state_next = NVL_CALIBRATE;
      NVL_CALIBRATE: if (train_counter > 100) state_next = NVL_ACTIVE;
      NVL_ACTIVE: begin
        if (power_state == 2'd1)   state_next = NVL_LOW_POWER;
        else if (power_state == 2'd2) state_next = NVL_OFF;
        else if (link_error)      state_next = NVL_RECOVERY;
      end
      NVL_LOW_POWER: if (power_state == 2'd0)  state_next = NVL_ACTIVE;
      NVL_RECOVERY:  if (train_counter > 100) state_next = NVL_ACTIVE;
      NVL_ERROR:     if (train_counter > 500) state_next = NVL_DETECT;
    endcase
  end

  assign link_up      = (state == NVL_ACTIVE);
  assign active_lanes = link_up ? NUM_LANES : 5'd0;
  assign link_bw_gbps = link_up ? 32'd900 : 32'd0;
  assign in_low_power = (state == NVL_LOW_POWER);

  logic [$clog2(CREDIT_DEPTH):0] credits;
  logic consume_credit, return_credit;
  assign consume_credit = tx_flit_valid && tx_flit_ready && (credits > 0);
  assign return_credit  = tx_credit_return && (credits < CREDIT_DEPTH);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      credits <= CREDIT_DEPTH;
    end else begin
      case ({consume_credit, return_credit})
        2'b10: credits <= credits - 1'b1;
        2'b01: credits <= credits + 1'b1;
        default: credits <= credits;
      endcase
    end
  end

  assign tx_credits_available = credits;
  assign tx_flit_ready = link_up && (credits > 0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      tx_p <= '0;
    else if (tx_flit_valid && tx_flit_ready)
      tx_p <= tx_flit_data[NUM_LANES-1:0];
  end
  assign tx_n = ~tx_p;

  logic                  rx_buf_valid;
  logic [FLIT_WIDTH-1:0] rx_buf_data;
  logic [3:0]            rx_buf_vc;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_buf_valid <= 1'b0;
      rx_buf_data  <= '0;
      rx_buf_vc    <= '0;
    end else begin
      if (rx_buf_valid && rx_flit_ready)
        rx_buf_valid <= 1'b0;

      if (!rx_buf_valid && tx_flit_valid && tx_flit_ready) begin
        rx_buf_valid <= 1'b1;
        rx_buf_data  <= tx_flit_data;
        rx_buf_vc    <= tx_flit_vc;
      end
    end
  end
  assign rx_flit_valid = rx_buf_valid;
  assign rx_flit_data  = rx_buf_data;
  assign rx_flit_vc    = rx_buf_vc;

  logic diff_pair_error, flow_error, rx_overflow_error;
  logic [7:0] error_syndrome_next;

  always_comb begin
    diff_pair_error  = link_up && ((rx_p ^ rx_n) !== {NUM_LANES{1'b1}});
    flow_error       = link_up && tx_flit_valid && !tx_flit_ready;
    rx_overflow_error = link_up && tx_flit_valid && tx_flit_ready && rx_buf_valid && !rx_flit_ready;
    error_syndrome_next = '0;
    error_syndrome_next[0] = diff_pair_error;
    error_syndrome_next[1] = flow_error;
    error_syndrome_next[2] = rx_overflow_error;
  end

  assign link_error = |error_syndrome_next;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      error_syndrome <= '0;
      error_count <= '0;
    end else begin
      error_syndrome <= error_syndrome_next;
      if (|error_syndrome_next)
        error_count <= error_count + 1'b1;
    end
  end

endmodule : nvlink_phy

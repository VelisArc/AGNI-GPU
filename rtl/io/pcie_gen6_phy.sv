

`timescale 1ns/1ps

module pcie_gen6_phy
  import agni_pkg::*;
#(
  parameter int unsigned NUM_LANES = 16,
  parameter int unsigned TLP_WIDTH = 256
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic [NUM_LANES-1:0] rx_p,
  input  logic [NUM_LANES-1:0] rx_n,
  output logic [NUM_LANES-1:0] tx_p,
  output logic [NUM_LANES-1:0] tx_n,

  input  logic                  tx_tlp_valid,
  input  logic [TLP_WIDTH-1:0]  tx_tlp_data,
  input  logic [7:0]            tx_tlp_type,
  input  logic [15:0]           tx_tlp_length,
  output logic                  tx_tlp_ready,

  output logic                  rx_tlp_valid,
  output logic [TLP_WIDTH-1:0]  rx_tlp_data,
  output logic [7:0]            rx_tlp_type,
  output logic [15:0]           rx_tlp_length,
  input  logic                  rx_tlp_ready,

  output logic        link_up,
  output logic [3:0]  link_gen,
  output logic [4:0]  link_width,
  output logic [1:0]  link_speed,

  output logic        correctable_error,
  output logic        uncorrectable_error,
  output logic [31:0] error_count
);

  typedef enum logic [3:0] {
    LTSSM_DETECT_QUIET    = 4'h0,
    LTSSM_DETECT_ACTIVE   = 4'h1,
    LTSSM_POLLING_ACTIVE  = 4'h2,
    LTSSM_POLLING_CONFIG  = 4'h3,
    LTSSM_CONFIG_LINK_W   = 4'h4,
    LTSSM_CONFIG_LANE_N   = 4'h5,
    LTSSM_CONFIG_COMPLETE = 4'h6,
    LTSSM_L0              = 4'h7,
    LTSSM_L0S             = 4'h8,
    LTSSM_L1              = 4'h9,
    LTSSM_L2              = 4'hA,
    LTSSM_RECOVERY        = 4'hB,
    LTSSM_HOT_RESET       = 4'hC,
    LTSSM_DISABLED        = 4'hD
  } ltssm_state_t;

  ltssm_state_t ltssm_state, ltssm_next;
  logic [15:0] train_timer;

  logic [31:0] tx_lcrc;
  logic [31:0] rx_lcrc;
  logic lane_pair_error;
  logic malformed_tlp_error;
  logic crc_error;
  logic rx_overflow_error;

  function automatic logic [31:0] crc32(input logic [TLP_WIDTH-1:0] data);
    logic [31:0] crc;
    crc = 32'hFFFF_FFFF;
    for (int i = 0; i < TLP_WIDTH; i++) begin
      if (crc[0] ^ data[i])
        crc = (crc >> 1) ^ 32'hEDB8_8320;
      else
        crc = crc >> 1;
    end
    return ~crc;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ltssm_state <= LTSSM_DETECT_QUIET;
      train_timer <= '0;
    end else begin
      ltssm_state <= ltssm_next;
      if (ltssm_state != ltssm_next)
        train_timer <= '0;
      else
        train_timer <= train_timer + 1'b1;
    end
  end

  always_comb begin
    ltssm_next = ltssm_state;
    case (ltssm_state)
      LTSSM_DETECT_QUIET:    if (train_timer > 16'd100) ltssm_next = LTSSM_DETECT_ACTIVE;
      LTSSM_DETECT_ACTIVE:   if (train_timer > 16'd50)  ltssm_next = LTSSM_POLLING_ACTIVE;
      LTSSM_POLLING_ACTIVE:  if (train_timer > 16'd200) ltssm_next = LTSSM_POLLING_CONFIG;
      LTSSM_POLLING_CONFIG:  if (train_timer > 16'd100) ltssm_next = LTSSM_CONFIG_LINK_W;
      LTSSM_CONFIG_LINK_W:   if (train_timer > 16'd50)  ltssm_next = LTSSM_CONFIG_LANE_N;
      LTSSM_CONFIG_LANE_N:   if (train_timer > 16'd50)  ltssm_next = LTSSM_CONFIG_COMPLETE;
      LTSSM_CONFIG_COMPLETE: if (train_timer > 16'd20)  ltssm_next = LTSSM_L0;
      LTSSM_L0: ;
      LTSSM_RECOVERY:        if (train_timer > 16'd100) ltssm_next = LTSSM_L0;
      default:               ltssm_next = LTSSM_DETECT_QUIET;
    endcase
  end

  assign link_up    = (ltssm_state == LTSSM_L0);
  assign link_gen   = 4'd6;
  assign link_width = 5'd16;
  assign link_speed = 2'd3;

  assign tx_lcrc = crc32(tx_tlp_data);

  assign tx_tlp_ready = link_up && (!rx_tlp_valid || rx_tlp_ready);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      tx_p <= '0;
    else if (tx_tlp_valid && tx_tlp_ready)
      tx_p <= tx_tlp_data[NUM_LANES-1:0];
  end
  assign tx_n = ~tx_p;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_tlp_valid  <= 1'b0;
      rx_tlp_data   <= '0;
      rx_tlp_type   <= '0;
      rx_tlp_length <= '0;
      rx_lcrc       <= '0;
    end else begin
      if (rx_tlp_valid && rx_tlp_ready)
        rx_tlp_valid <= 1'b0;

      if (!rx_tlp_valid && tx_tlp_valid && tx_tlp_ready) begin
        rx_tlp_valid  <= 1'b1;
        rx_tlp_data   <= tx_tlp_data;
        rx_tlp_type   <= tx_tlp_type;
        rx_tlp_length <= tx_tlp_length;
        rx_lcrc       <= tx_lcrc;
      end
    end
  end

  assign lane_pair_error =
      link_up && ((rx_p ^ rx_n) !== {NUM_LANES{1'b1}});
  assign malformed_tlp_error =
      link_up && tx_tlp_valid && tx_tlp_ready &&
      ((tx_tlp_length == 16'd0) || (tx_tlp_length > 16'd1024));
  assign crc_error =
      link_up && rx_tlp_valid && rx_tlp_ready &&
      (crc32(rx_tlp_data) != rx_lcrc);
  assign rx_overflow_error =
      link_up && tx_tlp_valid && tx_tlp_ready &&
      rx_tlp_valid && !rx_tlp_ready;

  assign correctable_error   = lane_pair_error;
  assign uncorrectable_error = malformed_tlp_error || crc_error || rx_overflow_error;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      error_count <= '0;
    else if (correctable_error || uncorrectable_error)
      error_count <= error_count + 1'b1;
  end

endmodule : pcie_gen6_phy

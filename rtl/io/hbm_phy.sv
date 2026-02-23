`timescale 1ns/1ps

module hbm_phy
  import agni_pkg::*;
#(
  parameter int unsigned DQ_WIDTH      = 64,
  parameter int unsigned ADDR_WIDTH    = 18,
  parameter int unsigned BA_WIDTH      = 4,
  parameter int unsigned BURST_LENGTH  = 8,
  parameter int unsigned TRAIN_PATTERNS = 16
)(
  input  logic        phy_clk,
  input  logic        rst_n,

  input  logic        ctrl_cmd_valid,
  input  logic [1:0]  ctrl_cmd,
  input  logic [ADDR_WIDTH-1:0] ctrl_addr,
  input  logic [BA_WIDTH-1:0]   ctrl_ba,
  input  logic [DQ_WIDTH*BURST_LENGTH-1:0] ctrl_wdata,
  input  logic [DQ_WIDTH*BURST_LENGTH/8-1:0] ctrl_wstrb,
  output logic        ctrl_cmd_ready,
  output logic        ctrl_rdata_valid,
  output logic [DQ_WIDTH*BURST_LENGTH-1:0] ctrl_rdata,

  output logic        hbm_ck_p, hbm_ck_n,
  output logic        hbm_cke,
  output logic [1:0]  hbm_cmd_out,
  output logic [ADDR_WIDTH-1:0] hbm_addr_out,
  output logic [BA_WIDTH-1:0]   hbm_ba_out,
  output logic        hbm_dq_oe,
  output logic [DQ_WIDTH-1:0]   hbm_dq_out,
  input  logic [DQ_WIDTH-1:0]   hbm_dq_in,
  output logic [DQ_WIDTH/8-1:0] hbm_dqs_out,
  input  logic [DQ_WIDTH/8-1:0] hbm_dqs_in,

  input  logic        train_start,
  output logic        train_done,
  output logic        train_pass,
  output logic [7:0]  train_status,

  input  logic [7:0]  temperature,
  output logic [15:0] refresh_interval,

  output logic        phy_ready,
  output logic [31:0] dq_delay_taps,
  output logic [31:0] dqs_delay_taps
);

  typedef enum logic [2:0] {
    PHY_RESET     = 3'b000,
    PHY_INIT      = 3'b001,
    PHY_TRAIN_WL  = 3'b010,
    PHY_TRAIN_RD  = 3'b011,
    PHY_TRAIN_WR  = 3'b100,
    PHY_READY     = 3'b101,
    PHY_ERROR     = 3'b110
  } phy_state_t;

  phy_state_t state, state_next;
  logic [15:0] state_timer;
  logic [3:0]  train_step;

  always_ff @(posedge phy_clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= PHY_RESET;
      state_timer <= '0;
      train_step  <= '0;
    end else begin
      state <= state_next;
      if (state != state_next) begin
        state_timer <= '0;
        train_step  <= '0;
      end else begin
        state_timer <= state_timer + 1;
      end
    end
  end

  always_comb begin
    state_next = state;
    case (state)
      PHY_RESET:    if (state_timer > 100)  state_next = PHY_INIT;
      PHY_INIT: begin
        if (state_timer > 200) begin
          if (train_start) state_next = PHY_TRAIN_WL;
        end
      end
      PHY_TRAIN_WL: if (state_timer > 500)  state_next = PHY_TRAIN_RD;
      PHY_TRAIN_RD: if (state_timer > 500)  state_next = PHY_TRAIN_WR;
      PHY_TRAIN_WR: if (state_timer > 500)  state_next = PHY_READY;
      PHY_READY:    ;
      PHY_ERROR:    if (state_timer > 1000) state_next = PHY_RESET;
    endcase
  end

  assign phy_ready   = (state == PHY_READY);
  assign train_done  = (state == PHY_READY);
  assign train_pass  = (state == PHY_READY);

  logic [31:0] lfsr;

  always_ff @(posedge phy_clk or negedge rst_n) begin
    if (!rst_n) begin
      lfsr <= 32'hDEAD_CAFE;
    end else begin

      lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    end
  end

  always_ff @(posedge phy_clk or negedge rst_n) begin
    if (!rst_n) begin
      dq_delay_taps  <= 32'd16;
      dqs_delay_taps <= 32'd16;
    end else if (state == PHY_TRAIN_RD) begin

      dq_delay_taps  <= 32'd15 + lfsr[3:0];
      dqs_delay_taps <= 32'd15 + lfsr[7:4];
    end
  end

  always_comb begin
    if (temperature > 95)
      refresh_interval = 16'd4800;
    else if (temperature > 85)
      refresh_interval = 16'd9600;
    else
      refresh_interval = 16'd19200;
  end

  localparam MEM_SIZE = 1024;
  logic [DQ_WIDTH*BURST_LENGTH-1:0] mem_array [0:MEM_SIZE-1];
  logic [9:0] mem_addr;

  assign mem_addr = {ctrl_ba[1:0], ctrl_addr[7:0]};

  always_ff @(posedge phy_clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_rdata_valid <= 1'b0;
      ctrl_rdata       <= '0;
    end else if (phy_ready && ctrl_cmd_valid) begin
      case (ctrl_cmd)
        2'b10: begin
          ctrl_rdata_valid <= 1'b1;
          ctrl_rdata       <= mem_array[mem_addr];
        end
        2'b11: begin
          ctrl_rdata_valid <= 1'b0;

          for (int b = 0; b < DQ_WIDTH*BURST_LENGTH/8; b++) begin
            if (ctrl_wstrb[b])
              mem_array[mem_addr][b*8 +: 8] <= ctrl_wdata[b*8 +: 8];
          end
        end
        default: begin
          ctrl_rdata_valid <= 1'b0;
        end
      endcase
    end else begin
      ctrl_rdata_valid <= 1'b0;
    end
  end

  assign ctrl_cmd_ready = phy_ready;

  assign hbm_ck_p    = phy_clk;
  assign hbm_ck_n    = ~phy_clk;
  assign hbm_cke     = phy_ready;
  assign hbm_cmd_out = ctrl_cmd;
  assign hbm_addr_out = ctrl_addr;
  assign hbm_ba_out  = ctrl_ba;

  assign hbm_dq_oe  = (ctrl_cmd == 2'b11) && ctrl_cmd_valid;
  assign hbm_dq_out = ctrl_wdata[DQ_WIDTH-1:0];
  assign hbm_dqs_out = {(DQ_WIDTH/8){phy_clk}};

  always_comb begin
    case (state)
      PHY_RESET:    train_status = 8'h01;
      PHY_INIT:     train_status = 8'h02;
      PHY_TRAIN_WL: train_status = 8'h10;
      PHY_TRAIN_RD: train_status = 8'h20;
      PHY_TRAIN_WR: train_status = 8'h30;
      PHY_READY:    train_status = 8'hFF;
      PHY_ERROR:    train_status = 8'hEE;
      default:      train_status = 8'h00;
    endcase
  end

endmodule : hbm_phy

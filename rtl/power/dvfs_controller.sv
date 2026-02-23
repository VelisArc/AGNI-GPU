`timescale 1ns/1ps

module dvfs_controller
  import agni_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  pstate_t     target_pstate,
  input  logic        pstate_req_valid,

  input  thermal_zone_t thermal_zone,

  output logic [7:0]  voltage_target,
  output logic        voltage_req,
  input  logic        voltage_stable,

  output logic [11:0] freq_target_mhz,
  output logic        freq_req,
  input  logic        freq_locked,

  output pstate_t     current_pstate,
  output logic        transition_busy
);

  typedef struct packed {
    logic [7:0]  voltage;
    logic [11:0] frequency;
  } pstate_config_t;

  logic [7:0]  pstate_voltage  [0:5];
  logic [11:0] pstate_frequency [0:5];

  assign pstate_voltage[0] = 8'd136; assign pstate_frequency[0] = 12'd2600;
  assign pstate_voltage[1] = 8'd120; assign pstate_frequency[1] = 12'd1800;
  assign pstate_voltage[2] = 8'd112; assign pstate_frequency[2] = 12'd1200;
  assign pstate_voltage[3] = 8'd104; assign pstate_frequency[3] = 12'd800;
  assign pstate_voltage[4] = 8'd96;  assign pstate_frequency[4] = 12'd300;
  assign pstate_voltage[5] = 8'd0;   assign pstate_frequency[5] = 12'd0;

  typedef enum logic [2:0] {
    DVFS_IDLE       = 3'b000,
    DVFS_RAMP_UP    = 3'b001,
    DVFS_FREQ_UP    = 3'b010,
    DVFS_FREQ_DOWN  = 3'b011,
    DVFS_RAMP_DOWN  = 3'b100,
    DVFS_SETTLE     = 3'b101
  } dvfs_state_t;

  dvfs_state_t state, state_next;
  pstate_t     cur_pstate, tgt_pstate;
  logic        going_up;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= DVFS_IDLE;
      cur_pstate <= PSTATE_IDLE;
    end else begin
      state <= state_next;
      if (state == DVFS_SETTLE && freq_locked && voltage_stable)
        cur_pstate <= tgt_pstate;
    end
  end

  always_comb begin
    state_next = state;
    going_up   = (tgt_pstate < cur_pstate);

    case (state)
      DVFS_IDLE: begin
        if (pstate_req_valid && target_pstate != cur_pstate) begin
          tgt_pstate = target_pstate;

          if (thermal_zone >= THERM_THROTTLE &&
              target_pstate < PSTATE_BASE)
            tgt_pstate = PSTATE_BASE;
          if (thermal_zone >= THERM_EMERGENCY)
            tgt_pstate = PSTATE_IDLE;

          if (tgt_pstate != cur_pstate) begin
            if (going_up)
              state_next = DVFS_RAMP_UP;
            else
              state_next = DVFS_FREQ_DOWN;
          end
        end
      end

      DVFS_RAMP_UP: begin
        if (voltage_stable) state_next = DVFS_FREQ_UP;
      end
      DVFS_FREQ_UP: begin
        if (freq_locked) state_next = DVFS_SETTLE;
      end

      DVFS_FREQ_DOWN: begin
        if (freq_locked) state_next = DVFS_RAMP_DOWN;
      end
      DVFS_RAMP_DOWN: begin
        if (voltage_stable) state_next = DVFS_SETTLE;
      end

      DVFS_SETTLE: begin
        state_next = DVFS_IDLE;
      end

      default: state_next = DVFS_IDLE;
    endcase
  end

  assign voltage_target  = pstate_voltage[tgt_pstate];
  assign voltage_req     = (state == DVFS_RAMP_UP || state == DVFS_RAMP_DOWN);
  assign freq_target_mhz = pstate_frequency[tgt_pstate];
  assign freq_req        = (state == DVFS_FREQ_UP || state == DVFS_FREQ_DOWN);
  assign current_pstate  = cur_pstate;
  assign transition_busy = (state != DVFS_IDLE);

endmodule : dvfs_controller

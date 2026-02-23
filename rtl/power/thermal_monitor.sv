`timescale 1ns/1ps

module thermal_monitor
  import agni_pkg::*;
#(
  parameter int unsigned NUM_SENSORS = 64
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic [7:0]  sensor_temp [NUM_SENSORS],

  output thermal_zone_t thermal_zone,
  output logic [7:0]    max_temp,
  output logic [7:0]    avg_temp,

  output logic          throttle_req,
  output logic          emergency_req,
  output logic          shutdown_req,
  output pstate_t       recommended_pstate
);

  logic [7:0]  max_val;
  logic [15:0] sum_val;
  logic [7:0]  avg_val;

  always @* begin
    max_val = 8'd0;
    sum_val = 16'd0;

    for (int i = 0; i < NUM_SENSORS; i++) begin
      if (sensor_temp[i] > max_val)
        max_val = sensor_temp[i];
      sum_val = sum_val + {8'b0, sensor_temp[i]};
    end

    avg_val = sum_val[13:6];
  end

  thermal_zone_t zone;

  always @* begin
    if (max_val >= 8'd95)
      zone = THERM_SHUTDOWN;
    else if (max_val >= 8'd83)
      zone = THERM_EMERGENCY;
    else if (max_val >= 8'd75)
      zone = THERM_THROTTLE;
    else if (max_val >= 8'd65)
      zone = THERM_NORMAL;
    else
      zone = THERM_SAFE;
  end

  pstate_t rec_pstate;

  always @* begin
    case (zone)
      THERM_SAFE:      rec_pstate = PSTATE_BOOST;
      THERM_NORMAL:    rec_pstate = PSTATE_BASE;
      THERM_THROTTLE:  rec_pstate = PSTATE_P1;
      THERM_EMERGENCY: rec_pstate = PSTATE_IDLE;
      THERM_SHUTDOWN:  rec_pstate = PSTATE_OFF;
      default:         rec_pstate = PSTATE_BASE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      thermal_zone       <= THERM_SAFE;
      max_temp           <= 8'd25;
      avg_temp           <= 8'd25;
      throttle_req       <= 1'b0;
      emergency_req      <= 1'b0;
      shutdown_req       <= 1'b0;
      recommended_pstate <= PSTATE_BASE;
    end else begin
      thermal_zone       <= zone;
      max_temp           <= max_val;
      avg_temp           <= avg_val;
      throttle_req       <= (zone >= THERM_THROTTLE);
      emergency_req      <= (zone >= THERM_EMERGENCY);
      shutdown_req       <= (zone == THERM_SHUTDOWN);
      recommended_pstate <= rec_pstate;
    end
  end

endmodule : thermal_monitor



`timescale 1ns/1ps

module agni_gpu_top
  import agni_pkg::*;
(

  input  logic        core_clk,
  input  logic        mem_clk,
  input  logic        io_clk,
  input  logic        rst_n,

  input  logic [15:0] pcie_rx_p,
  input  logic [15:0] pcie_rx_n,
  output logic [15:0] pcie_tx_p,
  output logic [15:0] pcie_tx_n,

  input  logic [17:0] nvlink_rx_p,
  input  logic [17:0] nvlink_rx_n,
  output logic [17:0] nvlink_tx_p,
  output logic [17:0] nvlink_tx_n,

  output logic [11:0]          hbm_ck,
  output logic [11:0]          hbm_cke,
  output logic [11:0][1:0]     hbm_cmd,
  output logic [11:0][17:0]    hbm_addr,
  output logic [11:0][3:0]     hbm_ba,
  output logic [11:0][511:0]   hbm_dq_out,
  input  logic [11:0][511:0]   hbm_dq_in,
  output logic [11:0]          hbm_dq_oe,

  input  logic [7:0]  die_temp_sensors [64],
  input  logic [7:0]  hbm_temp_sensors [6],

  output logic [7:0]  pmu_voltage_target,
  output logic        pmu_voltage_req,
  input  logic        pmu_voltage_stable,

  output pstate_t     current_pstate,
  output thermal_zone_t current_thermal_zone,
  output logic [31:0] total_ecc_ce_count,
  output logic [31:0] total_ecc_ue_count,
  output logic        fatal_error
);

  logic core_rst_n, mem_rst_n, io_rst_n;

  reset_sync u_core_rst (.clk(core_clk), .rst_async_n(rst_n), .rst_sync_n(core_rst_n));
  reset_sync u_mem_rst  (.clk(mem_clk),  .rst_async_n(rst_n), .rst_sync_n(mem_rst_n));
  reset_sync u_io_rst   (.clk(io_clk),   .rst_async_n(rst_n), .rst_sync_n(io_rst_n));

  thermal_zone_t thermal_zone;
  logic [7:0]    max_temp, avg_temp;
  logic          throttle_req, emergency_req, shutdown_req;
  pstate_t       recommended_pstate;

  thermal_monitor #(.NUM_SENSORS(64)) u_thermal (
    .clk              (core_clk),
    .rst_n            (core_rst_n),
    .sensor_temp      (die_temp_sensors),
    .thermal_zone     (thermal_zone),
    .max_temp         (max_temp),
    .avg_temp         (avg_temp),
    .throttle_req     (throttle_req),
    .emergency_req    (emergency_req),
    .shutdown_req     (shutdown_req),
    .recommended_pstate(recommended_pstate)
  );

  assign current_thermal_zone = thermal_zone;

  logic [11:0] freq_target;
  logic        freq_req, freq_locked;
  logic [7:0]  pll_freq_mult;
  logic [31:0] pll_out_freq_khz;
  logic        pll_core_clk;

  dvfs_controller u_dvfs (
    .clk             (core_clk),
    .rst_n           (core_rst_n),
    .target_pstate   (recommended_pstate),
    .pstate_req_valid(throttle_req || emergency_req),
    .thermal_zone    (thermal_zone),
    .voltage_target  (pmu_voltage_target),
    .voltage_req     (pmu_voltage_req),
    .voltage_stable  (pmu_voltage_stable),
    .freq_target_mhz(freq_target),
    .freq_req        (freq_req),
    .freq_locked     (freq_locked),
    .current_pstate  (current_pstate),
    .transition_busy ()
  );

  always @* begin
    if (freq_target < 12'd100)
      pll_freq_mult = 8'd1;
    else
      pll_freq_mult = freq_target / 12'd100;
  end

  pll_model u_core_pll (
    .ref_clk      (core_clk),
    .rst_n        (core_rst_n),
    .enable       (1'b1),
    .freq_mult    (pll_freq_mult),
    .freq_div     (4'd1),
    .freq_update  (freq_req),
    .out_clk      (pll_core_clk),
    .locked       (freq_locked),
    .out_freq_khz (pll_out_freq_khz)
  );

  logic [NUM_GPCS-1:0] gpc_ecc_ce, gpc_ecc_ue;
  logic [NUM_GPCS-1:0] gpc_block_ready;
  logic [NUM_GPCS-1:0] gpc_block_sent;
  logic                gpc_noc_req_valid [NUM_GPCS];
  logic                gpc_noc_req_ready [NUM_GPCS];
  logic                gpc_noc_resp_valid [NUM_GPCS];
  logic [47:0]         gpc_req_addr       [NUM_GPCS];
  logic [2:0]          gpc_req_op         [NUM_GPCS];
  logic [6:0]          gpc_req_warp_id    [NUM_GPCS];
  logic [4:0]          gpc_req_lane_id    [NUM_GPCS];
  logic [127:0]        gpc_req_wdata      [NUM_GPCS];
  logic [15:0]         gpc_req_byte_enable[NUM_GPCS];
  logic [127:0]        gpc_resp_rdata     [NUM_GPCS];
  logic [6:0]          gpc_resp_warp_id   [NUM_GPCS];
  logic [4:0]          gpc_resp_lane_id   [NUM_GPCS];
  logic                gpc_resp_hit       [NUM_GPCS];
  logic                gpc_resp_error     [NUM_GPCS];

  logic                hbm_req_valid_i    [HBM_CONTROLLERS];
  logic [47:0]         hbm_req_addr_i     [HBM_CONTROLLERS];
  logic                hbm_req_we_i       [HBM_CONTROLLERS];
  logic [511:0]        hbm_req_wdata_i    [HBM_CONTROLLERS];
  logic                hbm_req_ready_o    [HBM_CONTROLLERS];
  logic                hbm_resp_valid_o   [HBM_CONTROLLERS];
  logic [511:0]        hbm_resp_data_o    [HBM_CONTROLLERS];
  ecc_error_t          hbm_resp_status_o  [HBM_CONTROLLERS];

  localparam int unsigned HBM_REQ_PKT_W = 573;
  localparam int unsigned HBM_REQ_ADDR_LSB = 0;
  localparam int unsigned HBM_REQ_ADDR_MSB = 47;
  localparam int unsigned HBM_REQ_WE_BIT   = 48;
  localparam int unsigned HBM_REQ_WDATA_LSB = 49;
  localparam int unsigned HBM_REQ_WDATA_MSB = 560;
  localparam int unsigned HBM_REQ_LANE_LSB  = 561;
  localparam int unsigned HBM_REQ_LANE_MSB  = 565;
  localparam int unsigned HBM_REQ_WARP_LSB  = 566;
  localparam int unsigned HBM_REQ_WARP_MSB  = 572;

  localparam int unsigned HBM_RESP_PKT_W = 526;
  localparam int unsigned HBM_RESP_DATA_LSB = 0;
  localparam int unsigned HBM_RESP_DATA_MSB = 511;
  localparam int unsigned HBM_RESP_STATUS_LSB = 512;
  localparam int unsigned HBM_RESP_STATUS_MSB = 513;
  localparam int unsigned HBM_RESP_LANE_LSB = 514;
  localparam int unsigned HBM_RESP_LANE_MSB = 518;
  localparam int unsigned HBM_RESP_WARP_LSB = 519;
  localparam int unsigned HBM_RESP_WARP_MSB = 525;

  logic [HBM_REQ_PKT_W-1:0]  hbm_req_cdc_wr_data [HBM_CONTROLLERS];
  logic [HBM_REQ_PKT_W-1:0]  hbm_req_cdc_rd_data [HBM_CONTROLLERS];
  logic                      hbm_req_cdc_wr_en   [HBM_CONTROLLERS];
  logic                      hbm_req_cdc_rd_en   [HBM_CONTROLLERS];
  logic                      hbm_req_cdc_wr_full [HBM_CONTROLLERS];
  logic                      hbm_req_cdc_rd_empty[HBM_CONTROLLERS];

  logic [HBM_RESP_PKT_W-1:0] hbm_resp_cdc_wr_data [HBM_CONTROLLERS];
  logic [HBM_RESP_PKT_W-1:0] hbm_resp_cdc_rd_data [HBM_CONTROLLERS];
  logic                      hbm_resp_cdc_wr_en   [HBM_CONTROLLERS];
  logic                      hbm_resp_cdc_rd_en   [HBM_CONTROLLERS];
  logic                      hbm_resp_cdc_wr_full [HBM_CONTROLLERS];
  logic                      hbm_resp_cdc_rd_empty[HBM_CONTROLLERS];

  always_ff @(posedge core_clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      gpc_block_sent <= '0;
    end else begin
      for (int i = 0; i < NUM_GPCS; i++) begin
        if (!gpc_block_sent[i] && gpc_block_ready[i])
          gpc_block_sent[i] <= 1'b1;
      end
    end
  end

  genvar gg;
  generate
    for (gg = 0; gg < NUM_GPCS; gg++) begin : g_gpc
      gpc #(
        .GPC_ID (gg)
      ) u_gpc (
        .clk               (core_clk),
        .rst_n             (core_rst_n),
        .block_valid       (!gpc_block_sent[gg]),
        .block_id          (gg[4:0]),
        .block_warps       (6'd8),
        .block_ready       (gpc_block_ready[gg]),
        .noc_req_valid     (gpc_noc_req_valid[gg]),
        .noc_req_addr      (gpc_req_addr[gg]),
        .noc_req_op        (gpc_req_op[gg]),
        .noc_req_warp_id   (gpc_req_warp_id[gg]),
        .noc_req_lane_id   (gpc_req_lane_id[gg]),
        .noc_req_wdata     (gpc_req_wdata[gg]),
        .noc_req_byte_enable(gpc_req_byte_enable[gg]),
        .noc_req_ready     (gpc_noc_req_ready[gg]),
        .noc_resp_valid    (gpc_noc_resp_valid[gg]),
        .noc_resp_rdata    (gpc_resp_rdata[gg]),
        .noc_resp_warp_id  (gpc_resp_warp_id[gg]),
        .noc_resp_lane_id  (gpc_resp_lane_id[gg]),
        .noc_resp_hit      (gpc_resp_hit[gg]),
        .noc_resp_error    (gpc_resp_error[gg]),
        .ecc_ce            (gpc_ecc_ce[gg]),
        .ecc_ue            (gpc_ecc_ue[gg]),
        .perf_total_active_warps (),
        .perf_total_instructions ()
      );
    end
  endgenerate

  logic [31:0]  noc_local_valid_in;
  noc_flit_t    noc_local_flit_in  [32];
  logic [31:0]  noc_local_valid_out;
  noc_flit_t    noc_local_flit_out [32];

  noc_mesh u_noc (
    .clk             (core_clk),
    .rst_n           (core_rst_n),
    .local_valid_in  (noc_local_valid_in),
    .local_flit_in   (noc_local_flit_in),
    .local_valid_out (noc_local_valid_out),
    .local_flit_out  (noc_local_flit_out)
  );

  always @* begin
    noc_local_valid_in = '0;
    for (int n = 0; n < 32; n++) begin
      noc_local_flit_in[n] = '0;
    end

    for (int i = 0; i < NUM_GPCS; i++) begin
      noc_local_valid_in[i] = gpc_noc_req_valid[i];
    end
  end

  logic [31:0] hbm_ecc_ce [HBM_CONTROLLERS];
  logic [31:0] hbm_ecc_ue [HBM_CONTROLLERS];
  logic [7:0]  hbm_temp_for_ctrl [HBM_CONTROLLERS];

  always @* begin
    for (int i = 0; i < NUM_GPCS; i++) begin
      gpc_noc_req_ready[i]  = 1'b1;
      gpc_noc_resp_valid[i] = 1'b0;
      gpc_resp_rdata[i]     = '0;
      gpc_resp_warp_id[i]   = '0;
      gpc_resp_lane_id[i]   = '0;
      gpc_resp_hit[i]       = 1'b0;
      gpc_resp_error[i]     = 1'b0;
    end

    for (int c = 0; c < HBM_CONTROLLERS; c++) begin
      hbm_req_cdc_wr_data[c] = '0;
      hbm_req_cdc_wr_data[c][HBM_REQ_ADDR_MSB:HBM_REQ_ADDR_LSB]   = gpc_req_addr[c];
      hbm_req_cdc_wr_data[c][HBM_REQ_WE_BIT]                      = (gpc_req_op[c] == MEM_STORE);
      hbm_req_cdc_wr_data[c][HBM_REQ_WDATA_MSB:HBM_REQ_WDATA_LSB] = {4{gpc_req_wdata[c]}};
      hbm_req_cdc_wr_data[c][HBM_REQ_LANE_MSB:HBM_REQ_LANE_LSB]   = gpc_req_lane_id[c];
      hbm_req_cdc_wr_data[c][HBM_REQ_WARP_MSB:HBM_REQ_WARP_LSB]   = gpc_req_warp_id[c];
      hbm_req_cdc_wr_en[c] = gpc_noc_req_valid[c] && !hbm_req_cdc_wr_full[c];

      gpc_noc_req_ready[c]  = !hbm_req_cdc_wr_full[c];
      hbm_resp_cdc_rd_en[c] = !hbm_resp_cdc_rd_empty[c];

      if (!hbm_resp_cdc_rd_empty[c]) begin
        gpc_noc_resp_valid[c] = 1'b1;
        gpc_resp_rdata[c]     = hbm_resp_cdc_rd_data[c][127:0];
        gpc_resp_warp_id[c]   = hbm_resp_cdc_rd_data[c][HBM_RESP_WARP_MSB:HBM_RESP_WARP_LSB];
        gpc_resp_lane_id[c]   = hbm_resp_cdc_rd_data[c][HBM_RESP_LANE_MSB:HBM_RESP_LANE_LSB];
        gpc_resp_error[c]     = (hbm_resp_cdc_rd_data[c][HBM_RESP_STATUS_MSB:HBM_RESP_STATUS_LSB] == ECC_DETECTED) ||
                                (hbm_resp_cdc_rd_data[c][HBM_RESP_STATUS_MSB:HBM_RESP_STATUS_LSB] == ECC_POISON);
        gpc_resp_hit[c]       = !gpc_resp_error[c];
      end
    end
  end

  generate
    for (gg = 0; gg < HBM_CONTROLLERS; gg++) begin : g_hbm
      logic [6:0] req_warp_id_mem;
      logic [4:0] req_lane_id_mem;
      logic [11:0] tag_fifo_rd_data;
      logic        tag_fifo_full, tag_fifo_empty;
      logic        tag_fifo_wr_en, tag_fifo_rd_en;

      if (gg < HBM_STACKS) begin : g_temp_real
        assign hbm_temp_for_ctrl[gg] = hbm_temp_sensors[gg];
      end else begin : g_temp_default
        assign hbm_temp_for_ctrl[gg] = 8'd25;
      end

      async_fifo #(
        .WIDTH (HBM_REQ_PKT_W),
        .DEPTH (16)
      ) u_req_cdc (
        .wr_clk   (core_clk),
        .wr_rst_n (core_rst_n),
        .wr_en    (hbm_req_cdc_wr_en[gg]),
        .wr_data  (hbm_req_cdc_wr_data[gg]),
        .wr_full  (hbm_req_cdc_wr_full[gg]),
        .rd_clk   (mem_clk),
        .rd_rst_n (mem_rst_n),
        .rd_en    (hbm_req_cdc_rd_en[gg]),
        .rd_data  (hbm_req_cdc_rd_data[gg]),
        .rd_empty (hbm_req_cdc_rd_empty[gg])
      );

      assign hbm_req_valid_i[gg] = !hbm_req_cdc_rd_empty[gg];
      assign hbm_req_addr_i[gg]  = hbm_req_cdc_rd_data[gg][HBM_REQ_ADDR_MSB:HBM_REQ_ADDR_LSB];
      assign hbm_req_we_i[gg]    = hbm_req_cdc_rd_data[gg][HBM_REQ_WE_BIT];
      assign hbm_req_wdata_i[gg] = hbm_req_cdc_rd_data[gg][HBM_REQ_WDATA_MSB:HBM_REQ_WDATA_LSB];
      assign req_lane_id_mem     = hbm_req_cdc_rd_data[gg][HBM_REQ_LANE_MSB:HBM_REQ_LANE_LSB];
      assign req_warp_id_mem     = hbm_req_cdc_rd_data[gg][HBM_REQ_WARP_MSB:HBM_REQ_WARP_LSB];
      assign hbm_req_cdc_rd_en[gg] = hbm_req_ready_o[gg] && !hbm_req_cdc_rd_empty[gg];

      assign tag_fifo_wr_en = hbm_req_cdc_rd_en[gg];

      fifo #(
        .WIDTH (12),
        .DEPTH (32)
      ) u_tag_fifo (
        .clk          (mem_clk),
        .rst_n        (mem_rst_n),
        .wr_en        (tag_fifo_wr_en),
        .wr_data      ({req_warp_id_mem, req_lane_id_mem}),
        .rd_en        (tag_fifo_rd_en),
        .rd_data      (tag_fifo_rd_data),
        .full         (tag_fifo_full),
        .empty        (tag_fifo_empty),
        .almost_full  (),
        .almost_empty (),
        .count        ()
      );

      hbm4_controller #(
        .CTRL_ID (gg)
      ) u_hbm_ctrl (
        .clk             (mem_clk),
        .rst_n           (mem_rst_n),
        .req_valid       (hbm_req_valid_i[gg]),
        .req_addr        (hbm_req_addr_i[gg]),
        .req_we          (hbm_req_we_i[gg]),
        .req_wdata       (hbm_req_wdata_i[gg]),
        .req_ready       (hbm_req_ready_o[gg]),
        .resp_valid      (hbm_resp_valid_o[gg]),
        .resp_data       (hbm_resp_data_o[gg]),
        .resp_ecc_status (hbm_resp_status_o[gg]),
        .hbm_ck          (hbm_ck[gg]),
        .hbm_cke         (hbm_cke[gg]),
        .hbm_cmd         (hbm_cmd[gg]),
        .hbm_addr        (hbm_addr[gg]),
        .hbm_ba          (hbm_ba[gg]),
        .hbm_dq_out      (hbm_dq_out[gg]),
        .hbm_dq_in       (hbm_dq_in[gg]),
        .hbm_dq_oe       (hbm_dq_oe[gg]),
        .hbm_temp        (hbm_temp_for_ctrl[gg]),
        .ecc_ce_count    (hbm_ecc_ce[gg]),
        .ecc_ue_count    (hbm_ecc_ue[gg])
      );

      assign hbm_resp_cdc_wr_en[gg] = hbm_resp_valid_o[gg] &&
                                      !hbm_resp_cdc_wr_full[gg] &&
                                      !tag_fifo_empty;
      assign tag_fifo_rd_en = hbm_resp_cdc_wr_en[gg];
      assign hbm_resp_cdc_wr_data[gg] = {tag_fifo_rd_data[11:5],
                                         tag_fifo_rd_data[4:0],
                                         hbm_resp_status_o[gg],
                                         hbm_resp_data_o[gg]};

      async_fifo #(
        .WIDTH (HBM_RESP_PKT_W),
        .DEPTH (16)
      ) u_resp_cdc (
        .wr_clk   (mem_clk),
        .wr_rst_n (mem_rst_n),
        .wr_en    (hbm_resp_cdc_wr_en[gg]),
        .wr_data  (hbm_resp_cdc_wr_data[gg]),
        .wr_full  (hbm_resp_cdc_wr_full[gg]),
        .rd_clk   (core_clk),
        .rd_rst_n (core_rst_n),
        .rd_en    (hbm_resp_cdc_rd_en[gg]),
        .rd_data  (hbm_resp_cdc_rd_data[gg]),
        .rd_empty (hbm_resp_cdc_rd_empty[gg])
      );

      always @(posedge core_clk) begin
        if (core_rst_n && gpc_noc_req_valid[gg] && hbm_req_cdc_wr_full[gg])
          $error("TOP CDC[%0d]: request FIFO overflow", gg);
      end

      always @(posedge mem_clk) begin
        if (mem_rst_n && hbm_resp_valid_o[gg] && tag_fifo_empty)
          $error("TOP CDC[%0d]: response without matching tag", gg);
        if (mem_rst_n && hbm_resp_valid_o[gg] && hbm_resp_cdc_wr_full[gg])
          $error("TOP CDC[%0d]: response FIFO overflow", gg);
        if (mem_rst_n && tag_fifo_wr_en && tag_fifo_full)
          $error("TOP CDC[%0d]: tag FIFO overflow", gg);
      end

    end
  endgenerate

  always_ff @(posedge core_clk or negedge core_rst_n) begin
    if (!core_rst_n) begin
      total_ecc_ce_count <= '0;
      total_ecc_ue_count <= '0;
    end else begin
      logic [31:0] ce_next;
      logic [31:0] ue_next;
      ce_next = total_ecc_ce_count;
      ue_next = total_ecc_ue_count;
      for (int i = 0; i < HBM_CONTROLLERS; i++) begin
        if (hbm_resp_cdc_rd_en[i]) begin
          if (hbm_resp_cdc_rd_data[i][HBM_RESP_STATUS_MSB:HBM_RESP_STATUS_LSB] == ECC_CORRECTED)
            ce_next = ce_next + 1'b1;
          else if ((hbm_resp_cdc_rd_data[i][HBM_RESP_STATUS_MSB:HBM_RESP_STATUS_LSB] == ECC_DETECTED) ||
                   (hbm_resp_cdc_rd_data[i][HBM_RESP_STATUS_MSB:HBM_RESP_STATUS_LSB] == ECC_POISON))
            ue_next = ue_next + 1'b1;
        end
      end
      total_ecc_ce_count <= ce_next;
      total_ecc_ue_count <= ue_next;
    end
  end

  assign fatal_error = |gpc_ecc_ue || (total_ecc_ue_count > 0) || shutdown_req;

  logic               pcie_tx_tlp_valid, pcie_tx_tlp_ready;
  logic [255:0]       pcie_tx_tlp_data;
  logic [7:0]         pcie_tx_tlp_type;
  logic [15:0]        pcie_tx_tlp_length;
  logic               pcie_rx_tlp_valid;
  logic [255:0]       pcie_rx_tlp_data;
  logic [7:0]         pcie_rx_tlp_type;
  logic [15:0]        pcie_rx_tlp_length;

  logic               nv_tx_flit_valid, nv_tx_flit_ready;
  logic [127:0]       nv_tx_flit_data;
  logic [3:0]         nv_tx_flit_vc;
  logic               nv_rx_flit_valid;
  logic [127:0]       nv_rx_flit_data;
  logic [3:0]         nv_rx_flit_vc;
  logic [5:0]         nv_tx_credits;
  logic               nv_link_error;
  logic [7:0]         nv_error_syndrome;
  logic [31:0]        nv_error_count;
  logic               nv_low_power;
  noc_flit_t          noc0_flit;
  noc_flit_t          noc1_flit;
  localparam int unsigned NOC_PAYLOAD_W = NOC_FLIT_WIDTH - 14;

  always @* begin
    noc0_flit            = noc_local_flit_out[0];
    noc1_flit            = noc_local_flit_out[1];
    pcie_tx_tlp_data        = '0;
    pcie_tx_tlp_data[NOC_PAYLOAD_W-1:0] = noc0_flit.payload;
    pcie_tx_tlp_valid       = noc_local_valid_out[0];
    pcie_tx_tlp_type        = {4'b0, noc0_flit.flit_type, noc0_flit.vc_id};
    pcie_tx_tlp_length      = 16'd32;

    nv_tx_flit_valid        = noc_local_valid_out[1];
    nv_tx_flit_data         = noc1_flit.payload[127:0];
    nv_tx_flit_vc           = {2'b00, noc1_flit.vc_id};
  end

  pcie_gen6_phy u_pcie_phy (
    .clk                 (io_clk),
    .rst_n               (io_rst_n),
    .rx_p                (pcie_rx_p),
    .rx_n                (pcie_rx_n),
    .tx_p                (pcie_tx_p),
    .tx_n                (pcie_tx_n),
    .tx_tlp_valid        (pcie_tx_tlp_valid),
    .tx_tlp_data         (pcie_tx_tlp_data),
    .tx_tlp_type         (pcie_tx_tlp_type),
    .tx_tlp_length       (pcie_tx_tlp_length),
    .tx_tlp_ready        (pcie_tx_tlp_ready),
    .rx_tlp_valid        (pcie_rx_tlp_valid),
    .rx_tlp_data         (pcie_rx_tlp_data),
    .rx_tlp_type         (pcie_rx_tlp_type),
    .rx_tlp_length       (pcie_rx_tlp_length),
    .rx_tlp_ready        (1'b1),
    .link_up             (),
    .link_gen            (),
    .link_width          (),
    .link_speed          (),
    .correctable_error   (),
    .uncorrectable_error (),
    .error_count         ()
  );

  nvlink_phy u_nvlink_phy (
    .clk                  (io_clk),
    .rst_n                (io_rst_n),
    .rx_p                 (nvlink_rx_p),
    .rx_n                 (nvlink_rx_n),
    .tx_p                 (nvlink_tx_p),
    .tx_n                 (nvlink_tx_n),
    .tx_flit_valid        (nv_tx_flit_valid),
    .tx_flit_data         (nv_tx_flit_data),
    .tx_flit_vc           (nv_tx_flit_vc),
    .tx_flit_ready        (nv_tx_flit_ready),
    .rx_flit_valid        (nv_rx_flit_valid),
    .rx_flit_data         (nv_rx_flit_data),
    .rx_flit_vc           (nv_rx_flit_vc),
    .rx_flit_ready        (1'b1),
    .link_up              (),
    .active_lanes         (),
    .link_bw_gbps         (),
    .tx_credits_available (nv_tx_credits),
    .tx_credit_return     (1'b1),
    .link_error           (nv_link_error),
    .error_syndrome       (nv_error_syndrome),
    .error_count          (nv_error_count),
    .power_state          (2'd0),
    .in_low_power         (nv_low_power)
  );

endmodule : agni_gpu_top

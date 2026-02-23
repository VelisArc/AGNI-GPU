`timescale 1ns/1ps

module atomic_unit
  import agni_pkg::*;
#(
  parameter int unsigned DATA_WIDTH  = 32,
  parameter int unsigned ADDR_WIDTH  = 48,
  parameter int unsigned NUM_LOCKS   = 16,
  parameter int unsigned RETRY_DEPTH = 8
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic                    req_valid,
  input  atomic_op_t              req_op,
  input  logic [ADDR_WIDTH-1:0]   req_addr,
  input  logic [DATA_WIDTH-1:0]   req_src_data,
  input  logic [DATA_WIDTH-1:0]   req_cmp_data,
  input  logic [6:0]              req_warp_id,
  input  logic [4:0]              req_lane_id,
  output logic                    req_ready,

  output logic                    mem_rd_valid,
  output logic [ADDR_WIDTH-1:0]   mem_rd_addr,
  input  logic                    mem_rd_ready,
  input  logic                    mem_rd_resp_valid,
  input  logic [DATA_WIDTH-1:0]   mem_rd_data,

  output logic                    mem_wr_valid,
  output logic [ADDR_WIDTH-1:0]   mem_wr_addr,
  output logic [DATA_WIDTH-1:0]   mem_wr_data,
  input  logic                    mem_wr_ready,

  output logic                    result_valid,
  output logic [DATA_WIDTH-1:0]   result_data,
  output logic [6:0]              result_warp_id,
  output logic [4:0]              result_lane_id,

  output logic [31:0]             perf_atomics_completed,
  output logic [31:0]             perf_conflicts
);

  logic [ADDR_WIDTH-1:0] lock_addr [0:NUM_LOCKS-1];
  logic [NUM_LOCKS-1:0]  lock_valid;

  logic addr_locked;
  logic [$clog2(NUM_LOCKS)-1:0] lock_alloc_id;
  logic lock_full;

  always_comb begin
    addr_locked   = 1'b0;
    lock_full     = &lock_valid;
    lock_alloc_id = '0;

    for (int i = 0; i < NUM_LOCKS; i++) begin
      if (lock_valid[i] && lock_addr[i] == req_addr)
        addr_locked = 1'b1;
      if (!lock_valid[i] && lock_alloc_id == '0)
        lock_alloc_id = i[$clog2(NUM_LOCKS)-1:0];
    end
  end

  logic                    rq_valid    [0:RETRY_DEPTH-1];
  atomic_op_t              rq_op       [0:RETRY_DEPTH-1];
  logic [ADDR_WIDTH-1:0]   rq_addr     [0:RETRY_DEPTH-1];
  logic [DATA_WIDTH-1:0]   rq_src_data [0:RETRY_DEPTH-1];
  logic [DATA_WIDTH-1:0]   rq_cmp_data [0:RETRY_DEPTH-1];
  logic [6:0]              rq_warp_id  [0:RETRY_DEPTH-1];
  logic [4:0]              rq_lane_id  [0:RETRY_DEPTH-1];

  logic [$clog2(RETRY_DEPTH)-1:0] retry_head, retry_tail;
  logic [$clog2(RETRY_DEPTH):0]   retry_count;
  logic retry_full, retry_empty;

  assign retry_full  = (retry_count == RETRY_DEPTH);
  assign retry_empty = (retry_count == 0);

  logic                    s1_valid;
  atomic_op_t              s1_op;
  logic [ADDR_WIDTH-1:0]   s1_addr;
  logic [DATA_WIDTH-1:0]   s1_src_data;
  logic [DATA_WIDTH-1:0]   s1_cmp_data;
  logic [6:0]              s1_warp_id;
  logic [4:0]              s1_lane_id;

  logic                    s2_valid;
  atomic_op_t              s2_op;
  logic [ADDR_WIDTH-1:0]   s2_addr;
  logic [DATA_WIDTH-1:0]   s2_src_data;
  logic [DATA_WIDTH-1:0]   s2_cmp_data;
  logic [DATA_WIDTH-1:0]   s2_old_data;
  logic [6:0]              s2_warp_id;
  logic [4:0]              s2_lane_id;

  logic                    s3_valid;
  logic [ADDR_WIDTH-1:0]   s3_addr;
  logic [DATA_WIDTH-1:0]   s3_old_data;
  logic [6:0]              s3_warp_id;
  logic [4:0]              s3_lane_id;

  typedef enum logic [1:0] {
    S1_IDLE = 2'b00,
    S1_READ = 2'b01,
    S1_WAIT = 2'b10
  } s1_state_t;

  s1_state_t s1_state, s1_state_next;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_state <= S1_IDLE;
      s1_valid <= 1'b0;
    end else begin
      s1_state <= s1_state_next;
      if (s1_state == S1_IDLE && req_valid && !addr_locked && !lock_full) begin
        s1_valid    <= 1'b1;
        s1_op       <= req_op;
        s1_addr     <= req_addr;
        s1_src_data <= req_src_data;
        s1_cmp_data <= req_cmp_data;
        s1_warp_id  <= req_warp_id;
        s1_lane_id  <= req_lane_id;

        lock_valid[lock_alloc_id] <= 1'b1;
        lock_addr[lock_alloc_id]  <= req_addr;
      end
    end
  end

  always_comb begin
    s1_state_next = s1_state;
    case (s1_state)
      S1_IDLE: if (req_valid && !addr_locked && !lock_full) s1_state_next = S1_READ;
      S1_READ: if (mem_rd_ready)                            s1_state_next = S1_WAIT;
      S1_WAIT: if (mem_rd_resp_valid)                       s1_state_next = S1_IDLE;
      default: s1_state_next = S1_IDLE;
    endcase
  end

  assign req_ready     = (s1_state == S1_IDLE) && !addr_locked && !lock_full;
  assign mem_rd_valid  = (s1_state == S1_READ);
  assign mem_rd_addr   = s1_addr;

  logic [DATA_WIDTH-1:0] compute_result;
  logic                  cas_success;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s2_valid <= 1'b0;
    end else if (s1_state == S1_WAIT && mem_rd_resp_valid) begin
      s2_valid    <= 1'b1;
      s2_op       <= s1_op;
      s2_addr     <= s1_addr;
      s2_src_data <= s1_src_data;
      s2_cmp_data <= s1_cmp_data;
      s2_old_data <= mem_rd_data;
      s2_warp_id  <= s1_warp_id;
      s2_lane_id  <= s1_lane_id;
    end else begin
      s2_valid <= 1'b0;
    end
  end

  always_comb begin
    compute_result = s2_old_data;
    cas_success    = 1'b0;

    case (s2_op)
      ATOMIC_ADD:  compute_result = s2_old_data + s2_src_data;
      ATOMIC_SUB:  compute_result = s2_old_data - s2_src_data;
      ATOMIC_MIN: begin
        if ($signed(s2_old_data) < $signed(s2_src_data))
          compute_result = s2_old_data;
        else
          compute_result = s2_src_data;
      end
      ATOMIC_MAX: begin
        if ($signed(s2_old_data) > $signed(s2_src_data))
          compute_result = s2_old_data;
        else
          compute_result = s2_src_data;
      end
      ATOMIC_AND:  compute_result = s2_old_data & s2_src_data;
      ATOMIC_OR:   compute_result = s2_old_data | s2_src_data;
      ATOMIC_XOR:  compute_result = s2_old_data ^ s2_src_data;
      ATOMIC_EXCH: compute_result = s2_src_data;
      ATOMIC_CAS: begin
        cas_success = (s2_old_data == s2_cmp_data);
        if (cas_success)
          compute_result = s2_src_data;
        else
          compute_result = s2_old_data;
      end
      default:     compute_result = s2_old_data;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s3_valid <= 1'b0;
    end else if (s2_valid) begin
      s3_valid    <= 1'b1;
      s3_addr     <= s2_addr;
      s3_old_data <= s2_old_data;
      s3_warp_id  <= s2_warp_id;
      s3_lane_id  <= s2_lane_id;
    end else begin
      s3_valid <= 1'b0;
    end
  end

  assign mem_wr_valid = s3_valid;
  assign mem_wr_addr  = s3_addr;
  assign mem_wr_data  = compute_result;

  always_ff @(posedge clk) begin
    if (s3_valid && mem_wr_ready) begin
      for (int i = 0; i < NUM_LOCKS; i++) begin
        if (lock_valid[i] && lock_addr[i] == s3_addr)
          lock_valid[i] <= 1'b0;
      end
    end
  end

  assign result_valid   = s3_valid && mem_wr_ready;
  assign result_data    = s3_old_data;
  assign result_warp_id = s3_warp_id;
  assign result_lane_id = s3_lane_id;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      retry_head  <= '0;
      retry_tail  <= '0;
      retry_count <= '0;
      for (int i = 0; i < RETRY_DEPTH; i++)
        rq_valid[i] <= 1'b0;
    end else begin

      if (req_valid && addr_locked && !retry_full) begin
        rq_valid[retry_tail]    <= 1'b1;
        rq_op[retry_tail]       <= req_op;
        rq_addr[retry_tail]     <= req_addr;
        rq_src_data[retry_tail] <= req_src_data;
        rq_cmp_data[retry_tail] <= req_cmp_data;
        rq_warp_id[retry_tail]  <= req_warp_id;
        rq_lane_id[retry_tail]  <= req_lane_id;
        retry_tail  <= retry_tail + 1;
        retry_count <= retry_count + 1;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      perf_atomics_completed <= '0;
      perf_conflicts         <= '0;
    end else begin
      if (result_valid) perf_atomics_completed <= perf_atomics_completed + 1;
      if (req_valid && addr_locked) perf_conflicts <= perf_conflicts + 1;
    end
  end

endmodule : atomic_unit

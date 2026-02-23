

`ifndef AGNI_PKG_SV
`define AGNI_PKG_SV

package agni_pkg;
  timeunit 1ns;
  timeprecision 1ps;

  parameter int unsigned NUM_GPCS          = 16;
  parameter int unsigned SM_PER_GPC        = 16;
  parameter int unsigned TOTAL_SMS         = NUM_GPCS * SM_PER_GPC;

  parameter int unsigned WARP_SIZE         = 32;
  parameter int unsigned MAX_WARPS_PER_SM  = 64;
  parameter int unsigned MAX_THREADS_PER_SM = MAX_WARPS_PER_SM * WARP_SIZE;
  parameter int unsigned WARP_SCHEDULERS   = 4;
  parameter int unsigned MAX_BLOCKS_PER_SM = 32;

  parameter int unsigned NUM_FP32_PER_SM   = 128;
  parameter int unsigned NUM_INT32_PER_SM  = 128;
  parameter int unsigned NUM_FP64_PER_SM   = 2;
  parameter int unsigned NUM_TC_PER_SM     = 8;
  parameter int unsigned NUM_SFU_PER_SM    = 16;
  parameter int unsigned NUM_LSU_PER_SM    = 32;

  parameter int unsigned REG_FILE_SIZE_KB  = 256;
  parameter int unsigned REG_WIDTH         = 32;
  parameter int unsigned REGS_PER_SM       = (REG_FILE_SIZE_KB * 1024 * 8) / REG_WIDTH;
  parameter int unsigned REG_BANKS         = 32;
  parameter int unsigned REGS_PER_BANK     = REGS_PER_SM / REG_BANKS;

  parameter int unsigned L1_SIZE_KB        = 128;
  parameter int unsigned SMEM_SIZE_KB      = 128;
  parameter int unsigned L1_WAYS           = 4;
  parameter int unsigned L1_LINE_BYTES     = 128;

  parameter int unsigned L2_TOTAL_MB       = 192;
  parameter int unsigned L2_SLICES         = 24;
  parameter int unsigned L2_SLICE_KB       = (L2_TOTAL_MB * 1024) / L2_SLICES;
  parameter int unsigned L2_WAYS           = 16;
  parameter int unsigned L2_LINE_BYTES     = 128;

  parameter int unsigned HBM_STACKS        = 6;
  parameter int unsigned HBM_CONTROLLERS   = 12;
  parameter int unsigned HBM_BUS_WIDTH     = 512;
  parameter int unsigned HBM_TOTAL_BUS     = HBM_CONTROLLERS * HBM_BUS_WIDTH;
  parameter int unsigned HBM_CAPACITY_GB   = 288;

  parameter int unsigned NOC_FLIT_WIDTH    = 256;
  parameter int unsigned NOC_VC_COUNT      = 4;
  parameter int unsigned NOC_MESH_ROWS     = 4;
  parameter int unsigned NOC_MESH_COLS     = 8;
  parameter int unsigned NOC_PORTS         = 5;

  parameter int unsigned PCIE_LANES        = 16;
  parameter int unsigned PCIE_GEN          = 6;
  parameter int unsigned NVLINK_LANES      = 18;

  parameter int unsigned CORE_CLK_BASE_MHZ  = 1800;
  parameter int unsigned CORE_CLK_BOOST_MHZ = 2600;
  parameter int unsigned MEM_CLK_MHZ        = 2400;
  parameter int unsigned FABRIC_CLK_MHZ     = 2000;

  typedef enum logic [3:0] {
    PREC_FP64   = 4'b0000,
    PREC_TF32   = 4'b0001,
    PREC_FP32   = 4'b0010,
    PREC_FP16   = 4'b0011,
    PREC_BF16   = 4'b0100,
    PREC_FP8_E4 = 4'b0101,
    PREC_FP8_E5 = 4'b0110,
    PREC_INT8   = 4'b0111,
    PREC_INT4   = 4'b1000,
    PREC_INT32  = 4'b1001
  } precision_t;

  typedef enum logic [4:0] {
    ALU_ADD     = 5'b00000,
    ALU_SUB     = 5'b00001,
    ALU_MUL     = 5'b00010,
    ALU_FMA     = 5'b00011,
    ALU_DIV     = 5'b00100,
    ALU_MOD     = 5'b00101,
    ALU_AND     = 5'b00110,
    ALU_OR      = 5'b00111,
    ALU_XOR     = 5'b01000,
    ALU_SHL     = 5'b01001,
    ALU_SHR     = 5'b01010,
    ALU_SHRA    = 5'b01011,
    ALU_CMP_EQ  = 5'b01100,
    ALU_CMP_LT  = 5'b01101,
    ALU_CMP_LE  = 5'b01110,
    ALU_MIN     = 5'b01111,
    ALU_MAX     = 5'b10000,
    ALU_ABS     = 5'b10001,
    ALU_NEG     = 5'b10010,
    ALU_CVT     = 5'b10011,
    ALU_NOP     = 5'b11111
  } alu_op_t;

  typedef enum logic [2:0] {
    SFU_SIN   = 3'b000,
    SFU_COS   = 3'b001,
    SFU_EXP   = 3'b010,
    SFU_LOG   = 3'b011,
    SFU_RSQRT = 3'b100,
    SFU_SQRT  = 3'b101,
    SFU_RCP   = 3'b110
  } sfu_op_t;

  typedef enum logic [1:0] {
    TC_MMA     = 2'b00,
    TC_MMA_SP  = 2'b01,
    TC_LOAD    = 2'b10,
    TC_STORE   = 2'b11
  } tc_op_t;

  typedef enum logic [2:0] {
    MEM_LOAD    = 3'b000,
    MEM_STORE   = 3'b001,
    MEM_ATOM_ADD = 3'b010,
    MEM_ATOM_CAS = 3'b011,
    MEM_PREFETCH = 3'b100,
    MEM_FENCE   = 3'b101
  } mem_op_t;

  typedef struct packed {
    logic [47:0]  addr;
    mem_op_t      op;
    logic [6:0]   warp_id;
    logic [4:0]   lane_id;
    logic [127:0] wdata;
    logic [15:0]  byte_enable;
  } cache_req_t;

  typedef struct packed {
    logic [127:0] rdata;
    logic [6:0]   warp_id;
    logic [4:0]   lane_id;
    logic         hit;
    logic         error;
  } cache_resp_t;

  typedef enum logic [1:0] {
    FLIT_HEAD    = 2'b00,
    FLIT_BODY    = 2'b01,
    FLIT_TAIL    = 2'b10,
    FLIT_SINGLE  = 2'b11
  } flit_type_t;

  typedef struct packed {
    flit_type_t           flit_type;
    logic [3:0]           src_id;
    logic [3:0]           dst_id;
    logic [1:0]           vc_id;
    logic [1:0]           qos;
    logic [NOC_FLIT_WIDTH-15:0] payload;
  } noc_flit_t;

  typedef enum logic [2:0] {
    PSTATE_BOOST = 3'b000,
    PSTATE_BASE  = 3'b001,
    PSTATE_P1    = 3'b010,
    PSTATE_P2    = 3'b011,
    PSTATE_IDLE  = 3'b100,
    PSTATE_OFF   = 3'b101
  } pstate_t;

  typedef enum logic [2:0] {
    THERM_SAFE     = 3'b000,
    THERM_NORMAL   = 3'b001,
    THERM_THROTTLE = 3'b010,
    THERM_EMERGENCY = 3'b011,
    THERM_SHUTDOWN = 3'b100
  } thermal_zone_t;

  typedef enum logic [1:0] {
    ECC_NONE     = 2'b00,
    ECC_CORRECTED = 2'b01,
    ECC_DETECTED  = 2'b10,
    ECC_POISON    = 2'b11
  } ecc_error_t;

  typedef struct packed {
    alu_op_t      opcode;
    logic [4:0]   dst_reg;
    logic [4:0]   src0_reg;
    logic [4:0]   src1_reg;
    logic [4:0]   src2_reg;
    precision_t   precision;
    logic         predicated;
    logic [6:0]   warp_id;
    logic [31:0]  immediate;
  } warp_instr_t;

  typedef enum logic [3:0] {
    ATOMIC_ADD  = 4'b0000,
    ATOMIC_SUB  = 4'b0001,
    ATOMIC_MIN  = 4'b0010,
    ATOMIC_MAX  = 4'b0011,
    ATOMIC_AND  = 4'b0100,
    ATOMIC_OR   = 4'b0101,
    ATOMIC_XOR  = 4'b0110,
    ATOMIC_EXCH = 4'b0111,
    ATOMIC_CAS  = 4'b1000
  } atomic_op_t;

  typedef enum logic [2:0] {
    COH_GETS    = 3'b000,
    COH_GETM    = 3'b001,
    COH_PUTM    = 3'b010,
    COH_INV     = 3'b011,
    COH_ACK     = 3'b100,
    COH_DATA_E  = 3'b101,
    COH_DATA_S  = 3'b110,
    COH_DATA_M  = 3'b111
  } coherence_msg_t;

  function automatic int unsigned clog2(input int unsigned value);
    int unsigned result;
    result = 0;
    value = value - 1;
    while (value > 0) begin
      result = result + 1;
      value = value >> 1;
    end
    return result;
  endfunction

  function automatic int unsigned max2(input int unsigned a, input int unsigned b);
    return (a > b) ? a : b;
  endfunction

  function automatic int unsigned min2(input int unsigned a, input int unsigned b);
    return (a < b) ? a : b;
  endfunction

endpackage : agni_pkg

`endif

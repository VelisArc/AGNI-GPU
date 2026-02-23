# 01 — Compute Architecture Specification

> **Project AGNI** | Document: Compute Architecture | Rev: 1.0

---

## 1. Architecture Overview

- **Architecture Class:** Data-center AI accelerator (Transformer-optimized)
- **ISA:** CUDA Compute Capability 10.0
- **Process Node:** TSMC N3E (3nm Enhanced)
- **Transistor Count:** ~200 Billion
- **Die Size:** ~900 mm² (reticle limit)

---

## 2. Streaming Multiprocessor (SM) Design

### 2.1 SM Configuration

| Parameter | Value |
|---|---|
| Total SMs | 256 |
| SM Clusters (GPCs) | 16 GPCs × 16 SMs each |
| Warp Schedulers / SM | 4 |
| Max Warps / SM | 64 |
| Max Threads / SM | 2,048 |
| Max Thread Blocks / SM | 32 |

### 2.2 Execution Units per SM

| Unit | Count per SM | Total |
|---|---|---|
| FP32 CUDA Cores | 128 | 32,768 |
| FP64 Cores | 2 (shared path) | 512 |
| INT32 Cores | 128 (concurrent with FP) | 32,768 |
| Tensor Cores (5th Gen) | 8 | 2,048 |
| SFU (Special Function) | 16 | 4,096 |
| Load/Store Units | 32 | 8,192 |

### 2.3 SM Register File

| Parameter | Value |
|---|---|
| Register File / SM | 256 KB (65,536 × 32-bit) |
| Total Register File | 64 MB |
| ECC Protection | SEC-DED on all registers |

---

## 3. 5th-Generation Tensor Cores

### 3.1 Supported Data Types

| Data Type | Matrix Shape | Throughput / TC / Cycle |
|---|---|---|
| FP64 | 8×8×4 | 128 FMA ops |
| TF32 | 16×8×8 | 512 FMA ops |
| BF16 | 16×16×16 | 1,024 FMA ops |
| FP16 | 16×16×16 | 1,024 FMA ops |
| FP8 (E4M3) | 16×16×32 | 2,048 FMA ops |
| FP8 (E5M2) | 16×16×32 | 2,048 FMA ops |
| INT8 | 16×16×32 | 2,048 ops |
| INT4 | 16×16×64 | 4,096 ops |

### 3.2 Sparsity Engine

- **Structured Sparsity:** 2:4 pattern (50% zero, 2× throughput)
- **Sparsity Metadata:** Compressed format, stored in shared memory
- **Applicable Types:** FP16, BF16, FP8, INT8, INT4
- **Effective FP8 w/ Sparsity:** 14,400 TOPS

### 3.3 Transformer Engine (TE)

- **FP8 Dynamic Scaling:** Per-tensor amax tracking for loss-free FP8 training
- **Layer-wise Precision:** Attention in FP16, FFN in FP8 automatically
- **Statistics Tracking:** Hardware histograms for calibration-free quantization

---

## 4. Aggregate Compute Throughput

| Precision | Peak TFLOPS/TOPS | With 2:4 Sparsity |
|---|---|---|
| FP64 | 120 | N/A |
| TF32 | 1,800 | 3,600 |
| BF16 | 3,600 | 7,200 |
| FP16 | 3,600 | 7,200 |
| FP8 | 7,200 | 14,400 |
| INT8 | 7,200 TOPS | 14,400 TOPS |
| INT4 | 14,400 TOPS | 28,800 TOPS |

---

## 5. Clock Domain

| Parameter | Value | Rationale |
|---|---|---|
| Base Clock | 1,800 MHz | Conservative for reliability |
| Boost Clock | 2,600 MHz | Thermal headroom allows |
| Memory Clock | 2,400 MHz (HBM4 effective) | Matched to HBM4 spec |
| Fabric Clock | 2,000 MHz | NoC/L2 interconnect |

### 5.1 Clock Guardband Strategy

```
Reliability Clock Budget:
  Nominal Vdd = 0.75V
  Guardband   = +5% (aging: NBTI + HCI + EM)
  Operating   = 0.788V max
  
  Year 0:  Boost capable at 2,600 MHz / 0.75V
  Year 5:  Boost at 2,600 MHz / 0.76V (adaptive)  
  Year 10: Boost at 2,500 MHz / 0.78V (graceful aging)
```

- **Adaptive Voltage Scaling (AVS):** Per-chip fused calibration
- **DVFS States:** 16 P-states, 100 MHz granularity
- **Workload Classifier:** ML-based frequency predictor (latency vs. throughput)

---

## 6. GPC (Graphics Processing Cluster) Layout

```
GPU Die Layout (256 SMs across 16 GPCs):

┌──────────────────────────────────────────────────┐
│  GPC 0    GPC 1    GPC 2    GPC 3                │
│  [16 SM]  [16 SM]  [16 SM]  [16 SM]              │
│                                                   │
│  GPC 4    GPC 5    GPC 6    GPC 7                │
│  [16 SM]  [16 SM]  [16 SM]  [16 SM]              │
│                                                   │
│              ┌──────────────┐                     │
│              │  L2 Cache    │                     │
│              │  192 MB      │                     │
│              │  (24 slices) │                     │
│              └──────────────┘                     │
│                                                   │
│  GPC 8    GPC 9    GPC 10   GPC 11               │
│  [16 SM]  [16 SM]  [16 SM]  [16 SM]              │
│                                                   │
│  GPC 12   GPC 13   GPC 14   GPC 15               │
│  [16 SM]  [16 SM]  [16 SM]  [16 SM]              │
└──────────────────────────────────────────────────┘
         ↕ HBM4 stacks around perimeter ↕
```

---

## 7. Thread Execution Model

| Feature | Specification |
|---|---|
| Max Grid Dimensions | 2³¹ × 65,535 × 65,535 |
| Max Block Dimensions | 1,024 × 1,024 × 64 |
| Max Threads / Block | 1,024 |
| Warp Size | 32 threads |
| Async Copy Engine | DMA units for global→shared |
| Thread Block Clusters | Up to 16 blocks, cooperative |
| Distributed Shared Memory | Cross-block SMEM access within cluster |

---

## 8. Special Function Units

- **Transcendental Functions:** sin, cos, exp, log, rsqrt
- **Throughput:** 16 SFU per SM = 4,096 total
- **Use Case:** Softmax, GELU activation, RoPE positional embedding
- **Accuracy:** IEEE 754 compliant (ULP ≤ 2)

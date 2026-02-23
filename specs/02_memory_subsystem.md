# 02 — Memory Subsystem Specification

> **Project AGNI** | Document: Memory Subsystem | Rev: 1.0

---

## 1. Memory Architecture Overview

```
Memory Hierarchy:

  Registers (256 KB/SM)      ← Fastest, per-thread
       ↕
  L1 Cache / Shared Memory   ← 256 KB/SM, configurable
       ↕
  L2 Cache (192 MB)          ← Unified, all SMs share
       ↕
  HBM4 (288 GB @ 8 TB/s)    ← Main memory, model weights
       ↕
  Host Memory (PCIe 6.0)     ← System RAM, data pipeline
```

---

## 2. HBM4 — High Bandwidth Memory

### 2.1 Configuration

| Parameter | Value |
|---|---|
| HBM Generation | HBM4 |
| Total Capacity | 288 GB |
| Stack Configuration | 6 stacks × 12-Hi |
| Capacity per Stack | 48 GB (4 GB per die × 12 dies) |
| Bus Width per Stack | 1,024 bits |
| Total Bus Width | 6,144 bits |
| Data Rate | 6.4 Gbps per pin |
| Bandwidth per Stack | ~820 GB/s |
| **Total Bandwidth** | **~8 TB/s** (theoretical peak) |
| Effective Bandwidth | ~6.8 TB/s (85% efficiency typical) |

### 2.2 HBM4 Physical Integration

| Parameter | Value |
|---|---|
| Attachment | CoWoS-L silicon interposer |
| Micro-bump Pitch | 36 μm |
| TSV (Through-Silicon Via) | 5 μm diameter, 50 μm pitch |
| PHY IP | JEDEC HBM4 compliant |
| Channels per Stack | 32 pseudo-channels |
| Total Channels | 192 pseudo-channels |

### 2.3 HBM4 ECC & Reliability

| Feature | Implementation |
|---|---|
| ECC Level | **Chipkill** (corrects full single-die failure) |
| Error Code | Reed-Solomon + SECDED hybrid |
| Error Granularity | 256-bit correction domain |
| Patrol Scrub | Every 24 hours, low-priority background |
| Demand Scrub | On every read (in-line ECC check) |
| Poison Bit | Marks uncorrectable locations |
| Page Retirement | Driver remaps bad pages, OS notified |
| Error Counters | Per-stack correctable/uncorrectable counters |
| Error Injection | Test mode for ECC validation |

### 2.4 HBM4 Power Management

| Feature | Details |
|---|---|
| Active Power | ~45W per stack, ~270W total |
| Self-Refresh Power | ~2W per stack |
| Temperature-aware Refresh | Shorter intervals above 75°C |
| Power-down Mode | Per-stack individual power-down |
| Bandwidth Throttling | Dynamic rate limiting under thermal pressure |

---

## 3. L2 Cache

### 3.1 Configuration

| Parameter | Value |
|---|---|
| Total Size | 192 MB |
| Slices | 24 slices × 8 MB each |
| Associativity | 16-way set-associative |
| Line Size | 128 bytes |
| Replacement Policy | Adaptive (LRU + frequency) |
| Write Policy | Write-back, write-allocate |
| Internal Bandwidth | ~25 TB/s aggregate (all slices) |
| ECC | SEC-DED |

### 3.2 L2 Partitioning (Hardware)

- **Persistence Mode:** Pin model layers in L2 for repeated inference
- **Set-Aside:** Reserve up to 75% of L2 for specific kernels (via CUDA API)
- **Streaming Mode:** Bypass L2 for large sequential reads (weight loading)
- **Residency Control:** Per-kernel L2 access policy (normal, streaming, persisting)

### 3.3 L2 → HBM Interface

| Parameter | Value |
|---|---|
| Memory Controllers | 12 controllers |
| Bits per Controller | 512-bit |
| Request Queue Depth | 256 entries per controller |
| Page Policy | Adaptive (open for sequential, close for random) |
| Address Interleaving | Fine-grained (256B interleave) |
| Row Buffer Size | 2 KB per bank |

---

## 4. L1 Cache / Shared Memory

### 4.1 Per-SM Configuration

| Parameter | Value |
|---|---|
| Total L1/SMEM | 256 KB per SM |
| Configurable Split | 64/192, 128/128, 192/64, 256/0 (KB SMEM/L1) |
| Default Split | 128 KB SMEM + 128 KB L1 |
| L1 Associativity | 4-way set-associative |
| L1 Line Size | 128 bytes |
| L1 Bandwidth | 128 bytes/cycle per SM |
| SMEM Banks | 32 banks |
| SMEM Bank Width | 4 bytes |
| SMEM Bandwidth | 128 bytes/cycle per SM |
| ECC | SEC-DED |

### 4.2 Shared Memory Features

- **Async Copy:** DMA engine for global→shared, overlaps with compute
- **Distributed Shared Memory:** Access neighboring SM's SMEM within cluster
- **Barrier Synchronization:** 16 named barriers per block
- **Swizzle Patterns:** Hardware bank-conflict avoidance

---

## 5. Texture / Read-Only Cache

| Parameter | Value |
|---|---|
| Size per SM | 128 KB (unified with L1 in read-only path) |
| Filtering | Hardware bilinear/trilinear (unused for AI, kept for compatibility) |
| Use Case | Read-only weight access, constant data |

---

## 6. Constant Cache

| Parameter | Value |
|---|---|
| Size per SM | 64 KB |
| Broadcast | Single-cycle broadcast to entire warp |
| Capacity | 64 KB per SM (maps to host constant memory) |

---

## 7. Memory Bandwidth Analysis for 100B Models

### 7.1 Inference (Autoregressive Decoding)

```
Token generation is MEMORY-BANDWIDTH BOUND:

Each token requires reading ALL model weights once.
  → 100B params × 1 byte (FP8) = 100 GB per token (batch=1)
  → At 6.8 TB/s effective bandwidth:
  → 100 GB / 6.8 TB/s = 14.7 ms per token
  → ~68 tokens/sec (single stream)

With batch=32:
  → Amortized weight reads across batch
  → ~68 × 32 = ~2,176 tokens/sec aggregate
  → Compute becomes co-bottleneck at this batch size

With batch=64 (INT4):
  → 50 GB weight reads, more compute per byte
  → ~6,000+ tokens/sec aggregate
```

### 7.2 Training (Forward + Backward Pass)

```
Training is COMPUTE-BOUND (at large batch sizes):

Arithmetic Intensity for Transformer:
  → GEMM: ~2N FLOPs per byte (N = matrix dim)
  → For 100B model with hidden=12288:
  → AI ≈ 24,576 FLOPs/byte → heavily compute-bound
  → Utilization target: >60% of peak FP8 TFLOPS
```

---

## 8. Unified Memory Architecture

| Feature | Support |
|---|---|
| Unified Virtual Address | 49-bit virtual, 52-bit physical |
| Page Size | 64 KB (large pages), 2 MB (huge pages) |
| GPU Page Tables | Hardware MMU with 4-level page walk |
| Demand Paging | Page fault + migration from host |
| Access Counters | Hardware migration hints |
| CUDA Managed Memory | Automatic host↔device migration |
| ATS (Address Translation Services) | PCIe ATS for shared virtual memory with CPU |

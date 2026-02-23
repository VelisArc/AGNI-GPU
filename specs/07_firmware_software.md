# 07 — Firmware & Software Stack

> **Project AGNI** | Document: Firmware & Software | Rev: 1.0

---

## 1. Firmware Architecture

### 1.1 GPU Microcontroller (GSP — GPU System Processor)

| Parameter | Value |
|---|---|
| Processor | ARM Cortex-R82 (real-time, ECC-protected) |
| Clock | 1 GHz |
| SRAM | 2 MB (ECC protected) |
| Flash | 64 MB NOR (dual-bank for A/B firmware) |
| Role | Power management, thermal control, ECC, diagnostics |

### 1.2 Firmware Modules

```
GSP Firmware Stack:

  ┌─────────────────────────────────────┐
  │        OTA Update Manager           │ ← Secure firmware update
  ├─────────────────────────────────────┤
  │  PMU  │ Thermal │  ECC   │  BIST   │ ← Core services
  │Manager│ Control │Manager │ Engine  │
  ├───────┴─────────┴────────┴─────────┤
  │         Hardware Abstraction        │ ← Register access, I2C, SPI
  ├─────────────────────────────────────┤
  │         Secure Boot ROM             │ ← RSA-4096 root of trust
  └─────────────────────────────────────┘
```

### 1.3 Firmware Module Details

| Module | Responsibility |
|---|---|
| **PMU Manager** | DVFS control, P-state transitions, AVS calibration |
| **Thermal Controller** | PID fan/pump control, throttle decisions, predictive thermal |
| **ECC Manager** | Patrol scrub scheduling, error counters, page retirement |
| **BIST Engine** | Power-on self-test, periodic memory/logic tests |
| **OTA Manager** | Authenticated firmware updates, A/B rollback |
| **Telemetry** | Sensor aggregation, health score computation |
| **Watchdog** | 10s hardware WDT, heartbeat to BMC |
| **NVLink Manager** | Lane training, error recovery, bandwidth negotiation |

---

## 2. Secure Boot Chain

```
Boot Sequence:

  1. Power-On Reset
       ↓
  2. Secure Boot ROM (immutable, in-silicon)
     └── Verify GSP firmware signature (RSA-4096)
       ↓
  3. GSP Firmware loads (Bank A or Bank B)
     └── Initialize PMU, set safe voltage
     └── Run BIST (memory test, basic logic test)
       ↓
  4. PCIe Enumeration
     └── Host detects GPU via BAR mapping
       ↓
  5. Driver Load (Host OS)
     └── Verify driver ↔ firmware version compatibility
     └── Upload microcode (shader compiler, scheduler)
       ↓
  6. CUDA Runtime Initialization
     └── GPU ready for compute workloads

  Total boot time target: < 5 seconds
```

---

## 3. Software Driver Stack

### 3.1 Kernel-Mode Driver

| Feature | Details |
|---|---|
| OS Support | Linux (primary), Windows (secondary) |
| GPU Scheduler | Hardware-assisted preemptive scheduling |
| Memory Manager | Unified memory, demand paging, migration |
| Power Manager | OS-integrated DVFS via ACPI |
| Error Handler | MCA error bank reading, page retirement |
| MIG Support | Hardware-partitioned GPU instances |
| SR-IOV | PCIe virtual function for VM passthrough |

### 3.2 User-Space Runtime

| Component | Purpose |
|---|---|
| **CUDA Runtime** | Core compute API (v14+) |
| **CUDA Driver API** | Low-level GPU control |
| **cuBLAS** | Dense linear algebra (GEMM) |
| **cuDNN** | Neural network primitives |
| **cuSPARSE** | Sparse matrix operations |
| **NCCL** | Multi-GPU collective communication |
| **TensorRT** | Inference optimization + quantization |
| **cuRAND** | Random number generation |

---

## 4. AI Software Stack Compatibility

### 4.1 Inference Frameworks

| Framework | Support Level | Key Features |
|---|---|---|
| **TensorRT** | Native, optimized | FP8/INT4 quantization, layer fusion |
| **vLLM** | First-class | PagedAttention, continuous batching |
| **TGI (Text Gen Inference)** | Supported | HuggingFace model hub integration |
| **Triton Inference Server** | Supported | Multi-model serving, dynamic batching |
| **ONNX Runtime** | Supported | Cross-framework model format |
| **llama.cpp** | Supported | GGUF quantized models |

### 4.2 Training Frameworks

| Framework | Support Level | Key Features |
|---|---|---|
| **PyTorch** | Native CUDA backend | AMP, FSDP, torch.compile |
| **JAX** | XLA→CUDA compilation | pjit, TPU-like programming |
| **DeepSpeed** | ZeRO-3, ZeRO-Infinity | Model parallelism for >100B |
| **Megatron-LM** | Tensor + Pipeline parallel | State-of-the-art LLM training |
| **Hugging Face Transformers** | Trainer API | LoRA, QLoRA, PEFT |

### 4.3 Quantization Support

| Method | Precision | Software |
|---|---|---|
| PTQ (Post-Training Quantization) | FP8, INT8 | TensorRT, GPTQ |
| QAT (Quantization-Aware Training) | FP8, INT8 | PyTorch, TF |
| GPTQ | INT4, INT8 | auto-gptq |
| AWQ | INT4 | autoawq |
| GGUF | INT2–INT8 | llama.cpp |
| SmoothQuant | INT8 | TensorRT |

---

## 5. Developer Tools

| Tool | Purpose |
|---|---|
| **Nsight Compute** | Kernel profiling, roofline analysis |
| **Nsight Systems** | System-wide performance tracing |
| **CUDA-GDB** | GPU debugging |
| **CUDA-MEMCHECK** | Memory error detection |
| **DCGM** | Datacenter GPU monitoring |
| **nvidia-smi** | CLI monitoring + management |
| **GPU Operator** | Kubernetes GPU orchestration |

---

## 6. Firmware Update (OTA)

| Feature | Implementation |
|---|---|
| Dual Flash Banks | A/B partitioning — rollback on failure |
| Authentication | RSA-4096 + SHA-512 signature verification |
| Atomicity | Write to inactive bank → verify → swap |
| Rollback | Automatic if new firmware fails POST |
| Downtime | < 10 seconds (GPU reset, not host reboot) |
| Channels | In-band (driver) + Out-of-band (BMC/IPMI) |
| Versioning | Semantic versioning (major.minor.patch) |

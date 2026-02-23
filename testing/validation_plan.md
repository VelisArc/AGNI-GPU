# Testing & Validation Plan

> **Project AGNI** | Document: Testing & Validation | Rev: 1.0

---

## 1. Testing Phases Overview

```
Testing Pipeline:

  Phase 1: Silicon Validation (Pre-Production)
     └── Wafer-level tests → Known Good Die (KGD)
     └── Package-level burn-in → Known Good Package
  
  Phase 2: Board-Level Testing (Production)
     └── ICT → Functional Test → Thermal Imaging
  
  Phase 3: System-Level Validation (Qualification)
     └── Performance benchmarks → Stress tests → ECC validation
  
  Phase 4: Long-Term Reliability (Ongoing)
     └── Accelerated life tests → Field reliability monitoring
```

---

## 2. Phase 1: Silicon Validation

### 2.1 Wafer-Level Tests

| Test | Method | Pass Criteria |
|---|---|---|
| Parametric Test | Probe card on wafer | Vt, Idsat, Ioff within spec |
| IDDQ (Quiescent Current) | Measure leakage per die | < threshold for defect-free |
| Scan Chain (DFT) | Shift patterns through scan chains | 100% stuck-at fault coverage |
| Memory BIST | Built-in self-test for all SRAM | 0 defective bits (with repair) |
| SRAM Repair | Fuse-based redundancy for failed rows/columns | < 0.1% failure after repair |
| Speed Binning | Measure max frequency | Bin into speed grades |

### 2.2 Package-Level Tests

| Test | Duration | Conditions | Pass Criteria |
|---|---|---|---|
| **Burn-in** | 168 hours | 110% TDP, Tj = 105°C | 0 failures per 100 units |
| **HTOL** (High Temp Operating Life) | 1,000 hours | 125°C junction, 1.1× Vdd | < 0.1% failure rate |
| **Temperature Cycling** | 1,000 cycles | -40°C ↔ +125°C, 30 min/cycle | No solder joint opens |
| **Thermal Shock** | 200 cycles | -65°C ↔ +150°C, 1 min transfer | No package cracks |
| **Unbiased HAST** | 96 hours | 130°C, 85% RH | No corrosion failures |
| **ESD (HBM model)** | Per JEDEC JS-001 | ±2,000V all pins | No damage |
| **ESD (CDM model)** | Per JEDEC JS-002 | ±500V | No damage |
| **Latch-up** | Per JEDEC JESD78 | 1.5× Vdd, ±100 mA trigger | No latch-up |

### 2.3 HBM4 Qualification

| Test | Duration | Pass Criteria |
|---|---|---|
| HBM Burn-in | 168 hours at 95°C | 0 failures |
| HBM HTOL | 1,000 hours at 95°C | < 0.1% failure |
| Data Retention | 168 hours at 85°C | All bits retained |
| Refresh Margin | Test at 2× refresh interval | No data loss |
| Error Rate | 10⁹ read/write cycles | < 1 FIT correctable error rate |

---

## 3. Phase 2: Board-Level Testing

### 3.1 In-Circuit Test (ICT)

| Test | Method | Coverage |
|---|---|---|
| Component Presence | Capacitance measurement | All BGA/SMD components |
| Solder Quality | In-circuit resistance | All solder joints |
| Short/Open Detection | Boundary scan + flying probe | All nets |
| Component Value | LCR measurement | All passives (R, C, L) |
| Power Rail Continuity | DC resistance measurement | All power planes |

### 3.2 Functional Test

| Test | Method | Pass Criteria |
|---|---|---|
| GPU POST | Power-on self-test | All subsystems initialize |
| Memory Test | HBM4 full write/read pattern | 0 uncorrectable errors |
| PCIe Link Training | LTSSM → L0 active state | Gen 6 x16 negotiated |
| NVLink Training | Lane training sequence | All 18 lanes up |
| Thermal Sensor Calibration | Compare to reference thermometer | ±1°C accuracy |
| VRM Regulation | Load step test (0→100% load) | Vdd within ±0.5% |
| Fan/Pump Control | PWM sweep 0→100% | Monotonic response |

### 3.3 Thermal Imaging

| Test | Equipment | Pass Criteria |
|---|---|---|
| Full Load IR Scan | FLIR A700 thermal camera | No hotspots > Tj_target + 5°C |
| VRM Thermal | IR scan under sustained load | MOSFETs < 100°C |
| HBM Thermal | Per-stack temperature check | All stacks < 70°C |
| Cold Plate Contact | Compare pre/post TIM application | Uniform spreading |

---

## 4. Phase 3: System-Level Validation

### 4.1 Performance Benchmarks

| Benchmark | Configuration | Target |
|---|---|---|
| **MLPerf Inference** | ResNet-50, BERT, GPT-J, Llama-2 | Top-tier results |
| **MLPerf Training** | BERT, GPT-3 (scaled) | Competitive with H100/B200 |
| **GEMM Throughput** | cuBLAS SGEMM/HGEMM/FP8 GEMM | > 85% of peak TFLOPS |
| **HBM Bandwidth** | CUDA bandwidthTest (HtoD, DtoH, DtoD) | > 85% of peak 8 TB/s |
| **PCIe Bandwidth** | CUDA bandwidthTest | > 90% of 128 GB/s |
| **NVLink Bandwidth** | NCCL all_reduce (2-GPU) | > 90% of 1.8 TB/s |
| **Latency (TTFT)** | Llama-3 100B, batch=1, FP8 | < 50 ms |
| **Throughput (TPS)** | Llama-3 100B, batch=32, FP8 | > 2,000 tok/s |

### 4.2 100B Model Validation

| Test | Model | Config | Pass Criteria |
|---|---|---|---|
| **Load Test** | Llama-3-100B-FP16 | Full model in HBM | Loads successfully |
| **Inference Accuracy** | Llama-3-100B-FP8 | MMLU benchmark | < 0.5% accuracy drop vs FP16 |
| **Long Context** | Llama-3-100B-FP8 | 128K context window | Correct generation |
| **Batch Throughput** | Llama-3-100B-INT4 | batch=64 | > 4,000 tok/s |
| **LoRA Training** | Llama-3-100B-FP8 | rank=64, 1000 steps | Loss converges |
| **KV-Cache Stress** | 100B model | Max batch × max context | No OOM |

### 4.3 Stress Testing

| Test | Duration | Conditions | Pass Criteria |
|---|---|---|---|
| **FurMark AI** | 72 hours continuous | 100% GPU + 100% HBM | No throttle below base clock |
| **Memtest** | 24 hours | Full pattern write/read 288 GB | 0 errors |
| **Thermal Soak** | 48 hours at 95% load | Datacenter ambient (35°C) | Stable Tj < 78°C |
| **Power Cycling** | 10,000 on/off cycles | 30s on, 30s off | No POST failures |
| **Brown-out** | 1,000 random power cuts | During active inference | GPU recovers, no corruption |
| **NVLink Stress** | 48 hours | Bi-directional full bandwidth | 0 CRC errors |

### 4.4 ECC Validation

| Test | Method | Pass Criteria |
|---|---|---|
| Single-bit Injection | Software error injection → HBM | 100% corrected, logged |
| Multi-bit Injection | Inject 2-bit error → verify detection | UE detected, page poisoned |
| Chipkill Injection | Simulate full HBM die failure | All data corrected |
| Patrol Scrub Test | Inject latent error → wait for scrub | Corrected within 24h |
| Error Counter Test | Inject 1000 CEs → check counters | Counters accurate |
| Page Retirement | Inject UE → verify page retired | Page marked, workload continues |

---

## 5. Phase 4: Long-Term Reliability

### 5.1 Accelerated Life Testing

| Test | Duration | Acceleration | Simulated Life |
|---|---|---|---|
| HTOL Extended | 5,000 hours at 125°C | ~1000× (Arrhenius) | >10 years at 75°C |
| Voltage Stress | 2,000 hours at 1.1× Vdd | ~100× | >5 years at nominal |
| Electromigration | 2,000 hours at 125°C, 1.2× Jmax | Per JEDEC JEP154 | EM lifetime confirmed |
| Thermal Cycling Extended | 5,000 cycles (-40/+125°C) | 5× typical | Solder fatigue life |

### 5.2 Field Reliability Monitoring

| Metric | Collection | Alert Threshold |
|---|---|---|
| Correctable Error Rate | Per-GPU per-day | > 100 CE/day |
| Uncorrectable Errors | Per-GPU | Any UE → page retire |
| Retired Pages | Running total | > 100 pages → replace GPU |
| VRM Phase Failures | Phase current monitoring | Any phase current = 0 |
| Temperature Excursions | Tj max per hour | > 83°C sustained |
| NVLink CRC Errors | Per-lane counters | > 10/hour → lane disable |
| PCIe Retry Count | Link-level counter | > 1000/hour → investigate |
| Fan/Pump RPM | Tachometer | < minimum → alert |
| Power Consumption | Per-GPU wattmeter | Sudden change > ±20% |

### 5.3 Firmware Update Testing

| Test | Count | Pass Criteria |
|---|---|---|
| OTA Update Cycle | 1,000 updates | No bricking, all boot successfully |
| Rollback Test | 100 forced rollbacks | Previous firmware restores correctly |
| Power Cut During Update | 50 random power cuts mid-flash | Recovers to active bank |
| Version Mismatch | Test old firmware + new driver | Graceful error, not crash |

---

## 6. Compliance & Certification

| Standard | Scope | Required |
|---|---|---|
| JEDEC JESD47 | Stress test qualification | Mandatory |
| JEDEC JESD22 | Environmental test methods | Mandatory |
| IEC 61000-4-2 | ESD immunity | Mandatory |
| IEC 60068-2-6 | Vibration testing | For datacenter transport |
| IEC 60068-2-27 | Shock testing | For datacenter transport |
| UL 62368-1 | Safety (via system integrator) | Required for end product |
| RoHS | Hazardous substances | Mandatory (lead-free) |
| REACH | Chemical registration | Mandatory (EU) |
| FCC Part 15B | EMI emissions (system level) | Via system integrator |
| CE Mark | European conformity | Via system integrator |

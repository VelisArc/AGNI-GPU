# 05 — Reliability & Longevity Engineering

> **Project AGNI** | Document: Reliability & Longevity | Rev: 1.0

---

## 1. Design Lifetime Target

| Parameter | Target |
|---|---|
| **Operational Lifetime** | **10+ years** (87,600 hours) |
| **Operating Condition** | 24/7, continuous AI inference |
| **MTBF (Component Level)** | > 2,000,000 hours |
| **MTBF (System Level)** | > 200,000 hours |
| **Annualized Failure Rate** | < 0.5% |
| **Silent Data Corruption** | < 1 FIT per billion device-hours |

---

## 2. Silicon-Level Reliability

### 2.1 Failure Mechanism Mitigation

| Mechanism | Description | Mitigation | Guardband |
|---|---|---|---|
| **Electromigration (EM)** | Metal wire thinning due to current flow | Cu/Co dual-metal interconnect, conservative current density | < 70% of max current density |
| **NBTI** | PMOS threshold voltage shift over time | Periodic recovery cycles (voltage reduction), AVS compensation | +40 mV Vt margin |
| **HCI** | Hot carrier injection damages channel | Lower Vdd operating point | +5% voltage margin |
| **TDDB** | Gate oxide time-dependent breakdown | High-K dielectric (HfO₂), process margin | 15-year MTTF at 75°C |
| **BTI Recovery** | Bias temperature instability recovery | Scheduled idle periods allow recovery | Built into thermal controller |

### 2.2 Aging-Aware Adaptive Voltage

```
Year-by-Year Voltage Compensation:

  Year 0:   Vdd = 0.750V, Boost = 2,600 MHz  ← Fresh silicon
  Year 1:   Vdd = 0.752V, Boost = 2,600 MHz  ← Minimal aging
  Year 3:   Vdd = 0.758V, Boost = 2,580 MHz  ← Aging sensors detect Vt shift
  Year 5:   Vdd = 0.765V, Boost = 2,560 MHz  ← AVS compensates
  Year 7:   Vdd = 0.772V, Boost = 2,540 MHz  ← Predictable degradation
  Year 10:  Vdd = 0.780V, Boost = 2,500 MHz  ← Still within spec!

  → Maximum degradation: 100 MHz boost reduction over 10 years
  → Performance impact: < 4%
```

### 2.3 Reliability IP Blocks

| Block | Function |
|---|---|
| Aging Monitor | Ring oscillator + NBTI/HCI sensors at 32 die locations |
| Voltage Droop Detector | < 5 ns detection, triggers frequency throttling |
| Temperature Sensor | 64 distributed diode sensors |
| Glitch Detector | Supply noise monitoring for DPA/fault attack protection |
| Built-In Self-Test (BIST) | Memory BIST, Logic BIST for production + field test |

---

## 3. Memory Reliability

### 3.1 ECC Hierarchy

| Memory Type | ECC Level | Correction Capability | Error Response |
|---|---|---|---|
| Register File | SEC-DED | Single-bit correct, double detect | Warp replay |
| L1 Cache | SEC-DED + Parity | Single-bit correct | Line invalidate + refetch |
| L2 Cache | SEC-DED | Single-bit correct | Line invalidate + refetch |
| Shared Memory | SEC-DED | Single-bit correct | Warp replay |
| HBM4 | **Chipkill** | Full single-die failure correction | Transparent to software |

### 3.2 Chipkill ECC Details

```
Chipkill Architecture:

  Standard SECDED:  Corrects 1 bit, detects 2 bits per codeword
  Chipkill:         Corrects ALL bits from a single DRAM die failure

  Implementation:
  ├── Reed-Solomon outer code (symbol-level correction)
  ├── SECDED inner code (bit-level correction)
  ├── 256-bit granularity correction domains
  └── 32-bit symbol size → survives entire die failure

  Why this matters:
  ├── HBM4 12-Hi stack = 12 DRAM dies
  ├── If 1 die fails → Chipkill corrects ALL its bits
  ├── GPU continues operating normally
  └── Event logged, admin alerted for preventive replacement
```

### 3.3 Error Handling Workflow

```
Error Detection → Classification → Response:

  ┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
  │ Correctable  │ ──→ │ Log + Count  │ ──→ │ Continue normal  │
  │ (CE)         │     │ (per-bank)   │     │ Scrub region    │
  └─────────────┘     └──────────────┘     └─────────────────┘

  ┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
  │ Uncorrectable│ ──→ │ Poison page  │ ──→ │ Retire page     │
  │ (UE)         │     │ + alert      │     │ Remap workload  │
  └─────────────┘     └──────────────┘     └─────────────────┘

  ┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
  │ CE Storm     │ ──→ │ Page suspect │ ──→ │ Proactive retire│
  │ (>100 CE/hr) │     │ + escalate   │     │ before UE       │
  └─────────────┘     └──────────────┘     └─────────────────┘
```

### 3.4 Patrol Scrubbing

| Parameter | Value |
|---|---|
| Scrub Interval | Every 24 hours (full 288 GB) |
| Scrub Rate | ~3.3 GB/s background |
| Priority | Lowest QoS class (no performance impact) |
| Action on CE | Correct in-place, log, update counter |
| Action on UE | Poison page, alert BMC |
| Scrub Scheduling | Interleaved with normal traffic (< 1% BW impact) |

---

## 4. System-Level Reliability

### 4.1 Redundancy

| Component | Redundancy | Failure Mode |
|---|---|---|
| Power Connectors | 2× 12VHPWR (1,200W total) | Survives single connector failure at reduced TDP |
| VRM Phases | 24 phases (needs 18 minimum) | Survives 6 phase failures |
| Thermal Sensors | 122 total, redundant per zone | Averages/votes per zone |
| Clock PLLs | 2× redundant PLLs per domain | Seamless failover |
| NVLink Lanes | 18 lanes (10 minimum for full BW) | Lane degradation graceful |

### 4.2 Watchdog & Health Monitoring

| Feature | Implementation |
|---|---|
| Hardware Watchdog Timer | 10-second timeout, auto GPU reset |
| Heartbeat | GPU microcontroller → BMC every 1 second |
| Health Score | 0-100, composite of all sensors + error counts |
| Predictive Failure | ML model on error trends (runs on GPU microcontroller) |
| Remote Management | IPMI / Redfish API for datacenter monitoring |
| Syslog Integration | All errors → syslog for SIEM/alerting |

### 4.3 Machine Check Architecture (MCA)

```
GPU Machine Check Architecture:

  Error Bank 0:  Compute Errors (SM-level)
  Error Bank 1:  Memory Errors (L1, L2, HBM)
  Error Bank 2:  Interconnect Errors (NoC, PCIe, NVLink)
  Error Bank 3:  Power/Thermal Events
  Error Bank 4:  Firmware Errors

  Each bank provides:
  ├── Error Status  (corrected / uncorrected / fatal)
  ├── Error Address (physical location of error)
  ├── Error Count   (running counter since boot)
  ├── Error Misc    (syndrome, additional context)
  └── Error Config  (threshold for interrupt/NMI)
```

---

## 5. Component Derating for Longevity

### 5.1 Derating Table

| Component | Standard Max Rating | Our Operating Limit | Derating Factor | Life Extension |
|---|---|---|---|---|
| GPU Die (Tj) | 110°C | **75°C** | 32% temp reduction | ~8× lifetime |
| HBM4 (Tj) | 95°C | **70°C** | 26% temp reduction | ~4× lifetime |
| MLCC Capacitors | 100°C, X7R | **75°C** | 25% temp reduction | ~10× lifetime |
| VRM MOSFETs | 150°C | **100°C** | 33% temp reduction | ~16× lifetime |
| PCB Laminate | Tg=170°C | **90°C** | 47% temp reduction | Long-term stable |
| Electrolytic Caps | 105°C, 10Kh | **70°C** | 33% temp reduction | ~80,000 hours |

### 5.2 Voltage Derating

| Component | Max Voltage | Operating Voltage | Margin |
|---|---|---|---|
| MLCC Capacitors | 16V rated | 12V applied | 25% derating |
| GPU Core | 0.95V abs max | 0.85V max boost | 10.5% margin |
| HBM4 I/O | 1.35V abs max | 1.1V nominal | 18.5% margin |
| PCIe I/O | 1.0V nominal | 1.0V | Per-spec |

---

## 6. Environmental Protection

| Protection | Method |
|---|---|
| Moisture | Parylene-C conformal coating (25 μm) |
| Corrosion | ENEPIG PCB finish + nickel barrier on copper |
| Dust | Sealed liquid cooling loop + filtered air backup |
| Vibration | Backplate stiffener + anti-vibration mounts |
| ESD | Chassis grounding + TVS diodes on all I/O |
| Cosmic Rays | Full ECC on all SRAM + HBM (SER < 1 FIT) |

---

## 7. FMEA Summary (Failure Mode & Effects Analysis)

| Failure Mode | Severity | Probability | Detection | RPN | Mitigation |
|---|---|---|---|---|---|
| HBM die failure | High | Low | ECC detection | 48 | Chipkill correction |
| VRM phase failure | Medium | Low | Current sensor | 36 | 6-phase redundancy |
| Thermal runaway | Critical | Very Low | 122 sensors | 32 | Multi-stage throttle + shutdown |
| NVLink lane failure | Low | Low | CRC errors | 24 | Lane degradation |
| Firmware corruption | High | Very Low | Secure boot verification | 40 | Dual firmware images |
| Solder joint fatigue | Medium | Medium | Continuity test (field) | 60 | Underfill + low ΔT |
| PCIe link degradation | Medium | Low | LTSSM monitoring | 30 | Retimer + speed fallback |

# 06 — PCB & Packaging Design

> **Project AGNI** | Document: PCB & Packaging | Rev: 1.0

---

## 1. GPU Package

### 1.1 Package Technology

| Parameter | Value |
|---|---|
| Package Type | **CoWoS-L** (Chip-on-Wafer-on-Substrate, Large) |
| Interposer | Silicon interposer (12 μm metal pitch) |
| Interposer size | ~110mm × 80mm |
| Package Size | ~100mm × 100mm BGA |
| Package Height | ~4.5mm (die + stiffener) |
| Pin Count | ~25,000 BGA balls |
| Ball Pitch | 0.65mm |
| Substrate | 16-layer ABF (Ajinomoto Build-up Film) |
| Substrate Core | Coreless (for low inductance) |

### 1.2 Die-to-Package Integration

```
Cross-Section View:

  ┌───────────────────────────────────────┐ ← Stiffener Ring (Nickel alloy)
  │                                       │
  │  ┌──GPU Die──┐  ┌HBM┐ ┌HBM┐ ┌HBM┐  │
  │  │  900mm²   │  │ 4 │ │ 4 │ │ 4 │  │ ← Die + HBM stacks
  │  └─────┬─────┘  └─┬─┘ └─┬─┘ └─┬─┘  │
  │        │          │     │     │      │
  │  ┌─────┴──────────┴─────┴─────┴──┐  │ ← Silicon Interposer (CoWoS-L)
  │  │    μ-bumps (36μm pitch)        │  │
  │  │    RDL (redistribution layer)   │  │
  │  │    TSVs (5μm × 50μm)          │  │
  │  └────────────┬───────────────────┘  │
  │               │                      │
  │  ┌────────────┴───────────────────┐  │ ← Organic Substrate (16-layer ABF)
  │  │    C4 bumps (130μm pitch)      │  │
  │  │    Signal + Power routing       │  │
  │  └────────────┬───────────────────┘  │
  │               │                      │
  │  ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○  │ ← BGA Balls (0.65mm pitch)
  └───────────────────────────────────────┘
```

### 1.3 Underfill & Solder

| Parameter | Value |
|---|---|
| μ-bump Material | Cu pillar + SnAg cap |
| C4 Bump Material | SnAg (lead-free) |
| BGA Ball Material | SAC305 (Sn96.5/Ag3.0/Cu0.5) |
| Underfill | Capillary underfill (CUF) |
| Edge Bond | Adhesive edge bond for HBM stacks |
| Warpage Control | Stiffener ring + DAM adhesive |

---

## 2. Board Design

### 2.1 PCB Specification

| Parameter | Value |
|---|---|
| Layer Count | 20+ layers |
| Board Material | **Megtron 7** (Dk=3.4, Df=0.001 @ 10GHz) |
| Board Thickness | 2.4mm |
| Copper Weight | 1oz signal, 2oz power |
| Min Trace/Space | 75μm / 75μm (outer), 50μm / 50μm (inner) |
| Via Technology | Laser-drilled microvias + through-hole |
| HDI Levels | 3+N+3 sequential build-up |
| Size | ~300mm × 130mm (full-length dual-slot) |

### 2.2 Layer Stack-Up

```
20-Layer Stack-Up:

  L1:  Signal (PCIe TX)           ← Impedance controlled
  L2:  Ground Reference           ← Return path
  L3:  Signal (PCIe RX)           ← Impedance controlled
  L4:  Ground Reference           
  L5:  Signal (NVLink TX)         ← High-speed, length-matched
  L6:  Ground Reference
  L7:  Power Plane (Vdd Core)     ← Low impedance, wide plane
  L8:  Ground Reference
  L9:  Signal (General purpose)
  L10: Ground Reference (central) ← EMI shielding
  L11: Ground Reference (central)
  L12: Signal (General purpose)
  L13: Ground Reference
  L14: Power Plane (Vdd HBM)      
  L15: Ground Reference
  L16: Signal (NVLink RX)         ← High-speed, length-matched
  L17: Ground Reference
  L18: Signal (Low-speed ctrl)     ← I2C, SPI, JTAG
  L19: Power Plane (12V input)
  L20: Ground Reference (bottom)
```

### 2.3 Signal Integrity

| Parameter | Target |
|---|---|
| PCIe 6.0 (64 GT/s) | IL < 12 dB @ 32 GHz, RL < -10 dB |
| NVLink 5.0 | IL < 10 dB @ 28 GHz |
| Impedance (single-ended) | 50Ω ± 5% |
| Impedance (differential) | 85Ω ± 5% or 100Ω ± 5% |
| Length Matching | ±50 mil within differential pair |
| Skew (inter-pair) | < 100 ps |
| Retimer | Broadcom/Marvell PCIe 6.0 retimer on-board |

### 2.4 Power Integrity

| Parameter | Target |
|---|---|
| PDN Impedance (Vdd) | < 0.3 mΩ @ DC, < 1 mΩ @ 100 MHz |
| Decoupling Capacitors | 2,400× 0402 MLCC (100nF) distributed |
| Bulk Capacitors | 64× 47μF MLCC (0805) |
| Embedded Capacitance | Inter-plane capacitance (L7-L8, L14-L15) |
| Ripple (VRM output) | < 10 mV peak-to-peak |
| Transient Droop | < 30 mV at 500 A/μs |

---

## 3. PCB Surface Finish

| Finish Type | **ENEPIG** (Electroless Nickel / Electroless Palladium / Immersion Gold) |
|---|---|
| Nickel Thickness | 3–6 μm |
| Palladium Thickness | 0.05–0.15 μm |
| Gold Thickness | 0.03–0.10 μm |
| Rationale | Best corrosion resistance, compatible with SnAg solder |
| Alternative | ENIG (no Palladium) — lower cost, slightly less reliable |

---

## 4. Mechanical Design

### 4.1 Form Factor

| Parameter | Value |
|---|---|
| Form Factor | PCIe full-length, dual-slot (or OAM module) |
| Slot Interface | PCIe 6.0 x16 gold-finger |
| Retention | Backplate + retention bracket |
| Weight | ~2.5 kg (with heatsink) |
| Backplate | Full-coverage aluminum backplate (VRM cooling + rigidity) |

### 4.2 Conformal Coating

| Parameter | Value |
|---|---|
| Material | **Parylene-C** |
| Thickness | 25 μm |
| Coverage | Full board excluding connectors |
| Protection | Moisture, salt spray, fungus, corrosion |
| Compliance | IPC-CC-830C Class 3 |
| Application | Chemical vapor deposition (CVD) |
| Temperature Rating | -200°C to +200°C |

---

## 5. Bill of Materials (Key Components)

| Component | Part Number / Spec | Supplier | Qty |
|---|---|---|---|
| GPU Die | AGNI-100 (TSMC N3E, 900mm²) | TSMC | 1 |
| HBM4 Stack | H4-24G-12Hi | SK Hynix | 6 |
| Silicon Interposer | CoWoS-L custom | TSMC | 1 |
| DrMOS (VRM) | TDA38640 (90A) | Infineon | 24 |
| VRM Controller | XDPE192C3B | Infineon | 1 |
| MLCC 100nF 0402 | GCM155R71C104KA55 | Murata | 2,400 |
| MLCC 47μF 0805 | GRM21BD71A476ME15 | Murata | 64 |
| PCIe 6.0 Retimer | Custom SerDes | Broadcom | 1 |
| NVLink SerDes | Custom PHY | NVIDIA IP | 18 |
| Temperature Sensor | TMP461 | Texas Instruments | 8 |
| Voltage Monitor | INA226 | Texas Instruments | 6 |
| PCB | 20L Megtron 7 | AT&S / Ibiden | 1 |
| Cold Plate | Cu micro-channel, Ni-plated | CoolIT | 1 |
| Liquid Metal TIM | Conductonaut | Thermal Grizzly | 1 |
| Conformal Coating | Parylene-C, 25μm | SCS (Specialty Coating) | 1 |
| 12VHPWR Connector | Amphenol 16-pin | Amphenol | 2 |
| Backplate | Aluminum 6061, anodized | Custom | 1 |

# 04 — Power Delivery & Thermal Management

> **Project AGNI** | Document: Power & Thermal | Rev: 1.0

---

## 1. Power Architecture

### 1.1 Power Budget

| Parameter | Value |
|---|---|
| **TDP** | **900W** (unrestricted) |
| Peak Transient Power | ~1,100W (< 10 ms bursts) |
| Idle Power (P8) | < 50W |
| HBM4 Power | ~270W (6 stacks active) |
| GPU Die Power | ~580W |
| VRM + Board Power | ~50W |
| **Total System Slot Power** | **~950W** (with losses) |

### 1.2 Power Delivery Network (PDN)

| Parameter | Value |
|---|---|
| Input Voltage | 12V standard / 48V preferred |
| Core Voltage (Vdd) | 0.65V – 0.85V (DVFS range) |
| Nominal Vdd | 0.75V |
| VRM Phases | 24-phase digital VRM |
| VRM Controller | Infineon XDPE192C3B (digital multiphase) |
| DrMOS | Infineon TDA38640 (90A per phase) |
| Max VRM Current | 2,160A (24 × 90A) |
| Efficiency | > 92% at full load |
| Voltage Accuracy | ±0.5% load-line regulation |
| Transient Response | < 30 mV droop at 500A/μs step |

### 1.3 Power Connectors

| Connector | Rating | Count |
|---|---|---|
| 12VHPWR (16-pin) | 600W each | 2 connectors |
| Total Input Capacity | 1,200W | Redundant (survives 1 failure at reduced power) |
| Sense Pins | Present, with handshake | Per-connector power negotiation |

### 1.4 Power Rails

```
Power Rail Architecture:

  12V / 48V Input
       ↓
  ┌─────────────────────────────────────┐
  │  24-Phase Digital VRM               │
  │  ┌────────┐  ┌────────┐           │
  │  │Rail A  │  │Rail B  │  (redundant)│
  │  │12 phase│  │12 phase│           │
  │  └───┬────┘  └───┬────┘           │
  │      ↓           ↓                │
  │  ┌─────────────────┐              │
  │  │ Vdd GPU Core    │ 0.75V / 1200A│
  │  └─────────────────┘              │
  │                                    │
  │  ┌─────────┐  ┌─────────┐        │
  │  │Vdd_HBM  │  │Vdd_IO   │        │
  │  │1.1V/40A │  │1.2V/30A │        │
  │  └─────────┘  └─────────┘        │
  │                                    │
  │  ┌─────────┐  ┌─────────┐        │
  │  │Vdd_PLL  │  │Vdd_Aux  │        │
  │  │0.9V/5A  │  │3.3V/2A  │        │
  │  └─────────┘  └─────────┘        │
  └─────────────────────────────────────┘
```

### 1.5 Power Protection

| Protection | Implementation |
|---|---|
| OVP (Over-Voltage) | Hardware comparator, < 1 μs response |
| UVP (Under-Voltage) | Brown-out detection + graceful shutdown |
| OCP (Over-Current) | Per-phase current sensing + shutdown |
| OTP (Over-Temperature) | Dual threshold: throttle (83°C) + shutdown (95°C) |
| Short Circuit | < 500 ns detection + crowbar |

---

## 2. Thermal Management

### 2.1 Thermal Design Philosophy

> **Longevity-first:** We target **Tj < 75°C** under sustained load. Industry allows 110°C, but every 10°C reduction roughly **doubles** component lifetime (Arrhenius rule).

### 2.2 Primary Cooling: Direct-Die Liquid Cooling

| Parameter | Value |
|---|---|
| Cooling Type | Direct-die cold plate (copper) |
| Cold Plate Material | Oxygen-free copper (C101), nickel-plated |
| Channel Type | Micro-channel (0.2mm fin pitch) |
| Coolant | Propylene glycol / water (30/70) |
| Flow Rate | ≥ 2.5 L/min |
| Inlet Temperature | ≤ 30°C (datacenter supply) |
| Thermal Resistance (cold plate) | < 0.015 °C/W |
| Expected Tj at 900W | **~72°C** (at 30°C inlet) |
| HBM Coverage | Extended cold plate covers all 6 HBM stacks |

### 2.3 Thermal Interface Material (TIM)

| Parameter | Value |
|---|---|
| TIM Type | Liquid metal (Indium-Gallium alloy) |
| Thermal Conductivity | ~80 W/mK |
| Bond Line Thickness | < 25 μm |
| Reliability | > 50,000 hours without pump-out |
| Corrosion Protection | Nickel barrier on copper surfaces |
| Application | Automated dispensing (±5 μm tolerance) |
| vs. Traditional Paste | 10× better thermal conductivity |

### 2.4 Backup Cooling: Vapor Chamber + Air

| Parameter | Value |
|---|---|
| Vapor Chamber | 150mm × 100mm, sintered copper wick |
| Heat Pipes | 8× Ø8mm, flattened |
| Heatsink | 4-tower fin stack, 60 aluminum fins |
| Fans | 3× 120mm, 3,200 RPM max |
| Airflow | > 120 CFM |
| TDP Capability | Up to 600W in air-only mode |
| Use Case | Fail-safe if liquid cooling fails |

### 2.5 Thermal Throttling Strategy

```
Temperature-Based Performance Bands:

  ┌──────────────────────────────────────────┐
  │ < 65°C   │ FULL BOOST (2.6 GHz)        │ ← Target operating zone
  │ 65-75°C  │ BASE CLOCK (1.8 GHz)        │ ← Sustained workload safe zone
  │ 75-83°C  │ GRADUAL THROTTLE            │ ← -100 MHz steps
  │           │ (2.6→2.5→2.4→...→1.5 GHz)  │
  │ 83°C     │ EMERGENCY THROTTLE (P8)     │ ← Alert to BMC
  │ 95°C     │ HARD SHUTDOWN               │ ← Hardware cutoff
  └──────────────────────────────────────────┘
```

### 2.6 Thermal Sensors

| Location | Count | Type |
|---|---|---|
| GPU Die | 64 distributed | On-die diode sensors |
| HBM4 Stacks | 6 per stack (36 total) | JEDEC DRAM temp sensor |
| VRM | 12 (per 2-phase group) | NTC thermistor |
| PCB | 8 (hotspot zones) | NTC thermistor |
| Cold Plate Inlet/Outlet | 2 | RTD sensor (PT100) |
| **Total Sensors** | **122** | |

### 2.7 Fan/Pump Control Algorithm

```python
# PID-based thermal control with predictive model
class ThermalController:
    def __init__(self):
        self.Kp = 2.0      # Proportional gain
        self.Ki = 0.1       # Integral gain  
        self.Kd = 0.5       # Derivative gain
        self.target = 70.0  # Target Tj (°C)
    
    def update(self, current_temp, dt):
        error = current_temp - self.target
        self.integral += error * dt
        derivative = (error - self.prev_error) / dt
        
        output = (self.Kp * error + 
                  self.Ki * self.integral + 
                  self.Kd * derivative)
        
        # Predictive: if dT/dt > 2°C/s, pre-emptively increase
        if derivative > 2.0:
            output *= 1.5
        
        self.prev_error = error
        return clamp(output, 0, 100)  # % duty cycle
```

---

## 3. Power States (DVFS)

| State | Frequency | Voltage | Power | Use Case |
|---|---|---|---|---|
| P0-Boost | 2,600 MHz | 0.85V | 900W | Peak burst compute |
| P0-Base | 1,800 MHz | 0.75V | 500W | Sustained compute |
| P1 | 1,200 MHz | 0.70V | 280W | Medium load |
| P2 | 800 MHz | 0.65V | 150W | Light load |
| P8 | 300 MHz | 0.60V | 50W | Idle / standby |
| Off | — | 0V | 5W (aux rail) | Shutdown (BMC power) |

### 3.1 P-State Transition Timing

| Transition | Latency |
|---|---|
| P8 → P0 | < 10 μs |
| P0 → P0-Boost | < 1 μs |
| P0 → P8 | < 100 μs |
| Voltage change step | 6.25 mV / μs (VRM slew rate) |

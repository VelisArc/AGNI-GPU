# 03 — Interconnect & I/O Architecture

> **Project AGNI** | Document: Interconnect & I/O | Rev: 1.0

---

## 1. External Interfaces

### 1.1 PCIe Gen 6.0

| Parameter | Value |
|---|---|
| Version | PCIe 6.0 |
| Lanes | x16 |
| Data Rate | 64 GT/s per lane (PAM4) |
| Bandwidth (unidirectional) | 128 GB/s |
| Bandwidth (bidirectional) | 256 GB/s |
| Encoding | 1b/1b (FLIT-based) |
| CRC | Per-FLIT CRC + retry (link-level reliability) |
| LTSSM | Full power management state machine |
| ATS | Address Translation Services for SVM |
| SR-IOV | Hardware GPU partitioning (MIG) |

### 1.2 NVLink 5.0

| Parameter | Value |
|---|---|
| NVLink Version | 5.0 |
| Links | 18 lanes |
| Bandwidth per Link | 100 GB/s bidirectional |
| **Total NVLink BW** | **1,800 GB/s (1.8 TB/s)** |
| Protocol | High-speed SerDes, PAM4 |
| Error Handling | Link-level CRC + replay |
| Topology Support | All-to-all via NVSwitch |
| Use Case | Multi-GPU scale-out (8-GPU DGX) |

### 1.3 NVSwitch Port

| Parameter | Value |
|---|---|
| Dedicated Switch Port | Yes |
| Switch Fabric BW | 14.4 TB/s (8-GPU all-to-all) |
| SHARP (In-network Compute) | AllReduce in-switch |
| Multicast | Hardware multicast for broadcast ops |

---

## 2. Internal Network-on-Chip (NoC)

### 2.1 Topology

```
Hybrid Ring + 2D Mesh NoC:

    ┌─────┬─────┬─────┬─────┐
    │GPC 0│GPC 1│GPC 2│GPC 3│
    ├─────┼─────┼─────┼─────┤  ← 2D Mesh links (vertical + horizontal)
    │GPC 4│GPC 5│GPC 6│GPC 7│
    ├─────┴─────┴─────┴─────┤
    │     L2 Cache Slices    │  ← Ring interconnect for L2
    ├─────┬─────┬─────┬─────┤
    │GPC 8│GPC 9│GPC10│GPC11│
    ├─────┼─────┼─────┼─────┤
    │GPC12│GPC13│GPC14│GPC15│
    └─────┴─────┴─────┴─────┘
         ↕ HBM4 Controllers ↕
```

### 2.2 NoC Specifications

| Parameter | Value |
|---|---|
| Topology | Hybrid: 2D mesh (GPCs) + Ring (L2 slices) |
| Fabric Clock | 2,000 MHz |
| Link Width | 512 bits per direction |
| Bisection Bandwidth | > 30 TB/s |
| Hop Latency | ~4 ns per hop |
| Max Hops (worst case) | 8 hops |
| QoS Levels | 4 priority classes |
| Flow Control | Credit-based, virtual channels |
| Deadlock Freedom | Dimension-ordered routing |

### 2.3 QoS Priority Classes

| Class | Traffic Type | Priority |
|---|---|---|
| P0 | Compute (GEMM, Tensor Core) | Highest |
| P1 | Memory (L2 fill/writeback) | High |
| P2 | I/O (PCIe, NVLink) | Medium |
| P3 | Management (telemetry, ECC scrub) | Low |

---

## 3. DMA & Copy Engines

| Feature | Value |
|---|---|
| Copy Engines | 8 independent bidirectional |
| Host→Device BW | 128 GB/s (PCIe 6.0) |
| Peer→Peer BW | 1.8 TB/s (NVLink 5.0) |
| Async Copy | Overlaps with compute kernels |
| Compression | Hardware LZ4 for sparse data transfers |
| Peer Mapping | Direct GPU-to-GPU memory mapping |

---

## 4. Multi-Instance GPU (MIG)

| Feature | Value |
|---|---|
| Max Instances | 8 MIG instances |
| Per-Instance | 32 SMs, 36 GB HBM, dedicated L2 slice |
| Isolation | Full hardware isolation (memory, compute, cache) |
| Use Case | Multi-tenant inference serving |
| GPU Partitioning | VGPU support via hypervisor |

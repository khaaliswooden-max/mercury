# PHYSICS.md — Mercury Physical Envelope

**Project:** Mercury (a minimal bit-serial computer)
**Author:** Aldrich K. Wooden, Sr.
**Status:** Phase 0 — Locked
**Convention:** Epistemic markers per Zuup Research Framework
&nbsp;&nbsp;&nbsp;&nbsp;✓ VERIFIED — grounded in established physics
&nbsp;&nbsp;&nbsp;&nbsp;◐ PLAUSIBLE — supported by analogical reasoning
&nbsp;&nbsp;&nbsp;&nbsp;◯ SPECULATIVE — extrapolation requiring validation

---

## 1. Purpose

Mercury treats Lloyd's bounds (Nature 405, 2000) as hard runtime constraints, not aspirations. Every bit flip in the Mercury simulator and FPGA implementation is accounted for against three physical ceilings: Margolus–Levitin (ops/sec), Bekenstein (storage), and Landauer (energy per erasure). This document fixes the constants those ceilings depend on.

Two envelopes are defined. Both use the same rest mass `m = 1 kg`. They differ only in radius `R` and temperature `T`, which drives the storage and erasure floors apart by tens of orders of magnitude.

---

## 2. Axioms (Foundational Constants)

✓ All values from CODATA / SI. Where SI defines an exact value, full precision is used.

| Symbol | Value | Unit |
|---|---|---|
| ℏ  | 1.054 571 817 × 10⁻³⁴ | J·s |
| c  | 299 792 458 (exact) | m/s |
| G  | 6.674 30 × 10⁻¹¹ | m³ kg⁻¹ s⁻² |
| k_B | 1.380 649 × 10⁻²³ (exact) | J/K |
| ln 2 | 0.693 147 180 559 945 | — |

---

## 3. Governing Equations

✓ Derivations standard; restated here for self-containment.

**Margolus–Levitin ops ceiling** (max distinct quantum state transitions per second, given total energy E above ground state):

&nbsp;&nbsp;&nbsp;&nbsp;`N_ops/s ≤ 2E / (π ℏ)`

**Bekenstein storage bound** (max bits in region of radius R containing energy E):

&nbsp;&nbsp;&nbsp;&nbsp;`N_bits ≤ 2π E R / (ℏ c · ln 2)`

**Landauer erasure floor** (min dissipation per logically irreversible bit operation at temperature T):

&nbsp;&nbsp;&nbsp;&nbsp;`E_erase ≥ k_B T · ln 2`

**Light-crossing time** (relativistic signal propagation across the system):

&nbsp;&nbsp;&nbsp;&nbsp;`t_cross = R / c`

**Per-bit flip time** (Margolus–Levitin ceiling distributed across the Bekenstein-permitted bit count):

&nbsp;&nbsp;&nbsp;&nbsp;`t_flip = π ℏ N_bits / (2E)`

---

## 4. Config A — Desktop (Pragmatic)

◐ Radius and temperature chosen for engineering tractability. The 1 kg / 10 cm / 300 K envelope is what an FPGA-realized Mercury could plausibly be benchmarked against without leaving the room-temperature classical regime.

| Quantity | Value |
|---|---|
| m | 1.0 kg |
| R | 0.10 m |
| T | 300 K |
| E = mc² | 8.987 552 × 10¹⁶ J |
| **Ops ceiling** (Margolus–Levitin) | **5.426 × 10⁵⁰ ops/s** |
| **Storage ceiling** (Bekenstein) | **2.577 × 10⁴² bits** |
| **Erasure floor** (Landauer) | **2.871 × 10⁻²¹ J / bit** |
| Light-crossing time | 3.336 × 10⁻¹⁰ s |
| Per-bit flip time | 4.750 × 10⁻⁹ s |

---

## 5. Config B — Lloyd Limit (Symbolic)

◐ The "ultimate computer" regime: same 1 kg compressed to its Schwarzschild radius, temperature set by Hawking's formula. The FPGA cannot physically realize this, but Mercury's ledger can score against it for the compliance report.

| Quantity | Value | Formula |
|---|---|---|
| m | 1.0 kg | — |
| R = R_s | 1.485 × 10⁻²⁷ m | `2Gm/c²` |
| T = T_H | 1.227 × 10²³ K | `ℏc³ / (8π G m k_B)` |
| E = mc² | 8.987 552 × 10¹⁶ J | — |
| **Ops ceiling** | **5.426 × 10⁵⁰ ops/s** | (unchanged — depends only on E) |
| **Storage ceiling** | **3.827 × 10¹⁶ bits** | holographic; ↓ 26 orders vs Config A |
| **Erasure floor** | **1.174 J / bit** | ↑ 21 orders vs Config A |
| Light-crossing time | 4.954 × 10⁻³⁶ s | |
| Per-bit flip time | 7.054 × 10⁻³⁵ s | |

✓ The 3.83 × 10¹⁶-bit figure for a 1 kg black hole reproduces the canonical holographic-principle result. The Hawking temperature of 1.23 × 10²³ K (hotter than any astrophysical environment) is why the Landauer floor balloons from sub-attojoule to over a joule per bit.

---

## 6. Cross-Envelope Synthesis

✓ A structural identity falls out of the bounds:

&nbsp;&nbsp;&nbsp;&nbsp;`t_flip / t_cross  =  π² / ln 2  ≈  14.2388`

This ratio is **identical for both configs** and independent of `m`, `R`, and `T`. It is a property of the bounds themselves, not of the envelope. Interpretation: the gap between "how fast can one bit flip if all energy is shared evenly" and "how long does a signal take to cross the system" is fixed by the geometry of the inequalities. Lloyd's "convergence" claim is therefore qualitative — both configs are ~14× off from equality, but Config B is at the joint saturation of storage and ops/sec, where Config A has 26 orders of magnitude of storage headroom unused.

◐ Design implication: the FPGA implementation cannot meaningfully exploit parallelism beyond what the chosen envelope's per-bit-flip-time × bit-count product allows. A bit-serial datapath is therefore not a hardware compromise — it is the architecture that matches the envelope's actual budget.

---

## 7. Uncertainties

| Item | Marker | Note |
|---|---|---|
| Constants in §2 | ✓ | SI-defined or CODATA |
| Equations in §3 | ✓ | Standard derivations |
| Config A R, T choice | ◐ | Engineering pragmatism, not physical necessity |
| Config B physical realizability | ◯ | A 1 kg black hole is unstable on timescales << 1 s; "running" Mercury at this envelope is symbolic |
| π²/ln 2 identity | ✓ | Direct algebraic consequence of the bound forms used |

---

## 8. Downstream Use

These constants are consumed by:
- `crates/mercury-sim/` — Rust functional model, runtime ledger
- `hw/mercury-fpga/` — SystemVerilog, synthesis constraints
- `docs/compliance.md` — Phase 5 report

`config.toml` is the single source of truth at runtime. Editing constants requires updating this document, the TOML, and the regenerated derivation table together — no silent drift.

---

## 9. References

1. Lloyd, S. *Ultimate physical limits to computation.* Nature **406**, 1047–1054 (2000).
2. Margolus, N. & Levitin, L. B. *The maximum speed of dynamical evolution.* Physica D **120**, 188–195 (1998).
3. Bekenstein, J. D. *Universal upper bound on the entropy-to-energy ratio for bounded systems.* Phys. Rev. D **23**, 287 (1981).
4. Landauer, R. *Irreversibility and heat generation in the computing process.* IBM J. Res. Dev. **5**, 183–191 (1961).
5. Bekenstein, J. D. *Black holes and entropy.* Phys. Rev. D **7**, 2333 (1973).

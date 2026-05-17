# ARCH.md — Mercury Architecture Specification

**Project:** Mercury (a minimal bit-serial computer)
**Author:** Aldrich K. Wooden, Sr.
**Status:** Phase 1 — Locked
**Depends on:** [`PHYSICS.md`](./PHYSICS.md), [`config.toml`](./config.toml)
**Convention:** Epistemic markers per Zuup Research Framework
&nbsp;&nbsp;&nbsp;&nbsp;✓ VERIFIED — grounded in established CS/EE practice
&nbsp;&nbsp;&nbsp;&nbsp;◐ PLAUSIBLE — engineering judgment, defensible
&nbsp;&nbsp;&nbsp;&nbsp;◯ SPECULATIVE — design freedom, subject to revision

---

## 1. Scope

This document specifies the Mercury architecture with enough precision that the Rust functional model (Phase 2) and the SystemVerilog FPGA implementation (Phase 3) produce **byte-equivalent execution traces** on the same program. Conformance is bit-level, not behavioural.

The compliance ledger in `PHYSICS.md` is fed by counters defined here. Every bit movement specified in §6 is countable; the ledger sums them against the ceilings.

---

## 2. ISA: Subleq

✓ Subleq ("SUBtract and branch if Less than or Equal to zero") is a one-instruction set computer (OISC), proven Turing-complete. Mercury uses unmodified Subleq; no instruction decoder is required.

### 2.1 Instruction format

Every instruction is three consecutive memory words: `A`, `B`, `C`.

```
    Operational semantics:

    mem[B] ← mem[B] − mem[A]
    if mem[B] ≤ 0:   PC ← C
    else:            PC ← PC + 3
```

### 2.2 Halt

✓ `C = 0xFFFF` is the halt sentinel. When a branch is taken to `0xFFFF` the machine asserts `HALTED` and clocks stop advancing the PC. The subtract and store still complete normally before halt is recognized.

### 2.3 I/O

◐ Deferred to Phase 4. Memory addresses `0xFFFC` (input) and `0xFFFD` (output) are reserved. The Phase 2 simulator stubs them to stdin/stdout; the Phase 3 FPGA wires them to a UART. They are **not** implemented in Phase 1.

---

## 3. Word format

✓ Locked.

| Property | Value |
|---|---|
| Word width `W` | 16 bits |
| Number representation | Two's complement, signed |
| Range | −32 768 … +32 767 |
| Bit ordering on the bit-bus | **LSB-first** |
| Address space | 2¹⁶ words = 65 536 words = 1 Mbit memory |
| Endian (multi-word values) | Not applicable; all values are single-word |

✓ LSB-first is forced by the architecture: bit-serial subtraction propagates carry from LSB to MSB. Reversing the order would require either a separate reverse phase or a ripple in the wrong direction.

◐ The choice of W = 16 is engineering pragmatism. The desktop envelope's Bekenstein cap is 2.58 × 10⁴² bits — 36 orders of magnitude of headroom over the 1 Mbit Mercury occupies. The Lloyd-envelope cap is 3.83 × 10¹⁶ bits, still 10¹⁰× our footprint. Word size is not envelope-constrained; it is chosen so 16-bit Subleq programs have enough range to be non-trivial.

---

## 4. Datapath

✓ Single bit-bus. Every register that holds an address or operand is a shift register clocked by the same global clock. There is exactly one combinational arithmetic element: a full adder.

### 4.1 Block diagram

```
                ┌──────────────────────────────────┐
                │     Memory  (bit-addressable)    │
                │  64 K words × 16 b = 1 Mbit       │
                └──────────────────┬───────────────┘
                                   │  bit-bus (1 b/cycle)
        ┌─────────┬─────────┬──────┴──────┬─────────┬─────────┐
        ▼         ▼         ▼             ▼         ▼         ▼
     ┌─────┐  ┌─────┐   ┌─────┐       ┌─────┐  ┌──────┐  ┌──────┐
     │  PC │  │ AR  │   │ BR  │       │ CR  │  │ OP1  │  │ OP2  │
     │ 16b │  │ 16b │   │ 16b │       │ 16b │  │ 16 b │  │ 16 b │
     └──┬──┘  └─────┘   └─────┘       └─────┘  └──┬───┘  └──┬───┘
        │                                         │   ┌─────┘
        │                                         │   │
        │                                         │   ▼
        │                                         │ [INVERT]   (B̄ for subtract)
        │                                         │   │
        │                                         ▼   ▼
        │                                       ┌─────────┐
        │                                       │ 1-bit   │←── C_in latch
        │                                       │ ADDER   │     (init = 1 for −)
        │                                       └────┬────┘
        │                                            │
        │                                            ▼
        │                                       ┌─────────┐
        │                                       │ RESULT  │
        │                                       │  16 b   │
        │                                       └────┬────┘
        │                                            │
        │                                  ┌─────────┴─────────┐
        │                                  ▼                   ▼
        │                              SIGN latch        ZERO_OR latch
        │                              (MSB of result)   (OR of all bits)
        │                                  │                   │
        │                                  └─────────┬─────────┘
        │                                            ▼
        │                                       BRANCH_TAKEN
        │                                   = sign ∨ ¬zero_or
        │                                            │
        └──── PC ← C if taken, else PC+3 ◀──────────┘
```

### 4.2 Register inventory

| Name | Width | Type | Purpose |
|---|---|---|---|
| `PC`  | 16 b | shift reg | Program counter |
| `AR`  | 16 b | shift reg | Operand A address (fetched from `mem[PC]`) |
| `BR`  | 16 b | shift reg | Operand B address (fetched from `mem[PC+1]`) |
| `CR`  | 16 b | shift reg | Branch target (fetched from `mem[PC+2]`) |
| `OP1` | 16 b | shift reg | Value of `mem[AR]` |
| `OP2` | 16 b | shift reg | Value of `mem[BR]` |
| `RES` | 16 b | shift reg | Subtraction result |
| `C_in` | 1 b | latch | Carry between adder ticks |
| `SIGN` | 1 b | latch | Captured MSB of result |
| `ZERO_OR` | 1 b | latch | OR of all result bits during EX |
| `HALTED` | 1 b | latch | Set when branch target = `0xFFFF` |

✓ Eleven state elements, only one of them combinational (the adder). This is the minimality claim.

### 4.3 What is *not* in the datapath

✓ No instruction register, no opcode decoder, no microcode ROM, no general-purpose register file, no immediate field handling, no multi-bit ALU, no carry-lookahead, no condition-code register beyond `SIGN`/`ZERO_OR`, no interrupt logic. If a component is not in §4.2 it does not exist.

---

## 5. Memory model

### 5.1 Architectural view

✓ Memory is exposed as a bit-bus: one bit transferred per cycle, LSB-first within each word. The address presented is a 16-bit word address; the bit-bus then carries 16 cycles' worth of data for that word.

### 5.2 Implementation freedom

◐ The two implementations realize this differently:

- **Rust simulator (Phase 2):** memory as `Vec<u16>` of 65 536 words. The bit-bus is synthesized by shift operations.
- **FPGA (Phase 3):** memory as on-chip BRAM (UltraScale+ has 36 Kb blocks; we need ~29 blocks for 1 Mbit). BRAM is word-parallel at the cell level; a parallel-in/serial-out shift register adapts it to the bit-bus.

◯ The BRAM realization is a concession to FPGA physics. A literal mercury-delay-line analog (single circulating bit stream, no random access) would force every memory access to wait for the right bit to come around. That is faithful to the 1949 architecture but throws away ~five orders of magnitude of throughput on the FPGA. Decision: present a bit-serial **interface**, allow a word-parallel **substrate**. Documented as a deviation in `docs/deviations.md` once Phase 3 begins.

### 5.3 Reset state

✓ On reset: all memory zeroed, `PC = 0`, all registers and latches cleared, `HALTED = 0`. Programs are loaded via an out-of-band loader port (UART on FPGA, file I/O in simulator), not over the bit-bus.

---

## 6. Execution sequencing

✓ Each Subleq instruction takes 8 phases, each of `W = 16` cycles. **Total: 128 cycles per instruction.** A small FSM (4-bit state) sequences the phases.

| Phase | Cycles | Action | Bit movements |
|---|---|---|---|
| `F1` | 16 | `AR ← mem[PC]` | 16 reads |
| `F2` | 16 | `BR ← mem[PC+1]` | 16 reads |
| `F3` | 16 | `CR ← mem[PC+2]` | 16 reads |
| `L1` | 16 | `OP1 ← mem[AR]` | 16 reads |
| `L2` | 16 | `OP2 ← mem[BR]` | 16 reads |
| `EX` | 16 | bit-serial subtract: `RES ← OP2 − OP1`; capture `SIGN`, `ZERO_OR` | 16 adder ticks, 16 result writes |
| `ST` | 16 | `mem[BR] ← RES` | 16 writes |
| `BR` | 16 | `PC ← (SIGN ∨ ¬ZERO_OR) ? CR : PC + 3`; check halt | 16 bit-serial PC updates |

✓ `PC + 3` in BR phase is performed bit-serially using the same adder: shift PC out LSB-first, feed `+3` as the second operand (a 16-bit constant `0000…00000011`), reuse the carry latch.

### 6.1 Cycle-accuracy contract

✓ Both implementations must complete each phase in **exactly** 16 cycles. The FSM does not stall, branch, or skip. This makes execution traces byte-equivalent and the ledger deterministic.

### 6.2 Performance envelope

At a target clock of 100 MHz:

| Metric | Value | Note |
|---|---|---|
| Instructions / second | 7.81 × 10⁵ | 100 MHz ÷ 128 |
| Irreversible bit ops / second | ≈ 5 × 10⁷ | conservative; see §7.2 |
| Fraction of Margolus–Levitin (any envelope) | 9.2 × 10⁻⁴⁴ | both Configs A and B |
| Bekenstein occupancy (desktop) | 4.1 × 10⁻³⁷ | 1 Mbit / 2.58 × 10⁴² |
| Bekenstein occupancy (Lloyd) | 2.7 × 10⁻¹¹ | 1 Mbit / 3.83 × 10¹⁶ |
| Landauer power (desktop) | 1.4 × 10⁻¹³ W | classical floor |
| Landauer power (Lloyd) | **5.9 × 10⁷ W** | 59 MW heat at Hawking T |

◐ The Lloyd-envelope Landauer power is the punchline. Running Mercury inside a 1 kg black hole's Hawking-temperature bath would dissipate ~59 MW of unavoidable heat per second of operation. The classical irreversible architecture is not energetically realizable at the Lloyd limit. Phase 6 (reversible-logic variant) would address this; Phases 1–5 surface it explicitly via the compliance ledger.

---

## 7. Bit-serial arithmetic

### 7.1 Subtraction circuit

✓ `A − B` is computed as `A + B̄ + 1` (two's complement). The implementation:

```
  cycle i of EX phase:
    a_i  = OP2[i]            (LSB-first stream out of OP2)
    b_i  = ¬OP1[i]           (LSB-first, inverted, from OP1)
    s_i  = a_i ⊕ b_i ⊕ C_in
    c'   = (a_i ∧ b_i) ∨ (C_in ∧ (a_i ⊕ b_i))
    RES[i] ← s_i
    SIGN  ← s_i              (overwritten each cycle; final value = MSB)
    ZERO_OR ← ZERO_OR ∨ s_i
    C_in  ← c'

  pre-phase: C_in initialized to 1 (the "+1" of two's complement)
```

### 7.2 Bit-op counting (for the ledger)

✓ Per instruction:
- 5 × 16 = 80 read transits (F1, F2, F3, L1, L2)
- 16 adder ticks (EX)
- 16 + 16 = 32 write transits (ST, BR)
- 1 sign capture, 16 zero-OR updates ≈ negligible for counting

The ledger counts **128 bit-transits per instruction**. At 100 MHz / 128 cycles per instruction × 128 transits ≈ 10⁸ bit-transits per second. The "5 × 10⁷ irreversible" figure in §6.2 conservatively halves this on the assumption that read transits and write transits don't both count as full erasures (a read followed by a non-overwriting use is reversible-in-principle).

◐ The counting convention is documented and consistent, not physically definitive. Phase 5 may refine it after literature review of Bennett-style reversibility accounting.

---

## 8. Branch decision

✓ Condition: `RES ≤ 0`.

- `RES < 0`  ⇔  `SIGN = 1` (MSB of two's complement)
- `RES = 0`  ⇔  `ZERO_OR = 0` after all 16 cycles

Therefore:

&nbsp;&nbsp;&nbsp;&nbsp;`BRANCH_TAKEN = SIGN ∨ ¬ZERO_OR`

Both latches are reset to 0 at the start of every EX phase.

---

## 9. Halt detection

✓ During BR phase, after `PC` is loaded with either `CR` or `PC + 3`, the FSM compares `PC` against the 16-bit constant `0xFFFF`. The compare is bit-serial: clock `PC` through a chain of AND gates against the constant during a 16-cycle post-BR check. Implementation note: this can be fused into BR phase by feeding the PC output through an extra single-bit ANDtree without adding cycles. If `HALTED` is asserted, the FSM enters its terminal state and the global clock enable to PC is gated off.

◐ Programs that branch to `0xFFFF` for halt should ensure the branch target is reached *only* when halt is intended; using `0xFFFF` as a data address is undefined behaviour.

---

## 10. Programming model

### 10.1 Assembler syntax (Phase 2 deliverable)

Mercury Assembly (`.msq`) — each line is one Subleq instruction or a directive:

```
; comments after semicolon
@10              ; locate next instruction at address 10
loop: A B C      ; labelled instruction; A, B, C are word addresses or labels
.word 0x002A     ; raw data word at the current address
.org 0           ; explicit origin
```

The assembler (Phase 2) is a 200-line Rust program. Two-pass: first pass resolves labels, second emits 16-bit words to a flat memory image (`.mem`).

### 10.2 Canonical test program — `zero_b.msq`

✓ Subtracts B from itself once, halting:

```
.org 0
start: B B done       ; mem[B] ← mem[B] − mem[B] = 0; ≤0 → branch to done
done:  0 0 0xFFFF     ; halt sentinel branch
B:     .word 42
```

Expected trace after one instruction:
- `mem[B] = 0`
- `SIGN = 0`, `ZERO_OR = 0` ⇒ branch taken (0 ≤ 0)
- `PC ← done` (address of halt branch)
- Next instruction halts via `C = 0xFFFF`.

This is the Phase 2 / Phase 3 cross-conformance smoke test.

---

## 11. Conformance requirements

✓ Phase 2 (Rust) and Phase 3 (FPGA) must agree on:

1. **Memory image** after every instruction completes.
2. **PC value** after every instruction completes.
3. **HALTED flag** transitions.
4. **Ledger counters** (bit-transits, irreversible-bit-ops, peak live bits).
5. **Cycle count** for each program (must equal `128 × instructions_executed`).

✓ Test harness emits a `trace.jsonl` file: one JSON object per completed instruction, containing PC, AR, BR, CR, RES, SIGN, ZERO_OR, HALTED, and the running ledger totals. Diffing the two trace files between Phase 2 and Phase 3 is the conformance check.

---

## 12. Open questions deferred

| # | Question | Defer to |
|---|---|---|
| 1 | I/O semantics (mem-mapped at `0xFFFC`/`0xFFFD`) | Phase 4 |
| 2 | Reversible-logic Mercury variant for Lloyd envelope | Phase 6 (stretch) |
| 3 | Hand-coded vs higher-level compiler for `.msq` programs | Phase 2 follow-up |
| 4 | Whether to count read transits as irreversible | Phase 5 (literature pass) |
| 5 | True delay-line memory model (no random access) as a config flag | Phase 6 (stretch) |

---

## 13. References (in addition to PHYSICS.md)

1. Mavaddat, F. & Parhami, B. *URISC: The Ultimate Reduced Instruction Set Computer.* Int. J. Electrical Eng. Education **25** (1988). (Foundational OISC analysis.)
2. Mazonka, O. & Kolodin, A. *A simple multi-processor computer based on Subleq.* arXiv:1106.2593 (2011).
3. Bennett, C. H. *Logical reversibility of computation.* IBM J. Res. Dev. **17**, 525 (1973). (For Phase 6.)

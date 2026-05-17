# Mercury

A minimal bit-serial computer, designed and built to respect the physical
limits in Lloyd's *Ultimate Physical Limits to Computation* (Nature 2000) as
hard runtime constraints.

> Named after the mercury delay lines that served as the memory substrate of
> the first generation of serial computers (EDSAC, UNIVAC I, Pilot ACE).

## Status

| Phase | Deliverable | State |
|---|---|---|
| 0 | Physical envelope (Margolus–Levitin, Bekenstein, Landauer) | ✅ `PHYSICS.md`, `config.toml` |
| 1 | ISA and bit-serial datapath | ✅ `ARCH.md` |
| 2 | Rust functional model + compliance ledger | ✅ `crates/` |
| 3 | SystemVerilog RTL, conformance-checked vs. Rust | ✅ `hw/rtl/`, `hw/tb/tb_mercury.sv` |
| 3.5 | AWS F1 CL wrapper (AXI-Lite control plane + host loader) | ✅ `hw/aws_f1/`, `hw/tb/tb_cl_mercury.sv` |
| 4 | AWS Terraform IaC + GitHub Actions CI | ✅ `infra/`, `.github/workflows/` |
| 5 | SSRN/IEEE submission paper | ✅ `docs/paper/mercury.pdf` (5 pages) |

## What's here

```
mercury/
├── PHYSICS.md             — Phase 0: physical envelope, two configs
├── ARCH.md                — Phase 1: ISA, bit-serial datapath, FSM
├── config.toml            — runtime source of truth for both envelopes
├── programs/              — Mercury Assembly test programs
├── crates/                — Phase 2: Rust ledger, assembler, simulator
├── hw/
│   ├── rtl/               — Phase 3: SystemVerilog (pkg, mem, core, top)
│   ├── tb/                — testbenches (CPU-only, CL wrapper)
│   └── aws_f1/            — Phase 3.5: CL wrapper, host C, build scripts
├── infra/                 — Phase 4: Terraform + buildspec
├── .github/workflows/     — Phase 4: PR gate + manual synth trigger
├── docs/paper/            — Phase 5: IEEE-format paper (.tex + .pdf + SSRN packet)
└── scripts/
    ├── conformance.sh     — Phase 3 gate: Rust ↔ SV trace diff
    ├── cl_conformance.sh  — Phase 3.5 gate: host AXI-Lite end-to-end
    └── build_paper.sh     — Phase 5: regenerate figures + compile paper
```

## Quick start

```bash
cargo build --release

# Phase 2: run on the Rust simulator.
./target/release/mercury-run programs/zero_b.msq --envelope desktop
./target/release/mercury-run programs/zero_b.msq --envelope lloyd_limit

# Phase 3: SystemVerilog core ↔ Rust trace conformance.
./scripts/conformance.sh                              # zero_b.msq
./scripts/conformance.sh programs/countdown.msq

# Phase 3.5: full F1 CL wrapper exercised over a simulated AXI-Lite host.
./scripts/cl_conformance.sh                           # zero_b.msq
./scripts/cl_conformance.sh programs/countdown.msq
```

## Test

```bash
cargo test --release                                  # Rust suites (13 tests)
./scripts/conformance.sh    programs/zero_b.msq       # Phase 3 cross-impl
./scripts/conformance.sh    programs/countdown.msq    # Phase 3 cross-impl
./scripts/cl_conformance.sh programs/zero_b.msq       # Phase 3.5 wrapper
./scripts/cl_conformance.sh programs/countdown.msq    # Phase 3.5 wrapper
```

The three independent implementations (Rust simulator, iverilog CPU-only,
iverilog CL wrapper) all produce the same per-instruction outcomes on both
test programs. The conformance scripts are the merge gates for any future
RTL change.

## Key result, locked

For the canonical two-instruction `zero_b.msq` run:

| Metric | Desktop envelope | Lloyd-limit envelope |
|---|---|---|
| Total bit transits | 256 | 256 |
| Margolus–Levitin compliant | ✅ (1.8 × 10⁻⁴³ of ceiling) | ✅ (1.8 × 10⁻⁴³) |
| Bekenstein compliant | ✅ (4.1 × 10⁻³⁷ of cap) | ✅ (2.7 × 10⁻¹¹) |
| Landauer dissipation | 2.8 × 10⁻¹⁹ J | **1.1 × 10² J** |
| Landauer power @ 100 MHz | 1.1 × 10⁻¹³ W | **4.4 × 10⁷ W** |

The Lloyd-envelope dissipation (113 joules for *two* trivial instructions) is
the irreversibility tax of running classical bit operations at Hawking
temperature. It motivates the Phase 6 reversible-logic variant.

## Author

Aldrich K. Wooden, Sr.

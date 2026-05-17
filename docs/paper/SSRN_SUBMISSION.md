# SSRN submission packet — Mercury paper

This directory contains everything needed to submit the Mercury paper to
SSRN. Upload `mercury.pdf` as the primary file; paste the fields below
into the SSRN submission form.

## File checklist

| File | Use |
|---|---|
| `mercury.pdf` | Primary submission (upload this) |
| `mercury.tex` | LaTeX source — keep for revisions |
| `figs/landauer.{pdf,png}` | Figure 2 (results) |
| `figs/invariant.{pdf,png}` | Figure 1 (envelope-independent invariant) |

## SSRN form fields

### Title
```
Mercury: A Physically-Bounded Bit-Serial Computer — A Reproducible Bridge Between Lloyd's Ultimate Limits and Runnable Systems
```

### Author
Aldrich K. Wooden, Sr.
- Affiliation 1: Visionblox LLC
- Affiliation 2: Zuup Innovation Lab
- ORCID: 0009-0006-0006-6107

### Abstract (paste verbatim into SSRN's abstract field)

Lloyd's 2000 derivation of the ultimate physical limits to computation
quantifies how much computation a mass–energy budget can support, but does
not constrain any specific implementation. We close that gap with Mercury,
a minimal bit-serial Subleq computer designed so that the Margolus–Levitin,
Bekenstein, and Landauer bounds act as hard runtime constraints rather than
as aspirations. Mercury exposes a single configuration flag selecting
between a pragmatic 1 kg / 10 cm / 300 K envelope and the Lloyd-limit
envelope of the same 1 kg compressed to its Schwarzschild radius at Hawking
temperature. Execution under either envelope is bit-identical—only the
energy ledger changes. We implement Mercury three times (Rust functional
model with compliance ledger, SystemVerilog RTL under iverilog, and an AWS
F1 Custom Logic wrapper exercised over simulated AXI4-Lite) and verify
byte-equivalent per-instruction execution traces across all three. A
canonical 256-cycle program dissipates 2.76 × 10⁻¹⁹ J under the desktop
envelope and 1.13 × 10² J under the Lloyd envelope—a separation of 21
orders of magnitude that quantifies the irreversibility tax of classical
computing at the holographic storage limit. The ratio t_flip / t_cross =
π² / ln 2 is shown to be an envelope-independent invariant of the bounds
themselves, providing a first-principles justification for bit-serial
architecture at the physical-limit regime.

### Keywords

Bit-serial computing, Margolus–Levitin bound, Bekenstein bound, Landauer's
principle, holographic principle, Subleq, FPGA, AWS F1, reversible
computing, compliance verification.

### JEL / Subject classification (SSRN)

Primary network: Computer Science Research Network (CSRN)
Secondary networks:
- CompSci: Hardware & Architecture
- CompSci: Theory of Computing
- Physics & Mathematics: Physics

### Funding statement

Self-funded research conducted under the auspices of Zuup Innovation Lab
and Visionblox LLC.

### Conflict of interest

The author declares no competing financial interests.

### Data availability

All source code, configuration files, simulation outputs, and infrastructure
definitions are publicly available at https://github.com/khaaliswooden-max/mercury
under the Apache 2.0 license. All quantitative results in the paper can be
reproduced by running the workspace's conformance scripts on a Linux system
with Rust 1.95+ and Icarus Verilog 12 installed.

## Compilation

```bash
cd docs/paper
pdflatex mercury && pdflatex mercury     # two passes for cross-references
```

Requires `texlive-latex-recommended`, `texlive-publishers` (for IEEEtran),
`texlive-fonts-recommended`, and `texlive-latex-extra`.

## Reproducibility

Every quantitative claim in the paper has a corresponding file or script
in the public repository. The mapping:

| Paper claim | Source |
|---|---|
| Both physical envelopes, all constants | `PHYSICS.md`, `config.toml` |
| 128-cycle instruction budget | `ARCH.md` §6, `crates/mercury-sim/src/lib.rs` |
| Byte-equivalent traces, two programs | `scripts/conformance.sh`, `scripts/cl_conformance.sh` |
| Headline 21-OOM Landauer gap | `crates/mercury-sim/tests/conformance.rs::zero_b_compliance_passes_both_envelopes` |
| π² / ln 2 structural invariant | derivation in PHYSICS.md §6, figure `figs/invariant.pdf` |

A reviewer can clone the repository, run `cargo test --release` and
`./scripts/conformance.sh && ./scripts/cl_conformance.sh`, and reproduce
the numbers in roughly two minutes of wall time.

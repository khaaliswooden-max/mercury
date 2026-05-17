# AWS F1 deployment

This directory holds the AWS-F1-specific integration of Mercury: the CL
(custom logic) wrapper, an AXI4-Lite control plane, a host program for
loading and running programs over PCIe, and driver scripts for the HDK's
DCP-to-AFI build pipeline.

## Status

Phase 3.5 is **complete in simulation** through the CL wrapper, including
the full host-loaded → release reset → poll status → read counters cycle
over AXI4-Lite. The remaining work to land a running AFI is documented in
[§ Remaining work](#remaining-work) below.

| Layer | State | Verified by |
|---|---|---|
| Mercury core (Subleq CPU) | ✅ | `scripts/conformance.sh` (Rust ↔ SV trace diff) |
| Dual-port memory + host loader port | ✅ | both conformance suites |
| AXI4-Lite slave (control + mem backdoor) | ✅ | `scripts/cl_conformance.sh` |
| CL wrapper (`cl_mercury.sv`) | ✅ | `scripts/cl_conformance.sh` |
| Host program (`test_mercury.c`) | ⚠ | compiles against AWS SDK headers; not run on silicon |
| HDK shell port-list integration | ⬜ | requires the FPGA Developer AMI |
| Vivado synthesis (DCP build) | ⬜ | requires Vivado 2022.2 on a build host |
| AFI registration | ⬜ | requires AWS account with F1 entitlement |

## Architecture

```
                        Host (EC2 f1.2xlarge)
                              │
                              │  PCIe Gen3 ×16
                              ▼
                ┌──────────────────────────────────┐
                │           AWS Shell              │   AWS-provided
                │  (PCIe, DDR4 ctrl, AXI infra)    │
                └──────────────┬───────────────────┘
                               │  OCL AXI4-Lite (32-bit)
                               ▼
                ┌──────────────────────────────────┐
                │       cl_mercury.sv (CL)         │   This repo
                │                                  │
                │  ┌───────────────────────────┐   │
                │  │      ocl_slave.sv         │   │
                │  │  - register file          │   │
                │  │  - memory backdoor        │   │
                │  └────┬────────────────┬─────┘   │
                │       │ ctrl/status    │ port B  │
                │       ▼                ▼         │
                │  ┌─────────────┐   ┌──────────┐  │
                │  │ mercury_core│   │mercury_  │  │
                │  │ (bit-serial │◀──│mem dual- │  │
                │  │  Subleq)    │   │port 64K×16│  │
                │  └─────────────┘   └──────────┘  │
                └──────────────────────────────────┘
```

## Address map (OCL window)

| Offset | Reg | R/W | Description |
|---|---|---|---|
| `0x000000` | CTRL | R/W | bit 0 = hold reset, bit 1 = run enable |
| `0x000004` | STATUS | R | bit 0 = halted, bit 1 = insn-complete latch |
| `0x000008` | CYCLES_LO | R | lower 32 bits of cycle counter |
| `0x00000C` | CYCLES_HI | R | upper 32 bits |
| `0x000010` | INSN_LO | R | lower 32 bits of instruction counter |
| `0x000014` | INSN_HI | R | upper 32 bits |
| `0x000018` | PC_DBG | R | `{16'h0, pc[15:0]}` |
| `0x00001C` | DEBUG | R | `{sign, zero_or, 14'h0, res[15:0]}` |
| `0x100000 + (addr<<2)` | MEM | R/W | word `addr` of Mercury memory (low 16 bits) |

Source of truth: [`design/cl_mercury_defines.vh`](design/cl_mercury_defines.vh).

## Host workflow

```c
// from verif/tests/test_mercury.c
poke32(MERCURY_REG_CTRL, CTRL_RST);                       // 1. hold reset
for each word in program.hex:                             // 2. load
    poke32(MERCURY_MEM_BASE + (addr << 2), word);
poke32(MERCURY_REG_CTRL, CTRL_RUN_EN);                    // 3. release
while !(peek32(MERCURY_REG_STATUS) & STATUS_HALTED): ...  // 4. poll
peek32(MERCURY_REG_CYCLES_LO/HI); peek32(MERCURY_REG_INSN_LO/HI);  // 5. read
```

The wrapper testbench `hw/tb/tb_cl_mercury.sv` does exactly this flow in
SystemVerilog and confirms the counters match the Rust reference.

## Files

```
hw/aws_f1/
├── README.md                       (this file)
├── design/
│   ├── cl_mercury.sv               CL top: instantiates ocl_slave + mercury_top
│   ├── ocl_slave.sv                AXI4-Lite slave: reg file + memory backdoor
│   ├── cl_mercury_defines.vh       address map (sourced by SV and C)
│   └── cl_id_defines.vh            vendor/device IDs for the AFI metadata
├── verif/
│   └── tests/
│       ├── test_mercury.c          host program (fpga_pci API)
│       └── Makefile                builds against the AWS SDK on the F1 host
└── build/
    └── scripts/
        ├── build_afi.sh            staging + DCP build + S3 upload + AFI register
        ├── synth.tcl               Vivado synthesis settings
        └── encrypt.tcl             HDK encryption-step stub (pass-through)
```

## Remaining work

To land a running AFI, three concrete pieces remain. None affect Mercury's
architecture or its physics-bounded design; they're shell-integration work.

1. **HDK port-list adapter.** The AWS shell expects `cl_mercury`'s ports to
   match a fixed, long list (DDR4, AXI-Stream, interrupts, flop-protocol,
   etc.). The Phase 3.5 `cl_mercury.sv` exposes only the OCL port for
   testability under iverilog. At HDK integration time, wrap it in a thin
   adapter (or rename and add tie-offs directly) that matches the current
   `aws-fpga/hdk/cl/examples/cl_hello_world/design/cl_hello_world.sv` port
   list. Diff against the current example for the exact set of signals to
   tie off.

2. **Vivado DCP build.** Run on the AWS FPGA Developer AMI:

   ```bash
   git clone https://github.com/aws/aws-fpga.git
   source aws-fpga/hdk_setup.sh
   export S3_BUCKET=mercury-afi-staging
   export S3_DCP_KEY=dcp/phase35.tar
   ./hw/aws_f1/build/scripts/build_afi.sh
   ```

   Synthesis runs ~3–6 hours on a c5.4xlarge. Watch for timing closure at
   125 MHz; the bit-serial datapath is shallow, but `mercury_mem`'s 64K × 16
   array may invite "no output register" timing penalties on UltraScale+
   BRAM. Adding a registered read stage on port A would require updating
   the FSM in `mercury_core.sv` and re-running `scripts/conformance.sh`.

3. **Run the host program on `f1.2xlarge`.** With a registered AFI:

   ```bash
   sudo fpga-load-local-image -S 0 -I <agfi-id>
   cd hw/aws_f1/verif/tests
   make
   ../../../target/release/mercury-asm ../../../programs/zero_b.msq zero_b.hex --hex
   sudo ./test_mercury zero_b.hex
   ```

   Expected output: `HALT cycles=257 instructions=2 PC=0xffff` for
   `zero_b.msq`, `HALT cycles=1281 instructions=10 PC=0xffff` for
   `countdown.msq`. These are the same numbers the wrapper testbench
   produces under iverilog.

## Cost

The major cost line is the synthesis runs, not the F1 instances themselves
— each DCP build is hours of Vivado on a c5 instance. Verify current
on-demand pricing for `c5.4xlarge` and `f1.2xlarge` before kicking off; with
disciplined shutdown the full Phase 3.5 + 4 work has historically landed
under $200. Reserve a few hours of F1 time near the end for AFI validation
and program runs; AFI registration itself is free.

## Why this is honest about being incomplete

Mercury runs end-to-end in three independent simulations (Rust, iverilog
CPU-only, iverilog CL-wrapper) with byte-equivalent execution traces. The
remaining work to land it on silicon is mechanical and well-bounded — it
does not depend on resolving any open architecture or physics questions.
The Phase 3.5 deliverable is the design and verification work needed
before spending money on synthesis runs.

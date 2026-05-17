// mercury_pkg.sv — Mercury constants and types.
// Locked to ARCH.md §3, §6. Must be byte-equivalent with crates/mercury-sim.

`ifndef MERCURY_PKG_SV
`define MERCURY_PKG_SV

package mercury_pkg;

    // Word width — ARCH.md §3.
    localparam int W            = 16;
    // Cycles per phase (= W).
    localparam int PHASE_CYCLES = 16;
    // Cycles per instruction.
    localparam int INSN_CYCLES  = 128;
    // Halt sentinel — ARCH.md §2.2.
    localparam logic [15:0] HALT_ADDR = 16'hFFFF;

    // Phase enum order matches the Rust simulator's `Phase::next()`.
    typedef enum logic [2:0] {
        PH_F1 = 3'd0,
        PH_F2 = 3'd1,
        PH_F3 = 3'd2,
        PH_L1 = 3'd3,
        PH_L2 = 3'd4,
        PH_EX = 3'd5,
        PH_ST = 3'd6,
        PH_BR = 3'd7
    } phase_t;

endpackage

`endif

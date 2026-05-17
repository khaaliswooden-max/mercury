//! End-to-end conformance: assemble `zero_b.msq`, run on the simulator,
//! verify both functional outcome (mem[B] = 0, PC = HALT, instructions = 2)
//! and ledger counts match ARCH.md §6.2 / §7.2 exactly.

use mercury_ledger::{load_envelopes, EnvelopeName};
use mercury_sim::{Machine, HALT_ADDR, INSN_CYCLES};

const CONFIG_TOML: &str = include_str!("../../../config.toml");
const ZERO_B_MSQ: &str = include_str!("../../../programs/zero_b.msq");

#[test]
fn zero_b_program_executes_to_halt() {
    let (d, _) = load_envelopes(CONFIG_TOML).unwrap();
    let mut m = Machine::new(EnvelopeName::Desktop, d, 1.0e8);
    m.load_msq(ZERO_B_MSQ).expect("assembly should succeed");

    m.run(1000);

    assert!(m.halted, "machine should have halted");
    assert_eq!(m.pc, HALT_ADDR, "PC should be at halt sentinel");
    assert_eq!(m.instructions_executed, 2,
        "two instructions: subtract-to-zero, then halt branch");

    // Locate label B from the assembler so we don't hardcode the layout.
    let img = mercury_asm::assemble(ZERO_B_MSQ).unwrap();
    let b_addr = *img.labels.get("B").unwrap() as usize;
    assert_eq!(m.memory[b_addr], 0, "mem[B] should be 0 after subtract-self");
}

#[test]
fn zero_b_ledger_counts_match_arch_md() {
    let (d, _) = load_envelopes(CONFIG_TOML).unwrap();
    let mut m = Machine::new(EnvelopeName::Desktop, d, 1.0e8);
    m.load_msq(ZERO_B_MSQ).unwrap();
    m.run(1000);

    // 2 instructions × 128 cycles = 256 cycles total
    assert_eq!(m.ledger.cycles, 2 * INSN_CYCLES);

    // Per ARCH.md §7.2 — exact transit counts per instruction:
    //   80 reads + 16 adder ticks + 32 writes = 128 transits
    assert_eq!(m.ledger.read_transits, 2 * 80);
    assert_eq!(m.ledger.adder_ticks,   2 * 16);
    assert_eq!(m.ledger.write_transits, 2 * 32);
    assert_eq!(m.ledger.total_transits(), 2 * 128);
    assert_eq!(m.ledger.irreversible_ops(), 2 * 48);
}

#[test]
fn zero_b_compliance_passes_both_envelopes() {
    for env_name in [EnvelopeName::Desktop, EnvelopeName::LloydLimit] {
        let (d, l) = load_envelopes(CONFIG_TOML).unwrap();
        let env = if env_name == EnvelopeName::Desktop { d } else { l };
        let mut m = Machine::new(env_name, env, 1.0e8);
        m.load_msq(ZERO_B_MSQ).unwrap();
        m.run(1000);
        let r = m.ledger.report();
        assert!(r.ops_compliant, "ops/sec ceiling exceeded under {:?}", env_name);
        assert!(r.bekenstein_compliant, "Bekenstein cap exceeded under {:?}", env_name);
        // Sanity: Lloyd-envelope Landauer dissipation per instruction must be
        // many orders of magnitude larger than desktop, even though the
        // operation count is identical.
        if env_name == EnvelopeName::LloydLimit {
            assert!(r.landauer_energy_J > 1.0,
                "Lloyd-envelope Landauer cost should exceed 1 J for this run");
        } else {
            assert!(r.landauer_energy_J < 1e-15,
                "desktop Landauer cost should be sub-femtojoule");
        }
    }
}

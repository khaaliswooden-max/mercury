//! Mercury — bit-serial Subleq machine.
//!
//! Cycle-accurate functional model of the architecture in `ARCH.md`. Each
//! call to [`Machine::tick`] advances exactly one clock cycle and moves at
//! most one bit on the conceptual bit-bus. Phases run for exactly 16 cycles
//! each, in fixed order F1 → F2 → F3 → L1 → L2 → EX → ST → BR → F1 …, so
//! every instruction takes exactly 128 cycles. The bit pattern of execution
//! is the conformance contract for the Phase 3 FPGA implementation.

use mercury_ledger::{Envelope, EnvelopeName, Ledger};

/// Word width — locked at 16 bits per ARCH.md §3.
pub const W: u8 = 16;
/// Cycles per phase (= W).
pub const PHASE_CYCLES: u8 = 16;
/// Cycles per instruction (= 8 phases × 16).
pub const INSN_CYCLES: u64 = 128;
/// Halt sentinel branch target — ARCH.md §2.2.
pub const HALT_ADDR: u16 = 0xFFFF;
/// Total memory bits — used to set ledger live_bits.
pub const MEMORY_BITS: u64 = (W as u64) * 65536;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase { F1, F2, F3, L1, L2, EX, ST, BR }

impl Phase {
    fn next(self) -> Self {
        match self {
            Phase::F1 => Phase::F2,
            Phase::F2 => Phase::F3,
            Phase::F3 => Phase::L1,
            Phase::L1 => Phase::L2,
            Phase::L2 => Phase::EX,
            Phase::EX => Phase::ST,
            Phase::ST => Phase::BR,
            Phase::BR => Phase::F1,
        }
    }
}

/// All architectural state per ARCH.md §4.2 plus FSM and ledger.
pub struct Machine {
    // Registers
    pub pc: u16,
    pub ar: u16,
    pub br: u16,
    pub cr: u16,
    pub op1: u16,
    pub op2: u16,
    pub res: u16,
    pub c_in: bool,
    pub sign: bool,
    pub zero_or: bool,
    pub halted: bool,
    /// Word-organized memory; bit-bus interface is synthesized in `tick`.
    pub memory: Box<[u16; 65536]>,
    // FSM
    phase: Phase,
    cycle_in_phase: u8,
    // Latched at start of BR phase from EX results — the bit-streaming target for PC.
    pc_next: u16,
    // Compliance ledger
    pub ledger: Ledger,
    // Per-instruction counter (for trace/stats)
    pub instructions_executed: u64,
}

impl Machine {
    pub fn new(env_name: EnvelopeName, envelope: Envelope, clock_hz: f64) -> Self {
        let mut ledger = Ledger::new(env_name, envelope, clock_hz);
        ledger.set_live_bits(MEMORY_BITS);
        Self {
            pc: 0, ar: 0, br: 0, cr: 0,
            op1: 0, op2: 0, res: 0,
            c_in: false, sign: false, zero_or: false,
            halted: false,
            memory: Box::new([0u16; 65536]),
            phase: Phase::F1,
            cycle_in_phase: 0,
            pc_next: 0,
            ledger,
            instructions_executed: 0,
        }
    }

    pub fn load_image(&mut self, words: &[u16; 65536]) {
        *self.memory = *words;
    }

    /// Convenience: replace memory with the result of assembling `.msq` text.
    pub fn load_msq(&mut self, source: &str) -> Result<(), String> {
        let img = mercury_asm::assemble(source).map_err(|e| e.to_string())?;
        self.load_image(&img.words);
        Ok(())
    }

    /// One clock cycle. Moves at most one bit on the bit-bus.
    pub fn tick(&mut self) {
        if self.halted {
            return;
        }
        self.ledger.record_cycle();
        let i = self.cycle_in_phase as usize; // bit position 0..16, LSB-first

        match self.phase {
            Phase::F1 => {
                let bit = (self.memory[self.pc as usize] >> i) & 1;
                set_bit(&mut self.ar, i, bit != 0);
                self.ledger.record_read_transit();
            }
            Phase::F2 => {
                let addr = self.pc.wrapping_add(1) as usize;
                let bit = (self.memory[addr] >> i) & 1;
                set_bit(&mut self.br, i, bit != 0);
                self.ledger.record_read_transit();
            }
            Phase::F3 => {
                let addr = self.pc.wrapping_add(2) as usize;
                let bit = (self.memory[addr] >> i) & 1;
                set_bit(&mut self.cr, i, bit != 0);
                self.ledger.record_read_transit();
            }
            Phase::L1 => {
                let bit = (self.memory[self.ar as usize] >> i) & 1;
                set_bit(&mut self.op1, i, bit != 0);
                self.ledger.record_read_transit();
            }
            Phase::L2 => {
                let bit = (self.memory[self.br as usize] >> i) & 1;
                set_bit(&mut self.op2, i, bit != 0);
                self.ledger.record_read_transit();
            }
            Phase::EX => {
                // Initialize C_in and ZERO_OR at the start of EX.
                if i == 0 {
                    self.c_in = true;       // "+1" of two's complement subtract
                    self.zero_or = false;   // OR accumulator reset
                    self.sign = false;
                    self.res = 0;
                }
                // Bit-serial: RES = OP2 + ~OP1 + 1, LSB-first.
                let a = ((self.op2 >> i) & 1) != 0;
                let b_inv = ((self.op1 >> i) & 1) == 0; // inverted OP1 bit
                let s = a ^ b_inv ^ self.c_in;
                let c_out = (a && b_inv) || (self.c_in && (a ^ b_inv));
                set_bit(&mut self.res, i, s);
                self.c_in = c_out;
                self.sign = s;                   // final SIGN = MSB at i=15
                self.zero_or = self.zero_or || s;
                self.ledger.record_adder_tick();
            }
            Phase::ST => {
                let bit = ((self.res >> i) & 1) != 0;
                set_bit(&mut self.memory[self.br as usize], i, bit);
                self.ledger.record_write_transit();
            }
            Phase::BR => {
                // At cycle 0 of BR, latch the branch decision and compute the
                // 16-bit target. The bit-stream of pc_next into pc occupies
                // all 16 cycles so each cycle still corresponds to one bit
                // transit (BRANCH_TAKEN = SIGN ∨ ¬ZERO_OR).
                if i == 0 {
                    let take = self.sign || !self.zero_or;
                    self.pc_next = if take { self.cr } else { self.pc.wrapping_add(3) };
                }
                let bit = ((self.pc_next >> i) & 1) != 0;
                set_bit(&mut self.pc, i, bit);
                self.ledger.record_write_transit();
            }
        }

        // Advance FSM.
        self.cycle_in_phase += 1;
        if self.cycle_in_phase == PHASE_CYCLES {
            self.cycle_in_phase = 0;
            // End of phase: if BR just finished, instruction complete.
            if self.phase == Phase::BR {
                self.instructions_executed += 1;
                // Halt detection: branch landed on 0xFFFF.
                if self.pc == HALT_ADDR {
                    self.halted = true;
                }
            }
            self.phase = self.phase.next();
        }
    }

    /// Run exactly one Subleq instruction (128 cycles).
    pub fn step_instruction(&mut self) {
        let target = self.ledger.cycles + INSN_CYCLES;
        while !self.halted && self.ledger.cycles < target {
            self.tick();
        }
    }

    /// Run until halt or until `max_instructions` is reached.
    pub fn run(&mut self, max_instructions: u64) {
        let start = self.instructions_executed;
        while !self.halted && (self.instructions_executed - start) < max_instructions {
            self.step_instruction();
        }
    }

    pub fn snapshot(&self) -> Snapshot {
        Snapshot {
            pc: self.pc,
            ar: self.ar, br: self.br, cr: self.cr,
            op1: self.op1, op2: self.op2, res: self.res,
            sign: self.sign, zero_or: self.zero_or,
            halted: self.halted,
            cycles: self.ledger.cycles,
            instructions_executed: self.instructions_executed,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct Snapshot {
    pub pc: u16,
    pub ar: u16,
    pub br: u16,
    pub cr: u16,
    pub op1: u16,
    pub op2: u16,
    pub res: u16,
    pub sign: bool,
    pub zero_or: bool,
    pub halted: bool,
    pub cycles: u64,
    pub instructions_executed: u64,
}

#[inline]
fn set_bit(reg: &mut u16, i: usize, v: bool) {
    if v {
        *reg |= 1u16 << i;
    } else {
        *reg &= !(1u16 << i);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CONFIG_TOML: &str = include_str!("../../../config.toml");

    fn make_desktop_machine() -> Machine {
        let (d, _) = mercury_ledger::load_envelopes(CONFIG_TOML).unwrap();
        Machine::new(EnvelopeName::Desktop, d, 1.0e8)
    }

    #[test]
    fn subtract_correctness_small() {
        // Manually craft a memory image: at addr 0, instruction "A B C"
        // where mem[A]=5, mem[B]=12, expected mem[B] after = 12 - 5 = 7.
        let mut m = make_desktop_machine();
        // Layout:
        //   0: A_addr = 10
        //   1: B_addr = 11
        //   2: C_addr = 0xFFFF  (halt branch on result > 0)
        //   10: 5
        //   11: 12
        m.memory[0] = 10;
        m.memory[1] = 11;
        m.memory[2] = HALT_ADDR;
        m.memory[10] = 5;
        m.memory[11] = 12;

        m.step_instruction();
        assert_eq!(m.memory[11], 7);
        assert!(!m.halted);
        // result was +7, so branch should NOT be taken → PC = 3
        assert_eq!(m.pc, 3);
    }

    #[test]
    fn subtract_to_zero_branches() {
        // 12 - 12 = 0 ≤ 0 → branch to C
        let mut m = make_desktop_machine();
        m.memory[0] = 10;
        m.memory[1] = 10;            // A == B address → mem[B] -= mem[A] = 0
        m.memory[2] = 100;           // jump target on ≤0
        m.memory[10] = 12;
        m.step_instruction();
        assert_eq!(m.memory[10], 0);
        assert_eq!(m.pc, 100);
        assert!(m.zero_or == false); // result was exactly 0
        assert!(!m.sign);            // not negative
    }

    #[test]
    fn negative_result_branches() {
        // 3 - 10 = -7 ≤ 0 → branch
        let mut m = make_desktop_machine();
        m.memory[0] = 10;
        m.memory[1] = 11;
        m.memory[2] = 200;
        m.memory[10] = 10;
        m.memory[11] = 3;
        m.step_instruction();
        assert_eq!(m.memory[11] as i16, -7);
        assert!(m.sign);
        assert_eq!(m.pc, 200);
    }

    #[test]
    fn halt_sentinel() {
        let mut m = make_desktop_machine();
        // Force a branch to HALT_ADDR.
        m.memory[0] = 10;
        m.memory[1] = 10;            // result = 0 → branch
        m.memory[2] = HALT_ADDR;
        m.memory[10] = 5;
        m.run(100);
        assert!(m.halted);
        assert_eq!(m.pc, HALT_ADDR);
        assert_eq!(m.instructions_executed, 1);
    }

    #[test]
    fn cycle_count_exactly_128_per_insn() {
        let mut m = make_desktop_machine();
        m.memory[0] = 10;
        m.memory[1] = 11;
        m.memory[2] = HALT_ADDR;
        m.memory[10] = 1;
        m.memory[11] = 2;
        m.step_instruction();
        // Instruction completed before halt → exactly 128 cycles consumed.
        assert_eq!(m.ledger.cycles, INSN_CYCLES);
        assert_eq!(m.ledger.read_transits, 80);
        assert_eq!(m.ledger.adder_ticks, 16);
        assert_eq!(m.ledger.write_transits, 32);
        assert_eq!(m.ledger.irreversible_ops(), 48);
        assert_eq!(m.ledger.total_transits(), 128);
    }

    #[test]
    fn ledger_after_halt() {
        let mut m = make_desktop_machine();
        m.memory[0] = 10;
        m.memory[1] = 10;
        m.memory[2] = HALT_ADDR;
        m.memory[10] = 7;
        m.run(100);
        // One instruction executed, then halt latched.
        assert_eq!(m.instructions_executed, 1);
        let r = m.ledger.report();
        assert!(r.ops_compliant);
        assert!(r.bekenstein_compliant);
        assert_eq!(r.cycles, INSN_CYCLES);
        // Landauer for desktop is tiny but nonzero.
        assert!(r.landauer_energy_J > 0.0);
        assert!(r.landauer_energy_J < 1e-18);
    }
}

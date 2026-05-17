//! Mercury compliance ledger.
//!
//! Counts every bit transit during simulation and reports against the physical
//! envelopes defined in `PHYSICS.md` / `config.toml`. The ledger does not
//! enforce halts on its own — the simulator calls `record_*` methods per cycle
//! and reads `report()` at the end. Enforcement (halt on Bekenstein breach,
//! refuse-to-erase past Landauer budget) is a Phase 5 extension.

#![allow(non_snake_case)] // SI symbols (J, K) appear in identifiers by design.

use serde::Deserialize;

/// One of the two envelopes defined in `PHYSICS.md`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EnvelopeName {
    Desktop,
    LloydLimit,
}

impl EnvelopeName {
    pub fn as_str(&self) -> &'static str {
        match self {
            EnvelopeName::Desktop => "desktop",
            EnvelopeName::LloydLimit => "lloyd_limit",
        }
    }
}

/// Numerical envelope drawn from `config.toml`.
#[derive(Debug, Clone, Copy, Deserialize)]
pub struct Envelope {
    pub mass_kg: f64,
    pub radius_m: f64,
    pub temperature_K: f64,
    pub energy_J: f64,
    pub ops_per_s_ceiling: f64,
    pub bekenstein_bits: f64,
    pub landauer_J_per_bit: f64,
    pub light_crossing_s: f64,
    pub per_bit_flip_s: f64,
}

#[derive(Debug, Deserialize)]
struct ConfigToml {
    envelopes: Envelopes,
}

#[derive(Debug, Deserialize)]
struct Envelopes {
    desktop: Envelope,
    lloyd_limit: Envelope,
}

/// Load both envelopes from a TOML config string. Caller selects which one
/// to use by name when constructing the [`Ledger`].
pub fn load_envelopes(toml_text: &str) -> Result<(Envelope, Envelope), String> {
    let cfg: ConfigToml = toml::from_str(toml_text).map_err(|e| e.to_string())?;
    Ok((cfg.envelopes.desktop, cfg.envelopes.lloyd_limit))
}

/// Cycle-level ledger. Counters are u64 — at 100 MHz this overflows in ~5800
/// years of continuous simulation, which is well past project scope.
#[derive(Debug, Clone)]
pub struct Ledger {
    envelope_name: EnvelopeName,
    envelope: Envelope,
    /// Total clock cycles advanced (one per `tick`).
    pub cycles: u64,
    /// Bit transits that move data without overwriting prior state
    /// (memory → register reads in F1/F2/F3/L1/L2).
    pub read_transits: u64,
    /// Adder ticks during EX phase (also writes RES bits).
    pub adder_ticks: u64,
    /// Write transits to memory or PC (ST + BR phases).
    pub write_transits: u64,
    /// Static memory occupancy in bits — set by the simulator on construction.
    pub live_bits: u64,
    /// Target clock frequency (Hz) used to convert cycles → seconds when
    /// computing instantaneous ops/sec against the Margolus-Levitin ceiling.
    pub clock_hz: f64,
}

impl Ledger {
    pub fn new(envelope_name: EnvelopeName, envelope: Envelope, clock_hz: f64) -> Self {
        Self {
            envelope_name,
            envelope,
            cycles: 0,
            read_transits: 0,
            adder_ticks: 0,
            write_transits: 0,
            live_bits: 0,
            clock_hz,
        }
    }

    pub fn record_cycle(&mut self) {
        self.cycles += 1;
    }
    pub fn record_read_transit(&mut self) {
        self.read_transits += 1;
    }
    pub fn record_adder_tick(&mut self) {
        self.adder_ticks += 1;
    }
    pub fn record_write_transit(&mut self) {
        self.write_transits += 1;
    }
    pub fn set_live_bits(&mut self, bits: u64) {
        self.live_bits = bits;
    }

    /// Irreversible bit ops = every transit that overwrites prior state.
    /// RES writes during EX (one per adder tick) + memory writes (ST) +
    /// PC writes (BR). Read transits are conservatively treated as
    /// reversible-in-principle per ARCH.md §7.2.
    pub fn irreversible_ops(&self) -> u64 {
        self.adder_ticks + self.write_transits
    }

    pub fn total_transits(&self) -> u64 {
        self.read_transits + self.adder_ticks + self.write_transits
    }

    pub fn wall_time_s(&self) -> f64 {
        self.cycles as f64 / self.clock_hz
    }

    pub fn ops_per_second(&self) -> f64 {
        let t = self.wall_time_s();
        if t == 0.0 { 0.0 } else { self.total_transits() as f64 / t }
    }

    pub fn landauer_energy_J(&self) -> f64 {
        self.irreversible_ops() as f64 * self.envelope.landauer_J_per_bit
    }

    pub fn landauer_power_W(&self) -> f64 {
        let t = self.wall_time_s();
        if t == 0.0 { 0.0 } else { self.landauer_energy_J() / t }
    }

    pub fn report(&self) -> ComplianceReport {
        let ops_frac = self.ops_per_second() / self.envelope.ops_per_s_ceiling;
        let beken_frac = self.live_bits as f64 / self.envelope.bekenstein_bits;
        ComplianceReport {
            envelope_name: self.envelope_name,
            cycles: self.cycles,
            wall_time_s: self.wall_time_s(),
            read_transits: self.read_transits,
            adder_ticks: self.adder_ticks,
            write_transits: self.write_transits,
            total_transits: self.total_transits(),
            irreversible_ops: self.irreversible_ops(),
            ops_per_second: self.ops_per_second(),
            ops_ceiling: self.envelope.ops_per_s_ceiling,
            ops_fraction_of_ceiling: ops_frac,
            ops_compliant: ops_frac <= 1.0,
            live_bits: self.live_bits,
            bekenstein_cap: self.envelope.bekenstein_bits,
            bekenstein_fraction: beken_frac,
            bekenstein_compliant: beken_frac <= 1.0,
            landauer_energy_J: self.landauer_energy_J(),
            landauer_power_W: self.landauer_power_W(),
            landauer_J_per_bit: self.envelope.landauer_J_per_bit,
        }
    }
}

#[derive(Debug, Clone)]
pub struct ComplianceReport {
    pub envelope_name: EnvelopeName,
    pub cycles: u64,
    pub wall_time_s: f64,
    pub read_transits: u64,
    pub adder_ticks: u64,
    pub write_transits: u64,
    pub total_transits: u64,
    pub irreversible_ops: u64,
    pub ops_per_second: f64,
    pub ops_ceiling: f64,
    pub ops_fraction_of_ceiling: f64,
    pub ops_compliant: bool,
    pub live_bits: u64,
    pub bekenstein_cap: f64,
    pub bekenstein_fraction: f64,
    pub bekenstein_compliant: bool,
    pub landauer_energy_J: f64,
    pub landauer_power_W: f64,
    pub landauer_J_per_bit: f64,
}

impl ComplianceReport {
    pub fn render(&self) -> String {
        format!(
            "Mercury Compliance Report — envelope: {}\n\
             ────────────────────────────────────────────────────────────────\n\
             Execution\n\
               cycles                : {}\n\
               wall time (@ clock)   : {:.6e} s\n\
               read transits         : {}\n\
               adder ticks (EX)      : {}\n\
               write transits        : {}\n\
               total bit transits    : {}\n\
               irreversible bit ops  : {}\n\n\
             Margolus–Levitin\n\
               ops / s (actual)      : {:.6e}\n\
               ops / s (ceiling)     : {:.6e}\n\
               fraction of ceiling   : {:.6e}\n\
               compliant             : {}\n\n\
             Bekenstein\n\
               live bits             : {}\n\
               storage cap (bits)    : {:.6e}\n\
               fraction of cap       : {:.6e}\n\
               compliant             : {}\n\n\
             Landauer\n\
               J / erasure (envelope): {:.6e}\n\
               total dissipated (J)  : {:.6e}\n\
               dissipated power (W)  : {:.6e}\n",
            self.envelope_name.as_str(),
            self.cycles,
            self.wall_time_s,
            self.read_transits,
            self.adder_ticks,
            self.write_transits,
            self.total_transits,
            self.irreversible_ops,
            self.ops_per_second,
            self.ops_ceiling,
            self.ops_fraction_of_ceiling,
            self.ops_compliant,
            self.live_bits,
            self.bekenstein_cap,
            self.bekenstein_fraction,
            self.bekenstein_compliant,
            self.landauer_J_per_bit,
            self.landauer_energy_J,
            self.landauer_power_W,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_TOML: &str = include_str!("../../../config.toml");

    #[test]
    fn loads_both_envelopes() {
        let (d, l) = load_envelopes(TEST_TOML).unwrap();
        assert_eq!(d.mass_kg, 1.0);
        assert_eq!(d.radius_m, 0.10);
        assert!((d.energy_J - 8.987551787368177e16).abs() / d.energy_J < 1e-12);
        assert!(l.radius_m < 1e-26);
        assert!(l.temperature_K > 1e22);
    }

    #[test]
    fn ledger_basic_counts() {
        let (d, _) = load_envelopes(TEST_TOML).unwrap();
        let mut led = Ledger::new(EnvelopeName::Desktop, d, 1.0e8);
        for _ in 0..16 { led.record_read_transit(); led.record_cycle(); }
        for _ in 0..16 { led.record_adder_tick(); led.record_cycle(); }
        for _ in 0..16 { led.record_write_transit(); led.record_cycle(); }
        led.set_live_bits(1_048_576);

        let r = led.report();
        assert_eq!(r.read_transits, 16);
        assert_eq!(r.adder_ticks, 16);
        assert_eq!(r.write_transits, 16);
        assert_eq!(r.irreversible_ops, 32);
        assert_eq!(r.total_transits, 48);
        assert!(r.ops_compliant);
        assert!(r.bekenstein_compliant);
    }
}

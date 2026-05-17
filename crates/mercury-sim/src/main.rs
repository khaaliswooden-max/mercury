//! `mercury-run` — assemble a .msq file, execute on the Mercury simulator,
//! emit the compliance report, and optionally write a per-instruction trace
//! (JSONL) that can be diff'd against the SystemVerilog testbench trace.

use mercury_ledger::{load_envelopes, EnvelopeName};
use mercury_sim::Machine;
use std::io::Write;
use std::path::PathBuf;

const DEFAULT_CONFIG_TOML: &str = include_str!("../../../config.toml");

fn print_usage() {
    eprintln!(
        "usage: mercury-run <program.msq> [--envelope desktop|lloyd_limit] [--clock-hz <hz>] \\\n\
         \t[--max-insn <n>] [--config <config.toml>] [--trace <path>]\n\n\
         Default envelope: desktop\n\
         Default clock:    1e8 Hz (100 MHz)\n\
         Default max-insn: 1_000_000"
    );
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 || args.iter().any(|a| a == "-h" || a == "--help") {
        print_usage();
        std::process::exit(if args.len() < 2 { 2 } else { 0 });
    }

    let program_path = PathBuf::from(&args[1]);
    let mut envelope_str = "desktop".to_string();
    let mut clock_hz: f64 = 1.0e8;
    let mut max_insn: u64 = 1_000_000;
    let mut config_path: Option<PathBuf> = None;
    let mut trace_path: Option<PathBuf> = None;

    let mut i = 2;
    while i < args.len() {
        match args[i].as_str() {
            "--envelope" => { envelope_str = args[i + 1].clone(); i += 2; }
            "--clock-hz" => { clock_hz = args[i + 1].parse().unwrap_or(1.0e8); i += 2; }
            "--max-insn" => { max_insn = args[i + 1].parse().unwrap_or(1_000_000); i += 2; }
            "--config"   => { config_path = Some(PathBuf::from(&args[i + 1])); i += 2; }
            "--trace"    => { trace_path  = Some(PathBuf::from(&args[i + 1])); i += 2; }
            other => { eprintln!("unknown arg: {}", other); print_usage(); std::process::exit(2); }
        }
    }

    let env_name = match envelope_str.as_str() {
        "desktop" => EnvelopeName::Desktop,
        "lloyd_limit" => EnvelopeName::LloydLimit,
        other => { eprintln!("unknown envelope: {}", other); std::process::exit(2); }
    };

    let config_text: String = match config_path {
        Some(p) => std::fs::read_to_string(&p).unwrap_or_else(|e| {
            eprintln!("read {}: {}", p.display(), e); std::process::exit(1);
        }),
        None => DEFAULT_CONFIG_TOML.to_string(),
    };

    let (desktop, lloyd) = load_envelopes(&config_text).unwrap_or_else(|e| {
        eprintln!("config load error: {}", e); std::process::exit(1);
    });
    let envelope = if env_name == EnvelopeName::Desktop { desktop } else { lloyd };

    let source = std::fs::read_to_string(&program_path).unwrap_or_else(|e| {
        eprintln!("read {}: {}", program_path.display(), e); std::process::exit(1);
    });

    let mut m = Machine::new(env_name, envelope, clock_hz);
    m.load_msq(&source).unwrap_or_else(|e| {
        eprintln!("assembly error: {}", e); std::process::exit(1);
    });

    let mut trace_file = trace_path.as_ref().map(|p| {
        std::fs::File::create(p).unwrap_or_else(|e| {
            eprintln!("create trace {}: {}", p.display(), e); std::process::exit(1);
        })
    });

    let mut executed: u64 = 0;
    while !m.halted && executed < max_insn {
        m.step_instruction();
        executed += 1;
        if let Some(f) = trace_file.as_mut() {
            let s = m.snapshot();
            // Schema must match tb_mercury.sv $fwrite line-for-line.
            writeln!(
                f,
                "{{\"insn\":{},\"cycles\":{},\"pc\":{},\"ar\":{},\"br\":{},\"cr\":{},\"res\":{},\"sign\":{},\"zero_or\":{},\"halted\":{}}}",
                s.instructions_executed,
                s.cycles,
                s.pc,
                s.ar,
                s.br,
                s.cr,
                s.res,
                s.sign as u8,
                s.zero_or as u8,
                s.halted as u8
            ).expect("trace write");
        }
    }

    let report = m.ledger.report();
    println!("{}", report.render());
    println!("Program state at exit:");
    let s = m.snapshot();
    println!("  PC                    : 0x{:04X}", s.pc);
    println!("  HALTED                : {}", s.halted);
    println!("  Instructions executed : {}", s.instructions_executed);
}

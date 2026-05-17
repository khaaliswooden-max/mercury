use mercury_asm::assemble;
use std::io::Write;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let usage = "usage: mercury-asm <input.msq> <output> [--hex]\n\
                 Without --hex: little-endian binary, 16-bit words.\n\
                 With    --hex: one 4-digit hex value per line for $readmemh.";
    if args.len() < 3 {
        eprintln!("{}", usage);
        std::process::exit(2);
    }
    let want_hex = args.iter().any(|a| a == "--hex");
    let src = match std::fs::read_to_string(&args[1]) {
        Ok(s) => s,
        Err(e) => { eprintln!("read {}: {}", args[1], e); std::process::exit(1); }
    };
    let img = match assemble(&src) {
        Ok(i) => i,
        Err(e) => { eprintln!("assembly error: {}", e); std::process::exit(1); }
    };
    let mut out = match std::fs::File::create(&args[2]) {
        Ok(f) => f,
        Err(e) => { eprintln!("create {}: {}", args[2], e); std::process::exit(1); }
    };
    if want_hex {
        let mut s = String::new();
        for w in img.words.iter() {
            s.push_str(&format!("{:04x}\n", w));
        }
        if let Err(e) = out.write_all(s.as_bytes()) {
            eprintln!("write: {}", e); std::process::exit(1);
        }
    } else {
        let mut buf = Vec::with_capacity(65536 * 2);
        for w in img.words.iter() {
            buf.extend_from_slice(&w.to_le_bytes());
        }
        if let Err(e) = out.write_all(&buf) {
            eprintln!("write: {}", e); std::process::exit(1);
        }
    }
    let _ = std::io::stdout().flush();
    eprintln!("assembled {} words used, {} labels", img.used_extent, img.labels.len());
}

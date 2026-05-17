//! Mercury Assembly (`.msq`) — two-pass assembler.
//!
//! Grammar (per ARCH.md §10.1):
//!
//! ```text
//!     ; comment to end of line
//!     @<addr>          -- locate next instruction at <addr>
//!     .org <addr>      -- same as @<addr>
//!     .word <imm>      -- raw 16-bit word at current address
//!     label:           -- labels current address
//!     A B C            -- Subleq instruction (three space-separated operands)
//! ```
//!
//! Operands can be: decimal int, `0x` hex int, `'c'` char (its u16 value),
//! a label name, or `here` (current address). Labels resolve in pass 2.
//!
//! The output is a flat `[u16; 65536]` memory image. Untouched cells are 0.

use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct AssembledImage {
    pub words: Box<[u16; 65536]>,
    pub labels: HashMap<String, u16>,
    pub used_extent: u16,
}

#[derive(Debug)]
pub struct AsmError {
    pub line: usize,
    pub msg: String,
}

impl std::fmt::Display for AsmError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "line {}: {}", self.line, self.msg)
    }
}

impl std::error::Error for AsmError {}

#[derive(Debug, Clone)]
enum LineKind {
    Empty,
    Org(u16),
    Word(Token),
    Insn(Token, Token, Token),
}

#[derive(Debug, Clone)]
enum Token {
    Imm(u16),
    Label(String),
}

fn parse_imm(s: &str) -> Option<u16> {
    let s = s.trim();
    if let Some(rest) = s.strip_prefix("0x").or_else(|| s.strip_prefix("0X")) {
        return u16::from_str_radix(rest, 16).ok();
    }
    if let Some(rest) = s.strip_prefix('-') {
        return rest.parse::<i32>().ok().and_then(|n| {
            let n = -n;
            if n >= i16::MIN as i32 && n <= i16::MAX as i32 {
                Some(n as i16 as u16)
            } else { None }
        });
    }
    if s.starts_with('\'') && s.ends_with('\'') && s.len() >= 3 {
        let inner = &s[1..s.len() - 1];
        if inner.chars().count() == 1 {
            return Some(inner.chars().next().unwrap() as u16);
        }
    }
    s.parse::<i32>().ok().and_then(|n| {
        if n >= 0 && n <= u16::MAX as i32 { Some(n as u16) }
        else if n >= i16::MIN as i32 && n <= -1 { Some(n as i16 as u16) }
        else { None }
    })
}

fn parse_token(s: &str) -> Token {
    if let Some(n) = parse_imm(s) {
        Token::Imm(n)
    } else {
        Token::Label(s.to_string())
    }
}

fn strip_comment(line: &str) -> &str {
    match line.find(';') {
        Some(i) => &line[..i],
        None => line,
    }
}

pub fn assemble(source: &str) -> Result<AssembledImage, AsmError> {
    // Pass 1: parse lines, collect labels with their addresses.
    let mut parsed: Vec<(usize, LineKind)> = Vec::new();
    let mut labels: HashMap<String, u16> = HashMap::new();
    let mut cursor: u32 = 0;

    for (idx, raw) in source.lines().enumerate() {
        let lineno = idx + 1;
        let line = strip_comment(raw).trim();
        if line.is_empty() {
            parsed.push((lineno, LineKind::Empty));
            continue;
        }

        // labels: any leading "name:" prefixes
        let mut rest = line.to_string();
        loop {
            if let Some(colon) = rest.find(':') {
                let name = rest[..colon].trim();
                let after = rest[colon + 1..].trim().to_string();
                if name.is_empty() || name.contains(char::is_whitespace) {
                    return Err(AsmError {
                        line: lineno,
                        msg: format!("invalid label name `{}`", name),
                    });
                }
                if cursor > u16::MAX as u32 {
                    return Err(AsmError {
                        line: lineno,
                        msg: "address overflow past 0xFFFF".into(),
                    });
                }
                if labels.insert(name.to_string(), cursor as u16).is_some() {
                    return Err(AsmError {
                        line: lineno,
                        msg: format!("duplicate label `{}`", name),
                    });
                }
                rest = after;
                if rest.is_empty() { break; }
            } else {
                break;
            }
        }
        if rest.is_empty() {
            parsed.push((lineno, LineKind::Empty));
            continue;
        }

        // directives
        if let Some(arg) = rest.strip_prefix('@') {
            let n = parse_imm(arg.trim()).ok_or_else(|| AsmError {
                line: lineno,
                msg: format!("bad @ address `{}`", arg),
            })?;
            cursor = n as u32;
            parsed.push((lineno, LineKind::Org(n)));
            continue;
        }
        if let Some(arg) = rest.strip_prefix(".org") {
            let n = parse_imm(arg.trim()).ok_or_else(|| AsmError {
                line: lineno,
                msg: format!("bad .org address `{}`", arg),
            })?;
            cursor = n as u32;
            parsed.push((lineno, LineKind::Org(n)));
            continue;
        }
        if let Some(arg) = rest.strip_prefix(".word") {
            let tok = parse_token(arg.trim());
            parsed.push((lineno, LineKind::Word(tok)));
            cursor += 1;
            continue;
        }

        // otherwise: three-operand subleq
        let parts: Vec<&str> = rest.split_whitespace().collect();
        if parts.len() != 3 {
            return Err(AsmError {
                line: lineno,
                msg: format!("expected 3 operands, got {}: `{}`", parts.len(), rest),
            });
        }
        parsed.push((
            lineno,
            LineKind::Insn(parse_token(parts[0]), parse_token(parts[1]), parse_token(parts[2])),
        ));
        cursor += 3;
    }

    // Pass 2: emit. Resolve label tokens.
    let mut words = Box::new([0u16; 65536]);
    let mut cursor: u32 = 0;
    let mut max_cursor: u32 = 0;

    fn resolve(
        tok: &Token,
        lineno: usize,
        cursor: u32,
        labels: &HashMap<String, u16>,
    ) -> Result<u16, AsmError> {
        match tok {
            Token::Imm(n) => Ok(*n),
            Token::Label(name) => {
                if name == "here" {
                    Ok(cursor as u16)
                } else {
                    labels.get(name).copied().ok_or_else(|| AsmError {
                        line: lineno,
                        msg: format!("undefined label `{}`", name),
                    })
                }
            }
        }
    }

    for (lineno, kind) in &parsed {
        match kind {
            LineKind::Empty => {}
            LineKind::Org(n) => { cursor = *n as u32; }
            LineKind::Word(tok) => {
                let v = resolve(tok, *lineno, cursor, &labels)?;
                if cursor > u16::MAX as u32 {
                    return Err(AsmError { line: *lineno, msg: "address overflow".into() });
                }
                words[cursor as usize] = v;
                cursor += 1;
                if cursor > max_cursor { max_cursor = cursor; }
            }
            LineKind::Insn(a, b, c) => {
                let va = resolve(a, *lineno, cursor, &labels)?;
                let vb = resolve(b, *lineno, cursor, &labels)?;
                let vc = resolve(c, *lineno, cursor, &labels)?;
                if cursor + 3 > 65536 {
                    return Err(AsmError { line: *lineno, msg: "address overflow".into() });
                }
                words[cursor as usize] = va;
                words[cursor as usize + 1] = vb;
                words[cursor as usize + 2] = vc;
                cursor += 3;
                if cursor > max_cursor { max_cursor = cursor; }
            }
        }
    }

    let used_extent = max_cursor.min(65536) as u16;

    Ok(AssembledImage { words, labels, used_extent })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_b_assembles() {
        let src = "
            .org 0
            start: B B done
            done:  0 0 0xFFFF
            B:     .word 42
        ";
        let img = assemble(src).unwrap();
        // Instruction at 0: B B done
        let b_addr = *img.labels.get("B").unwrap();
        let done_addr = *img.labels.get("done").unwrap();
        assert_eq!(img.words[0], b_addr);
        assert_eq!(img.words[1], b_addr);
        assert_eq!(img.words[2], done_addr);
        // Halt branch at done: 0 0 0xFFFF
        assert_eq!(img.words[done_addr as usize + 2], 0xFFFF);
        // Data word at B
        assert_eq!(img.words[b_addr as usize], 42);
    }

    #[test]
    fn negative_imm() {
        let src = ".word -1";
        let img = assemble(src).unwrap();
        assert_eq!(img.words[0], 0xFFFF);
    }
}

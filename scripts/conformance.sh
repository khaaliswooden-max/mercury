#!/usr/bin/env bash
# scripts/conformance.sh — Phase 3 cross-implementation check.
#
# Builds the Rust simulator and the iverilog testbench, runs both on the
# same Mercury program, and diffs their per-instruction JSONL traces.
#
# Usage:  ./scripts/conformance.sh [program.msq]
# Default program: programs/zero_b.msq

set -euo pipefail
cd "$(dirname "$0")/.."

PROG="${1:-programs/zero_b.msq}"
[ -f "$PROG" ] || { echo "no such program: $PROG"; exit 1; }
BASE="$(basename "$PROG" .msq)"

mkdir -p build

echo "═══ 1. cargo build --release"
. "$HOME/.cargo/env"
cargo build --release --quiet

echo "═══ 2. assemble ${PROG} → build/${BASE}.hex"
./target/release/mercury-asm "$PROG" "build/${BASE}.hex" --hex

echo "═══ 3. rust simulator trace → build/${BASE}.rust.jsonl"
./target/release/mercury-run "$PROG" \
    --envelope desktop \
    --trace "build/${BASE}.rust.jsonl" \
    > "build/${BASE}.rust.report.txt"

echo "═══ 4. compile iverilog testbench"
iverilog -g2012 -Wall -I hw/rtl -o "build/${BASE}.vvp" \
    hw/rtl/mercury_pkg.sv \
    hw/rtl/mercury_mem.sv \
    hw/rtl/mercury_core.sv \
    hw/rtl/mercury_top.sv \
    hw/tb/tb_mercury.sv

echo "═══ 5. run iverilog testbench → build/${BASE}.sv.jsonl"
vvp "build/${BASE}.vvp" \
    +hex="build/${BASE}.hex" \
    +trace="build/${BASE}.sv.jsonl" \
    +cycles=1000000 \
    | tee "build/${BASE}.sv.report.txt"

echo "═══ 6. diff traces"
if diff -u "build/${BASE}.rust.jsonl" "build/${BASE}.sv.jsonl"; then
    rust_lines=$(wc -l < "build/${BASE}.rust.jsonl")
    sv_lines=$(wc -l   < "build/${BASE}.sv.jsonl")
    echo ""
    echo "✅ CONFORMANCE PASS"
    echo "   rust trace: $rust_lines instructions"
    echo "   sv   trace: $sv_lines instructions"
    echo "   per-instruction state byte-equivalent"
    exit 0
else
    echo ""
    echo "❌ CONFORMANCE FAIL — traces diverge"
    exit 1
fi

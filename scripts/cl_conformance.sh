#!/usr/bin/env bash
# scripts/cl_conformance.sh — Phase 3.5 wrapper-level conformance.
#
# Builds the CL wrapper + AXI-Lite slave, simulates the host's view by
# driving OCL transactions, and verifies the program runs to halt with
# correct counters. Cycle counts are NOT expected to match
# scripts/conformance.sh (the OCL slave adds latency before reset release),
# but the program semantics (final memory state, halt PC, instructions
# executed) must match.
#
# Usage: ./scripts/cl_conformance.sh [program.msq]
# Default: programs/zero_b.msq

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

echo "═══ 3. expected instructions from Rust simulator"
EXPECTED_INSN=$(./target/release/mercury-run "$PROG" --envelope desktop \
    | awk -F: '/Instructions executed/ {gsub(/ /,"",$2); print $2}')
echo "   expected: ${EXPECTED_INSN} instructions"

echo "═══ 4. compile CL wrapper testbench"
iverilog -g2012 -Wall -I hw/rtl -I hw/aws_f1/design -o "build/${BASE}.cl.vvp" \
    hw/rtl/mercury_pkg.sv \
    hw/rtl/mercury_mem.sv \
    hw/rtl/mercury_core.sv \
    hw/rtl/mercury_top.sv \
    hw/aws_f1/design/ocl_slave.sv \
    hw/aws_f1/design/cl_mercury.sv \
    hw/tb/tb_cl_mercury.sv

echo "═══ 5. run CL testbench → build/${BASE}.cl.log"
vvp "build/${BASE}.cl.vvp" +hex="build/${BASE}.hex" \
    | tee "build/${BASE}.cl.log"

echo "═══ 6. verify"
ACTUAL_INSN=$(awk '/HOST: insns/ {print $4}' "build/${BASE}.cl.log")
ACTUAL_PC=$(awk '/HOST: PC/ {print $4}' "build/${BASE}.cl.log")

if [ "$ACTUAL_INSN" = "$EXPECTED_INSN" ] && [ "$ACTUAL_PC" = "0xffff" ]; then
    echo ""
    echo "✅ CL CONFORMANCE PASS"
    echo "   instructions executed : ${ACTUAL_INSN} (expected ${EXPECTED_INSN})"
    echo "   final PC              : ${ACTUAL_PC}"
    exit 0
else
    echo ""
    echo "❌ CL CONFORMANCE FAIL"
    echo "   expected: insns=${EXPECTED_INSN}, pc=0xffff"
    echo "   actual:   insns=${ACTUAL_INSN}, pc=${ACTUAL_PC}"
    exit 1
fi

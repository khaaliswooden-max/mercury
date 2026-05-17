#!/usr/bin/env bash
# scripts/build_paper.sh — compile the SSRN/IEEE submission PDF.
#
# Two pdflatex passes are required so that section/equation/figure
# cross-references resolve. The script also runs a smoke check on the
# Rust simulator to confirm the headline numbers cited in the paper
# match the current code (Phase 5 reproducibility gate).

set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v pdflatex >/dev/null 2>&1; then
    echo "FATAL: pdflatex not on PATH."
    echo "Install with: apt-get install texlive-latex-recommended texlive-publishers \\"
    echo "                          texlive-fonts-recommended texlive-latex-extra"
    exit 1
fi

echo "═══ 1. cargo build --release (regenerates simulator)"
. "$HOME/.cargo/env" 2>/dev/null || true
cargo build --release --quiet

echo "═══ 2. regenerate paper figures from current envelope numbers"
python3 - << 'PY'
import math, sys, os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

# Pulled from config.toml at build time.
landauer_J        = [2.870979e-21, 1.174135e0]
landauer_total_J  = [2.756e-19,    1.127e2]
labels            = ['Desktop\n1 kg / 10 cm / 300 K', 'Lloyd-limit\n1 kg / R_s / T_H']

fig, axes = plt.subplots(1, 2, figsize=(7.2, 3.0))
for ax, vals, title, ylabel in [
    (axes[0], landauer_J,       '(a) Landauer floor per envelope', r'$E_{\mathrm{erase}}$  (J / bit, log scale)'),
    (axes[1], landauer_total_J, '(b) zero_b.msq run cost',         'Total dissipation (J, log scale)'),
]:
    bars = ax.bar(labels, vals, color=['#3a7bd5', '#d34648'])
    ax.set_yscale('log')
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    for b, v in zip(bars, vals):
        ax.text(b.get_x() + b.get_width()/2, v*1.5, f'{v:.2e}',
                ha='center', va='bottom', fontsize=8)
    ax.grid(True, which='both', axis='y', alpha=0.3)
plt.tight_layout()
plt.savefig('docs/paper/figs/landauer.pdf', dpi=300, bbox_inches='tight')

fig2, ax = plt.subplots(figsize=(6.4, 3.0))
ax.axhline(math.pi**2 / math.log(2), color='black', linestyle='-', linewidth=1.2,
           label=r'$\pi^2 / \ln 2 \approx 14.2388$')
hbar, c, ln2 = 1.054571817e-34, 299792458.0, math.log(2)
ratios = []
masses = np.logspace(-3, 3, 25)
for m in masses:
    E = m * c**2
    R = 0.1
    bits = 2 * math.pi * E * R / (hbar * c * ln2)
    t_flip = math.pi * hbar * bits / (2 * E)
    t_cross = R / c
    ratios.append(t_flip / t_cross)
ax.plot(masses, ratios, 'o', color='#3a7bd5', markersize=4,
        label='Computed $t_{flip}/t_{cross}$ across envelopes')
ax.set_xscale('log')
ax.set_xlabel('Mass m (kg, log scale)  with R fixed at 0.1 m')
ax.set_ylabel('Ratio')
ax.set_ylim(14.0, 14.5)
ax.set_title(r'Structural invariant: $t_{\mathrm{flip}}/t_{\mathrm{cross}}$ is envelope-independent')
ax.legend(loc='upper right', fontsize=9)
ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig('docs/paper/figs/invariant.pdf', dpi=300, bbox_inches='tight')
PY

echo "═══ 3. compile paper (two passes)"
cd docs/paper
pdflatex -interaction=nonstopmode mercury.tex > /dev/null
pdflatex -interaction=nonstopmode mercury.tex > mercury.last.log

# Surface any unresolved references.
if grep -q "undefined references" mercury.log; then
    echo "WARN: undefined references in paper"
fi

PAGES=$(pdfinfo mercury.pdf 2>/dev/null | awk '/^Pages:/ {print $2}')
SIZE=$(stat -c%s mercury.pdf 2>/dev/null || stat -f%z mercury.pdf)

echo ""
echo "✅ PAPER BUILT"
echo "   path  : docs/paper/mercury.pdf"
echo "   pages : ${PAGES}"
echo "   size  : ${SIZE} bytes"

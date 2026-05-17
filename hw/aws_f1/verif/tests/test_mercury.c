// test_mercury.c — host program for running Mercury on AWS F1.
//
// Builds against the AWS FPGA SDK on the F1 instance:
//   gcc -I$SDK_DIR/userspace/include test_mercury.c \
//       -lfpga_mgmt -lpci -o test_mercury
//
// Usage:
//   sudo ./test_mercury <program.hex> [<slot>]
//
// Where <program.hex> is the file produced by `mercury-asm --hex` and
// <slot> defaults to 0. The program loads the binary into FPGA memory over
// the OCL BAR, releases CPU reset, polls until halt, and prints the cycle
// and instruction counters reported by the CL.
//
// This file follows the public fpga_pci API documented in the aws-fpga
// repository. It has not been validated against silicon; review against
// the current SDK headers before deployment.

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

#include <fpga_pci.h>
#include <fpga_mgmt.h>
#include <utils/lcd.h>

// Address map — must match hw/aws_f1/design/cl_mercury_defines.vh.
#define MERCURY_REG_CTRL       0x00000000U
#define MERCURY_REG_STATUS     0x00000004U
#define MERCURY_REG_CYCLES_LO  0x00000008U
#define MERCURY_REG_CYCLES_HI  0x0000000CU
#define MERCURY_REG_INSN_LO    0x00000010U
#define MERCURY_REG_INSN_HI    0x00000014U
#define MERCURY_REG_PC_DBG     0x00000018U
#define MERCURY_REG_DEBUG      0x0000001CU
#define MERCURY_MEM_BASE       0x00100000U

#define CTRL_RST               (1U << 0)
#define CTRL_RUN_EN            (1U << 1)
#define STATUS_HALTED          (1U << 0)

#define POLL_INTERVAL_US       1000
#define POLL_TIMEOUT_S         30

static int poke32(pci_bar_handle_t h, uint32_t off, uint32_t val) {
    int rc = fpga_pci_poke(h, off, val);
    if (rc) fprintf(stderr, "poke @%08x failed: %d\n", off, rc);
    return rc;
}

static int peek32(pci_bar_handle_t h, uint32_t off, uint32_t *val) {
    int rc = fpga_pci_peek(h, off, val);
    if (rc) fprintf(stderr, "peek @%08x failed: %d\n", off, rc);
    return rc;
}

static int load_program(pci_bar_handle_t h, const char *path, int *out_words) {
    FILE *f = fopen(path, "r");
    if (!f) { perror(path); return -1; }
    char line[64];
    int  written = 0;
    uint16_t addr = 0;
    while (fgets(line, sizeof line, f)) {
        unsigned int v;
        if (sscanf(line, "%x", &v) == 1) {
            if (v != 0) {
                if (poke32(h, MERCURY_MEM_BASE + (addr * 4), v & 0xFFFF) != 0) {
                    fclose(f);
                    return -1;
                }
                written++;
            }
            addr++;
            if (addr == 0) break;       // overflow past 64K
        }
    }
    fclose(f);
    if (out_words) *out_words = written;
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2 || argc > 3) {
        fprintf(stderr, "usage: %s <program.hex> [<slot>]\n", argv[0]);
        return 2;
    }
    const char *hex_path = argv[1];
    int slot = (argc == 3) ? atoi(argv[2]) : 0;

    int rc = fpga_mgmt_init();
    if (rc) { fprintf(stderr, "fpga_mgmt_init: %d\n", rc); return 1; }

    pci_bar_handle_t h = PCI_BAR_HANDLE_INIT;
    rc = fpga_pci_attach(slot, FPGA_APP_PF, APP_PF_BAR0, 0, &h);
    if (rc) { fprintf(stderr, "fpga_pci_attach: %d\n", rc); return 1; }

    // 1. Hold CPU in reset.
    if (poke32(h, MERCURY_REG_CTRL, CTRL_RST)) goto err;

    // 2. Load program.
    int loaded = 0;
    if (load_program(h, hex_path, &loaded)) goto err;
    printf("[host] loaded %d nonzero words from %s\n", loaded, hex_path);

    // 3. Release reset, enable run.
    if (poke32(h, MERCURY_REG_CTRL, CTRL_RUN_EN)) goto err;

    // 4. Poll status for halted.
    uint32_t status = 0;
    int iterations = (POLL_TIMEOUT_S * 1000000) / POLL_INTERVAL_US;
    int done = 0;
    for (int i = 0; i < iterations && !done; i++) {
        if (peek32(h, MERCURY_REG_STATUS, &status)) goto err;
        if (status & STATUS_HALTED) { done = 1; break; }
        usleep(POLL_INTERVAL_US);
    }
    if (!done) {
        fprintf(stderr, "[host] TIMEOUT after %d s (status=0x%x)\n",
                POLL_TIMEOUT_S, status);
        goto err;
    }

    // 5. Read counters.
    uint32_t clo, chi, ilo, ihi, pc;
    if (peek32(h, MERCURY_REG_CYCLES_LO, &clo)) goto err;
    if (peek32(h, MERCURY_REG_CYCLES_HI, &chi)) goto err;
    if (peek32(h, MERCURY_REG_INSN_LO,   &ilo)) goto err;
    if (peek32(h, MERCURY_REG_INSN_HI,   &ihi)) goto err;
    if (peek32(h, MERCURY_REG_PC_DBG,    &pc))  goto err;

    uint64_t cycles = ((uint64_t)chi << 32) | clo;
    uint64_t insns  = ((uint64_t)ihi << 32) | ilo;

    printf("[host] HALT  cycles=%lu  instructions=%lu  PC=0x%04x\n",
           cycles, insns, pc & 0xFFFF);
    printf("[host] cycles/instruction = %.2f (expected 128.0)\n",
           insns ? (double)cycles / (double)insns : 0.0);

    fpga_pci_detach(h);
    return 0;

err:
    fpga_pci_detach(h);
    return 1;
}

// mercury_mem.sv — 64K × 16-bit memory, true dual-port.
//
// Port A is the CPU's port (read combinational, write synchronous).
// Port B is the host loader's port, used in Phase 3.5 by the AWS F1 CL to
// preload programs over PCIe before the CPU is released from reset, and to
// read memory back after halt. Port B is unused (held idle) in the
// conformance testbench, so per-instruction execution traces remain
// byte-equivalent with the Rust simulator.
//
// Inferred as TDP BRAM on UltraScale+ (~29 × BRAM_36K @ 64K × 16). The
// "no output register" timing path is documented in hw/aws_f1/README.md.

`include "mercury_pkg.sv"

module mercury_mem (
    input  logic        clk,

    // Port A — CPU
    input  logic [15:0] addr_a,
    input  logic        we_a,
    input  logic [15:0] wdata_a,
    output logic [15:0] rdata_a,

    // Port B — host loader (held idle in CPU-only sims)
    input  logic [15:0] addr_b,
    input  logic        we_b,
    input  logic [15:0] wdata_b,
    output logic [15:0] rdata_b
);
    logic [15:0] ram [0:65535];

    assign rdata_a = ram[addr_a];
    assign rdata_b = ram[addr_b];

    always_ff @(posedge clk) begin
        if (we_a) ram[addr_a] <= wdata_a;
        if (we_b) ram[addr_b] <= wdata_b;
    end

    initial begin
        for (int i = 0; i < 65536; i++) ram[i] = 16'h0000;
    end
endmodule

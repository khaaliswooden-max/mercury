// mercury_top.sv — Mercury top wrapper.
// Wires the CPU (mercury_core) to port A of the dual-port memory; port B
// is exposed for an external loader (the AWS F1 CL in Phase 3.5). In the
// conformance testbench, port B is tied off and execution is unchanged.

`include "mercury_pkg.sv"

module mercury_top (
    input  logic        clk,
    input  logic        rst,

    // Host loader port (port B of mercury_mem).
    input  logic [15:0] host_addr,
    input  logic        host_we,
    input  logic [15:0] host_wdata,
    output logic [15:0] host_rdata,

    // Status / debug.
    output logic        halted,
    output logic [15:0] pc_dbg,
    output logic [15:0] ar_dbg,
    output logic [15:0] br_dbg,
    output logic [15:0] cr_dbg,
    output logic [15:0] res_dbg,
    output logic        sign_dbg,
    output logic        zero_or_dbg,
    output logic [63:0] cycles_dbg,
    output logic [63:0] instructions_dbg,
    output logic        insn_complete_dbg
);

    logic [15:0] cpu_addr, cpu_wdata, cpu_rdata;
    logic        cpu_we;

    mercury_core u_core (
        .clk(clk),
        .rst(rst),
        .mem_addr(cpu_addr),
        .mem_we(cpu_we),
        .mem_wdata(cpu_wdata),
        .mem_rdata(cpu_rdata),
        .halted(halted),
        .pc_dbg(pc_dbg),
        .ar_dbg(ar_dbg),
        .br_dbg(br_dbg),
        .cr_dbg(cr_dbg),
        .res_dbg(res_dbg),
        .sign_dbg(sign_dbg),
        .zero_or_dbg(zero_or_dbg),
        .cycles_dbg(cycles_dbg),
        .instructions_dbg(instructions_dbg),
        .insn_complete_dbg(insn_complete_dbg)
    );

    mercury_mem u_mem (
        .clk(clk),
        // Port A — CPU
        .addr_a(cpu_addr),
        .we_a(cpu_we),
        .wdata_a(cpu_wdata),
        .rdata_a(cpu_rdata),
        // Port B — host loader
        .addr_b(host_addr),
        .we_b(host_we),
        .wdata_b(host_wdata),
        .rdata_b(host_rdata)
    );

endmodule

// cl_mercury.sv — Custom Logic (CL) wrapper for AWS F1.
//
// This module follows the AWS HDK `developer_designs` convention. The full
// AWS shell expects a long, fixed port list (DDR4, AXI-Stream, interrupts,
// flop-protocol, etc.); the only interfaces Mercury uses are:
//
//   - clk_main_a0           — main user clock (configurable; 100 MHz nominal)
//   - rst_main_n            — shell-driven active-low reset
//   - sh_ocl_*  / ocl_sh_*  — AXI4-Lite from host (OCL bar4)
//
// All other shell-driven interfaces are tied off in `cl_tie_off.svh` (TODO
// when integrating with the HDK; see hw/aws_f1/README.md). This file is
// written so it elaborates standalone under iverilog for the wrapper
// testbench (tb_cl_mercury.sv), and so the only HDK-specific edit needed
// at integration time is renaming the port list to match the shell's
// fixed-name convention.

`include "mercury_pkg.sv"
`include "cl_mercury_defines.vh"

module cl_mercury (
    input  logic        clk,         // = clk_main_a0
    input  logic        rst_n,       // = rst_main_n

    // OCL AXI-Lite slave (single AXI4-Lite port).
    input  logic [31:0] ocl_awaddr,
    input  logic        ocl_awvalid,
    output logic        ocl_awready,
    input  logic [31:0] ocl_wdata,
    input  logic  [3:0] ocl_wstrb,
    input  logic        ocl_wvalid,
    output logic        ocl_wready,
    output logic  [1:0] ocl_bresp,
    output logic        ocl_bvalid,
    input  logic        ocl_bready,
    input  logic [31:0] ocl_araddr,
    input  logic        ocl_arvalid,
    output logic        ocl_arready,
    output logic [31:0] ocl_rdata,
    output logic  [1:0] ocl_rresp,
    output logic        ocl_rvalid,
    input  logic        ocl_rready
);

    // -----------------------------------------------------------------------
    // Wires between OCL slave and mercury_top.
    // -----------------------------------------------------------------------
    logic        cpu_rst, cpu_run_en;
    logic        halted;
    logic [15:0] pc_dbg, ar_dbg, br_dbg, cr_dbg, res_dbg;
    logic        sign_dbg, zero_or_dbg;
    logic [63:0] cycles_dbg, instructions_dbg;
    logic        insn_complete_dbg;

    logic [15:0] mem_addr_b, mem_wdata_b, mem_rdata_b;
    logic        mem_we_b;

    // -----------------------------------------------------------------------
    // CPU reset:
    //   - shell reset (~rst_n) holds Mercury in reset.
    //   - host can also assert reset via CTRL register bit 0.
    //   - when both cleared, CPU runs.
    // -----------------------------------------------------------------------
    logic core_rst;
    assign core_rst = (~rst_n) | cpu_rst | (~cpu_run_en);

    mercury_top u_top (
        .clk(clk),
        .rst(core_rst),
        .host_addr(mem_addr_b),
        .host_we(mem_we_b),
        .host_wdata(mem_wdata_b),
        .host_rdata(mem_rdata_b),
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

    ocl_slave u_ocl (
        .clk(clk),
        .rst_n(rst_n),
        .s_axi_awaddr(ocl_awaddr),
        .s_axi_awvalid(ocl_awvalid),
        .s_axi_awready(ocl_awready),
        .s_axi_wdata(ocl_wdata),
        .s_axi_wstrb(ocl_wstrb),
        .s_axi_wvalid(ocl_wvalid),
        .s_axi_wready(ocl_wready),
        .s_axi_bresp(ocl_bresp),
        .s_axi_bvalid(ocl_bvalid),
        .s_axi_bready(ocl_bready),
        .s_axi_araddr(ocl_araddr),
        .s_axi_arvalid(ocl_arvalid),
        .s_axi_arready(ocl_arready),
        .s_axi_rdata(ocl_rdata),
        .s_axi_rresp(ocl_rresp),
        .s_axi_rvalid(ocl_rvalid),
        .s_axi_rready(ocl_rready),
        .cpu_rst(cpu_rst),
        .cpu_run_en(cpu_run_en),
        .cpu_halted(halted),
        .cpu_insn_complete(insn_complete_dbg),
        .cpu_cycles(cycles_dbg),
        .cpu_instructions(instructions_dbg),
        .cpu_pc_dbg(pc_dbg),
        .cpu_res_dbg(res_dbg),
        .cpu_sign_dbg(sign_dbg),
        .cpu_zero_or_dbg(zero_or_dbg),
        .mem_addr_b(mem_addr_b),
        .mem_we_b(mem_we_b),
        .mem_wdata_b(mem_wdata_b),
        .mem_rdata_b(mem_rdata_b)
    );

endmodule

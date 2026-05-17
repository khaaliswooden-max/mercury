// tb_mercury.sv — Mercury testbench.
//
// Usage (driven from scripts/conformance.sh):
//   iverilog -g2012 -o build/tb hw/rtl/*.sv hw/tb/tb_mercury.sv
//   vvp build/tb +hex=programs/zero_b.hex +trace=build/sv_trace.jsonl
//
// Loads a 16-bit-per-line hex file into mercury_mem, releases reset, runs
// until either halted is asserted or the cycle cap is reached. Emits one
// JSONL trace line per completed instruction; the schema matches the Rust
// trace so traces can be diff'd byte-for-byte (see scripts/conformance.sh).

`include "mercury_pkg.sv"

module tb_mercury;
    import mercury_pkg::*;

    // 100 MHz simulated clock (10 ns period).
    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic rst;

    logic        halted;
    logic [15:0] pc_dbg, ar_dbg, br_dbg, cr_dbg, res_dbg;
    logic        sign_dbg, zero_or_dbg;
    logic [63:0] cycles_dbg, instructions_dbg;
    logic        insn_complete_dbg;

    mercury_top dut (
        .clk(clk),
        .rst(rst),
        // Host loader port — held idle; $readmemh writes ram directly.
        .host_addr(16'd0),
        .host_we(1'b0),
        .host_wdata(16'd0),
        .host_rdata(/* unused */),
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

    string hex_path;
    string trace_path;
    int    trace_fd;
    int    cycle_cap;

    initial begin
        if (!$value$plusargs("hex=%s", hex_path)) begin
            $display("FATAL: pass +hex=<path/to/program.hex>");
            $finish;
        end
        if (!$value$plusargs("trace=%s", trace_path)) trace_path = "sv_trace.jsonl";
        if (!$value$plusargs("cycles=%d", cycle_cap))  cycle_cap  = 1_000_000;

        // Load program.
        $readmemh(hex_path, dut.u_mem.ram);
        $display("INFO: loaded %s, max %0d cycles", hex_path, cycle_cap);

        trace_fd = $fopen(trace_path, "w");
        if (trace_fd == 0) begin
            $display("FATAL: cannot open %s for write", trace_path);
            $finish;
        end

        // Reset for 2 cycles.
        rst = 1'b1;
        @(posedge clk); @(posedge clk);
        rst = 1'b0;
    end

    // Trace one JSON line per completed instruction. Capture state on the
    // *next* edge after insn_complete so PC has settled.
    always_ff @(posedge clk) begin
        if (!rst && insn_complete_dbg) begin
            // PC at this edge is one cycle stale; sample on the next edge.
            // We use a one-cycle lookahead by capturing on insn_complete_q.
        end
    end

    logic insn_complete_q1;
    always_ff @(posedge clk) begin
        insn_complete_q1 <= insn_complete_dbg;
        if (insn_complete_q1) begin
            // halted_q1: SV's halted_l registers one cycle after PC settles,
            // so at the trace point we compute it directly from PC. This
            // matches the Rust simulator, which captures halted after the
            // halt check has run.
            $fwrite(trace_fd,
                "{\"insn\":%0d,\"cycles\":%0d,\"pc\":%0d,\"ar\":%0d,\"br\":%0d,\"cr\":%0d,\"res\":%0d,\"sign\":%0d,\"zero_or\":%0d,\"halted\":%0d}\n",
                instructions_dbg, cycles_dbg, pc_dbg, ar_dbg, br_dbg, cr_dbg,
                res_dbg, sign_dbg, zero_or_dbg,
                (halted || (pc_dbg == HALT_ADDR)));
        end
    end

    // Termination: halt or cycle cap.
    initial begin
        wait(rst == 1'b0);
        forever begin
            @(posedge clk);
            if (halted) begin
                $display("HALT  cycles=%0d insns=%0d  PC=0x%04h", cycles_dbg, instructions_dbg, pc_dbg);
                $fclose(trace_fd);
                $finish;
            end
            if (cycles_dbg >= cycle_cap) begin
                $display("CYCLE_CAP cycles=%0d insns=%0d  PC=0x%04h", cycles_dbg, instructions_dbg, pc_dbg);
                $fclose(trace_fd);
                $finish;
            end
        end
    end
endmodule

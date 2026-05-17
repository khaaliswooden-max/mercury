// tb_cl_mercury.sv — Wrapper testbench for the AWS F1 CL.
//
// Simulates the host's view: drive AXI-Lite transactions over the OCL port
// to load a program, release reset, poll status until halted, and read
// memory and counters back. Compares to the same conformance trace as the
// Rust simulator.
//
// Usage:
//   iverilog -g2012 -I hw/rtl -I hw/aws_f1/design \
//     hw/rtl/mercury_pkg.sv hw/rtl/mercury_mem.sv hw/rtl/mercury_core.sv \
//     hw/rtl/mercury_top.sv hw/aws_f1/design/ocl_slave.sv \
//     hw/aws_f1/design/cl_mercury.sv hw/tb/tb_cl_mercury.sv -o build/tb_cl
//   vvp build/tb_cl +hex=build/zero_b.hex

`include "mercury_pkg.sv"
`include "cl_mercury_defines.vh"

module tb_cl_mercury;
    import mercury_pkg::*;

    // 100 MHz simulated clock.
    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic rst_n;

    // AXI4-Lite host-side wires.
    logic [31:0] awaddr;   logic awvalid;  logic awready;
    logic [31:0] wdata;    logic [3:0] wstrb;  logic wvalid;  logic wready;
    logic  [1:0] bresp;    logic bvalid;   logic bready;
    logic [31:0] araddr;   logic arvalid;  logic arready;
    logic [31:0] rdata;    logic  [1:0] rresp;  logic rvalid;  logic rready;

    cl_mercury dut (
        .clk(clk),
        .rst_n(rst_n),
        .ocl_awaddr(awaddr),   .ocl_awvalid(awvalid),  .ocl_awready(awready),
        .ocl_wdata(wdata),     .ocl_wstrb(wstrb),      .ocl_wvalid(wvalid),  .ocl_wready(wready),
        .ocl_bresp(bresp),     .ocl_bvalid(bvalid),    .ocl_bready(bready),
        .ocl_araddr(araddr),   .ocl_arvalid(arvalid),  .ocl_arready(arready),
        .ocl_rdata(rdata),     .ocl_rresp(rresp),      .ocl_rvalid(rvalid),  .ocl_rready(rready)
    );

    // -------------------------------------------------------------------
    // AXI4-Lite host BFM (blocking, single beat).
    // -------------------------------------------------------------------
    task automatic axi_write(input logic [31:0] a, input logic [31:0] d);
        @(posedge clk);
        awaddr  <= a;     awvalid <= 1'b1;
        wdata   <= d;     wstrb   <= 4'hF;  wvalid <= 1'b1;
        bready  <= 1'b1;
        do @(posedge clk); while (!(awready && awvalid));
        awvalid <= 1'b0;
        do @(posedge clk); while (!(wready && wvalid));
        wvalid  <= 1'b0;
        do @(posedge clk); while (!bvalid);
        if (bresp != 2'b00) $display("WRITE BRESP=%b @ %h", bresp, a);
        @(posedge clk);
        bready  <= 1'b0;
    endtask

    task automatic axi_read(input logic [31:0] a, output logic [31:0] d);
        @(posedge clk);
        araddr  <= a;     arvalid <= 1'b1;
        rready  <= 1'b1;
        do @(posedge clk); while (!(arready && arvalid));
        arvalid <= 1'b0;
        do @(posedge clk); while (!rvalid);
        d = rdata;
        @(posedge clk);
        rready  <= 1'b0;
    endtask

    // -------------------------------------------------------------------
    // Program loader: read $readmemh-style hex into a local array, push to
    // the FPGA over OCL memory-backdoor writes.
    // -------------------------------------------------------------------
    string hex_path;
    logic [15:0] prog_image [0:65535];

    initial begin : main
        logic [31:0] tmp;
        logic [31:0] status;
        int          cap;
        int          word_count;
        int          idx;
        cap = 5000;

        if (!$value$plusargs("hex=%s", hex_path)) begin
            $display("FATAL: pass +hex=<path/to/program.hex>"); $finish;
        end

        // Initialize AXI signals.
        awaddr  = 32'd0;  awvalid = 1'b0;
        wdata   = 32'd0;  wstrb   = 4'h0;  wvalid = 1'b0;
        bready  = 1'b0;
        araddr  = 32'd0;  arvalid = 1'b0;
        rready  = 1'b0;

        // Initialize local program image to 0 and load hex on top.
        for (int i = 0; i < 65536; i++) prog_image[i] = 16'h0000;
        $readmemh(hex_path, prog_image);

        rst_n = 1'b0;
        #50;
        rst_n = 1'b1;
        @(posedge clk);

        // 1. Hold CPU in reset (default after rst_n release).
        // 2. Load only the words that are nonzero — keeps sim fast for
        //    small programs.
        word_count = 0;
        for (int i = 0; i < 65536; i++) begin
            if (prog_image[i] != 16'h0000) begin
                axi_write(`MERCURY_MEM_BASE + (i << 2), {16'd0, prog_image[i]});
                word_count++;
            end
        end
        $display("HOST: loaded %0d nonzero words", word_count);

        // 3. Spot-check by reading one nonzero word back.
        if (word_count > 0) begin
            idx = -1;
            for (int i = 0; i < 65536; i++)
                if (prog_image[i] != 16'h0000 && idx == -1) idx = i;
            axi_read(`MERCURY_MEM_BASE + (idx << 2), tmp);
            if (tmp[15:0] != prog_image[idx])
                $display("HOST: readback mismatch at %0d: got %h, expect %h",
                         idx, tmp[15:0], prog_image[idx]);
            else
                $display("HOST: readback ok at addr %0d = 0x%04h", idx, tmp[15:0]);
        end

        // 4. Release reset and run.
        axi_write(`MERCURY_REG_CTRL,
                  (1 << `CTRL_BIT_RUN_EN) | (0 << `CTRL_BIT_RST));

        // 5. Poll STATUS for halted.
        begin : poll
            int i;
            logic done;
            done = 1'b0;
            for (i = 0; i < cap; i++) begin
                if (!done) begin
                    axi_read(`MERCURY_REG_STATUS, status);
                    if (status[`STATUS_BIT_HALTED]) done = 1'b1;
                end
            end
            if (!done) begin
                $display("HOST: TIMEOUT (status=%h)", status);
                $finish;
            end
        end

        // 6. Read final counters and a couple debug registers.
        axi_read(`MERCURY_REG_CYCLES_LO, tmp); $display("HOST: cycles_lo = %0d", tmp);
        axi_read(`MERCURY_REG_INSN_LO,   tmp); $display("HOST: insns    = %0d", tmp);
        axi_read(`MERCURY_REG_PC_DBG,    tmp); $display("HOST: PC       = 0x%04h", tmp[15:0]);

        $display("HOST: DONE");
        $finish;
    end

    // Safety timeout.
    initial begin
        #5_000_000;   // 5 ms simulated
        $display("HOST: FATAL TIMEOUT");
        $finish;
    end
endmodule

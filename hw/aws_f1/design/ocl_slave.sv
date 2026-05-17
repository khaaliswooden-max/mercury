// ocl_slave.sv — AXI4-Lite slave for the CL.
//
// Address map (32-bit aligned, 4 MB OCL window):
//
//   0x000000  CTRL          [W] bit0=rst (1=hold reset, 0=release), bit1=run_en
//             CTRL          [R] mirrors last write
//   0x000004  STATUS        [R] bit0=halted, bit1=insn_complete_q
//   0x000008  CYCLES_LO     [R] lower 32 bits of cycles_dbg
//   0x00000C  CYCLES_HI     [R] upper 32 bits
//   0x000010  INSN_LO       [R] lower 32 bits of instructions_dbg
//   0x000014  INSN_HI       [R] upper 32 bits
//   0x000018  PC_DBG        [R] {16'h0, pc_dbg}
//   0x00001C  DEBUG         [R] {sign_dbg, zero_or_dbg, 14'h0, res_dbg}
//
//   0x100000 + (word_addr<<2)   MEMORY BACKDOOR
//             [W] writes wdata[15:0] into mercury_mem at word_addr (port B)
//             [R] reads  mercury_mem[word_addr] into rdata[15:0]
//             64 K words × 4 B = 256 KB at offsets 0x100000–0x13FFFF
//
// Transaction style: blocking single-beat, write-after-read serialization.
// Adequate for control plane and 64K-word program loads. Throughput
// optimization (AXI-MM DMA) is Phase 3.5+ optional and lives behind a
// different interface (PCIs) per AWS HDK conventions.

`include "mercury_pkg.sv"

module ocl_slave
    import mercury_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // AXI4-Lite from shell.  AW / W / B / AR / R channels.
    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic  [3:0] s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic  [1:0] s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic  [1:0] s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // To/from mercury_top.
    output logic        cpu_rst,
    output logic        cpu_run_en,
    input  logic        cpu_halted,
    input  logic        cpu_insn_complete,
    input  logic [63:0] cpu_cycles,
    input  logic [63:0] cpu_instructions,
    input  logic [15:0] cpu_pc_dbg,
    input  logic [15:0] cpu_res_dbg,
    input  logic        cpu_sign_dbg,
    input  logic        cpu_zero_or_dbg,

    // Host-side port B of mercury_mem.
    output logic [15:0] mem_addr_b,
    output logic        mem_we_b,
    output logic [15:0] mem_wdata_b,
    input  logic [15:0] mem_rdata_b
);

    // Latched control register.
    logic [31:0] ctrl_q;
    assign cpu_rst    = ctrl_q[0];
    assign cpu_run_en = ctrl_q[1];

    // -----------------------------------------------------------------------
    // Write channel FSM
    // -----------------------------------------------------------------------
    typedef enum logic [1:0] { W_IDLE, W_DATA, W_RESP } w_state_t;
    w_state_t w_state;

    logic [31:0] aw_addr_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            w_state       <= W_IDLE;
            aw_addr_q     <= 32'd0;
            ctrl_q        <= 32'h0000_0001;   // start with cpu_rst asserted
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            mem_we_b      <= 1'b0;
            mem_addr_b    <= 16'd0;
            mem_wdata_b   <= 16'd0;
        end else begin
            mem_we_b <= 1'b0;  // pulse for one cycle when memory write fires
            unique case (w_state)
                W_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b0;
                    s_axi_bvalid  <= 1'b0;
                    if (s_axi_awvalid && s_axi_awready) begin
                        aw_addr_q     <= s_axi_awaddr;
                        s_axi_awready <= 1'b0;
                        w_state       <= W_DATA;
                    end
                end
                W_DATA: begin
                    s_axi_wready <= 1'b1;
                    if (s_axi_wvalid && s_axi_wready) begin
                        s_axi_wready <= 1'b0;
                        // Decode.
                        if (aw_addr_q[23:20] == 4'h0) begin
                            // Register space.
                            unique case (aw_addr_q[7:0])
                                8'h00: ctrl_q <= s_axi_wdata;
                                default: ;  // ignore writes to RO regs
                            endcase
                            s_axi_bresp <= 2'b00; // OKAY
                        end else if (aw_addr_q[23:20] == 4'h1) begin
                            // Memory backdoor.
                            mem_addr_b  <= aw_addr_q[17:2];
                            mem_wdata_b <= s_axi_wdata[15:0];
                            mem_we_b    <= 1'b1;
                            s_axi_bresp <= 2'b00;
                        end else begin
                            s_axi_bresp <= 2'b10; // SLVERR
                        end
                        s_axi_bvalid <= 1'b1;
                        w_state      <= W_RESP;
                    end
                end
                W_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        w_state      <= W_IDLE;
                    end
                end
                default: w_state <= W_IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Read channel FSM (2-cycle: latch addr → drive memory → return rdata)
    // -----------------------------------------------------------------------
    typedef enum logic [1:0] { R_IDLE, R_MEM_LAT, R_DATA } r_state_t;
    r_state_t r_state;

    logic [31:0] ar_addr_q;
    logic [31:0] r_data_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            r_state       <= R_IDLE;
            ar_addr_q     <= 32'd0;
            r_data_q      <= 32'd0;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= 2'b00;
        end else begin
            unique case (r_state)
                R_IDLE: begin
                    s_axi_arready <= 1'b1;
                    s_axi_rvalid  <= 1'b0;
                    if (s_axi_arvalid && s_axi_arready) begin
                        ar_addr_q     <= s_axi_araddr;
                        s_axi_arready <= 1'b0;
                        if (s_axi_araddr[23:20] == 4'h1) begin
                            // Memory read: drive port B address; rdata is
                            // combinational, so we can sample next cycle.
                            mem_addr_b <= s_axi_araddr[17:2];
                            r_state    <= R_MEM_LAT;
                        end else begin
                            r_state <= R_DATA;
                            unique case (s_axi_araddr[7:0])
                                8'h00: r_data_q <= ctrl_q;
                                8'h04: r_data_q <= {30'd0, cpu_insn_complete, cpu_halted};
                                8'h08: r_data_q <= cpu_cycles[31:0];
                                8'h0C: r_data_q <= cpu_cycles[63:32];
                                8'h10: r_data_q <= cpu_instructions[31:0];
                                8'h14: r_data_q <= cpu_instructions[63:32];
                                8'h18: r_data_q <= {16'd0, cpu_pc_dbg};
                                8'h1C: r_data_q <= {cpu_sign_dbg, cpu_zero_or_dbg, 14'd0, cpu_res_dbg};
                                default: r_data_q <= 32'hDEAD_BEEF;
                            endcase
                            s_axi_rresp <= 2'b00;
                        end
                    end
                end
                R_MEM_LAT: begin
                    r_data_q    <= {16'd0, mem_rdata_b};
                    s_axi_rresp <= 2'b00;
                    r_state     <= R_DATA;
                end
                R_DATA: begin
                    s_axi_rdata  <= r_data_q;
                    s_axi_rvalid <= 1'b1;
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        r_state      <= R_IDLE;
                    end
                end
                default: r_state <= R_IDLE;
            endcase
        end
    end

endmodule

// mercury_core.sv — bit-serial Subleq CPU.
//
// Cycle-accurate implementation of ARCH.md §4–§9. Each clock cycle moves
// exactly one bit on the bit-bus (LSB-first). Eight phases of 16 cycles
// each = 128 cycles per Subleq instruction. The state-transition order is
// byte-equivalent with crates/mercury-sim/src/lib.rs; that equivalence is
// the Phase 3 conformance contract.

`include "mercury_pkg.sv"

module mercury_core
    import mercury_pkg::*;
(
    input  logic        clk,
    input  logic        rst,
    // Memory port.
    output logic [15:0] mem_addr,
    output logic        mem_we,
    output logic [15:0] mem_wdata,
    input  logic [15:0] mem_rdata,
    // Status.
    output logic        halted,
    // Debug taps.
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

    // ---------------------------------------------------------------------
    // FSM and architectural state
    // ---------------------------------------------------------------------
    phase_t phase_q, phase_n;
    logic [3:0] cyc_q, cyc_n;

    logic [15:0] pc, ar, br, cr, op1, op2, res;
    logic        c_in, sign_l, zero_or, halted_l;
    logic [15:0] pc_next_q;

    logic [63:0] cycles, instructions;

    // ---------------------------------------------------------------------
    // Phase predicates
    // ---------------------------------------------------------------------
    logic is_ex_cyc0, is_br_cyc0;
    assign is_ex_cyc0 = (phase_q == PH_EX) && (cyc_q == 4'd0);
    assign is_br_cyc0 = (phase_q == PH_BR) && (cyc_q == 4'd0);

    // ---------------------------------------------------------------------
    // Address mux
    // ---------------------------------------------------------------------
    always_comb begin
        unique case (phase_q)
            PH_F1: mem_addr = pc;
            PH_F2: mem_addr = pc + 16'd1;
            PH_F3: mem_addr = pc + 16'd2;
            PH_L1: mem_addr = ar;
            PH_L2: mem_addr = br;
            PH_ST: mem_addr = br;
            default: mem_addr = 16'd0;
        endcase
    end

    // ---------------------------------------------------------------------
    // Bit-serial subtract:  RES_i = OP2_i + ~OP1_i + C_in
    // At EX cycle 0, substitute C_in_init = 1 ("+1" of two's complement),
    // bypassing the stale c_in register.
    // ---------------------------------------------------------------------
    logic ex_a, ex_b_inv, ex_cin_used, ex_s, ex_cout;
    assign ex_a        = op2[cyc_q];
    assign ex_b_inv    = ~op1[cyc_q];
    assign ex_cin_used = is_ex_cyc0 ? 1'b1 : c_in;
    assign ex_s        = ex_a ^ ex_b_inv ^ ex_cin_used;
    assign ex_cout     = (ex_a & ex_b_inv) | (ex_cin_used & (ex_a ^ ex_b_inv));

    // ---------------------------------------------------------------------
    // Branch decision  (BRANCH_TAKEN = SIGN ∨ ¬ZERO_OR)
    // ---------------------------------------------------------------------
    logic        branch_taken;
    logic [15:0] pc_next_comb;
    assign branch_taken = sign_l | ~zero_or;
    assign pc_next_comb = branch_taken ? cr : (pc + 16'd3);

    // ---------------------------------------------------------------------
    // Memory write: read-modify-write one bit during ST phase.
    // ---------------------------------------------------------------------
    logic [15:0] st_patched;
    always_comb begin
        st_patched        = mem_rdata;
        st_patched[cyc_q] = res[cyc_q];
    end
    assign mem_we    = (phase_q == PH_ST) && !halted_l;
    assign mem_wdata = st_patched;

    // ---------------------------------------------------------------------
    // FSM next state
    // ---------------------------------------------------------------------
    always_comb begin
        if (cyc_q == 4'd15) begin
            cyc_n = 4'd0;
            unique case (phase_q)
                PH_F1: phase_n = PH_F2;
                PH_F2: phase_n = PH_F3;
                PH_F3: phase_n = PH_L1;
                PH_L1: phase_n = PH_L2;
                PH_L2: phase_n = PH_EX;
                PH_EX: phase_n = PH_ST;
                PH_ST: phase_n = PH_BR;
                PH_BR: phase_n = PH_F1;
                default: phase_n = PH_F1;
            endcase
        end else begin
            cyc_n   = cyc_q + 4'd1;
            phase_n = phase_q;
        end
    end

    // ---------------------------------------------------------------------
    // Instruction-complete pulse
    // ---------------------------------------------------------------------
    logic insn_complete;
    assign insn_complete = (phase_q == PH_BR) && (cyc_q == 4'd15) && !halted_l;

    // ---------------------------------------------------------------------
    // Sequential state
    // ---------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            phase_q      <= PH_F1;
            cyc_q        <= 4'd0;
            pc           <= 16'd0;
            ar           <= 16'd0;
            br           <= 16'd0;
            cr           <= 16'd0;
            op1          <= 16'd0;
            op2          <= 16'd0;
            res          <= 16'd0;
            c_in         <= 1'b0;
            sign_l       <= 1'b0;
            zero_or      <= 1'b0;
            halted_l     <= 1'b0;
            pc_next_q    <= 16'd0;
            cycles       <= 64'd0;
            instructions <= 64'd0;
        end else if (!halted_l) begin
            phase_q <= phase_n;
            cyc_q   <= cyc_n;
            cycles  <= cycles + 64'd1;

            unique case (phase_q)
                PH_F1: ar[cyc_q]  <= mem_rdata[cyc_q];
                PH_F2: br[cyc_q]  <= mem_rdata[cyc_q];
                PH_F3: cr[cyc_q]  <= mem_rdata[cyc_q];
                PH_L1: op1[cyc_q] <= mem_rdata[cyc_q];
                PH_L2: op2[cyc_q] <= mem_rdata[cyc_q];

                PH_EX: begin
                    res[cyc_q] <= ex_s;
                    c_in       <= ex_cout;
                    sign_l     <= ex_s;
                    zero_or    <= (is_ex_cyc0 ? 1'b0 : zero_or) | ex_s;
                end

                PH_ST: ; // memory write is combinational via mem_we/mem_wdata

                PH_BR: begin
                    if (is_br_cyc0) begin
                        pc_next_q <= pc_next_comb;
                        pc[0]     <= pc_next_comb[0];
                    end else begin
                        pc[cyc_q] <= pc_next_q[cyc_q];
                    end
                end

                default: ;
            endcase

            if (insn_complete) instructions <= instructions + 64'd1;
        end
    end

    // ---------------------------------------------------------------------
    // Halt detection — one cycle after BR completes, PC has settled.
    // ---------------------------------------------------------------------
    logic insn_complete_q;
    always_ff @(posedge clk) begin
        if (rst) begin
            insn_complete_q <= 1'b0;
        end else begin
            insn_complete_q <= insn_complete;
            if (insn_complete_q && (pc == HALT_ADDR)) halted_l <= 1'b1;
        end
    end

    // ---------------------------------------------------------------------
    // Outputs
    // ---------------------------------------------------------------------
    assign halted            = halted_l;
    assign pc_dbg            = pc;
    assign ar_dbg            = ar;
    assign br_dbg            = br;
    assign cr_dbg            = cr;
    assign res_dbg           = res;
    assign sign_dbg          = sign_l;
    assign zero_or_dbg       = zero_or;
    assign cycles_dbg        = cycles;
    assign instructions_dbg  = instructions;
    assign insn_complete_dbg = insn_complete;

endmodule

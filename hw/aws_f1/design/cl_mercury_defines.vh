// cl_mercury_defines.vh — CL-side parameters.
//
// Address map mirrors ocl_slave.sv. Host software in
// hw/aws_f1/verif/tests/test_mercury.c references these as numeric literals
// for portability; this header is the source of truth.

`ifndef CL_MERCURY_DEFINES_VH
`define CL_MERCURY_DEFINES_VH

`define MERCURY_REG_CTRL       32'h0000_0000
`define MERCURY_REG_STATUS     32'h0000_0004
`define MERCURY_REG_CYCLES_LO  32'h0000_0008
`define MERCURY_REG_CYCLES_HI  32'h0000_000C
`define MERCURY_REG_INSN_LO    32'h0000_0010
`define MERCURY_REG_INSN_HI    32'h0000_0014
`define MERCURY_REG_PC_DBG     32'h0000_0018
`define MERCURY_REG_DEBUG      32'h0000_001C

`define MERCURY_MEM_BASE       32'h0010_0000
`define MERCURY_MEM_SPAN       32'h0004_0000   // 64K words × 4 B

// CTRL register bits.
`define CTRL_BIT_RST           0
`define CTRL_BIT_RUN_EN        1

// STATUS register bits.
`define STATUS_BIT_HALTED      0
`define STATUS_BIT_INSN_DONE   1

`endif

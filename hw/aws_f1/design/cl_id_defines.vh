// cl_id_defines.vh — vendor/device IDs surfaced to the AFI metadata.
//
// These values are read by the HDK during DCP build and embedded in the AFI
// metadata that AWS registers. Values shown are placeholders; edit before
// running `aws ec2 create-fpga-image`.

`ifndef CL_ID_DEFINES_VH
`define CL_ID_DEFINES_VH

`define CL_SH_ID0   32'hF000_1D0F   // Vendor ID 0x1D0F = Amazon
`define CL_SH_ID1   32'h1D51_FEDC   // Device/Subsystem ID (project-specific)

// Version: bumped on every AFI rebuild for traceability.
`define CL_VERSION  32'h0000_0100   // v0.1.0 — Phase 3.5 baseline

`endif

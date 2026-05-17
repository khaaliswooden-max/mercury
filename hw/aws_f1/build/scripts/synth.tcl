# synth.tcl — Vivado synthesis settings for cl_mercury.
#
# Sourced by the HDK's aws_build_dcp_from_cl.sh. The HDK provides the bulk
# of the synthesis flow (shell wrapper, IP packaging, timing closure); this
# file only adds Mercury-specific options.

# Source list — files synthesized as part of the CL.
set CL_DIR $::env(CL_DIR)

read_verilog -sv [glob $CL_DIR/design/mercury_pkg.sv]
read_verilog -sv [glob $CL_DIR/design/mercury_mem.sv]
read_verilog -sv [glob $CL_DIR/design/mercury_core.sv]
read_verilog -sv [glob $CL_DIR/design/mercury_top.sv]
read_verilog -sv [glob $CL_DIR/design/ocl_slave.sv]
read_verilog -sv [glob $CL_DIR/design/cl_mercury.sv]

# Include search path for `include directives.
set_property include_dirs $CL_DIR/design [current_fileset]

# Clock constraint: 125 MHz nominal (clk_main_a0 in the F1 shell).
# Override via -clock_recipe_a in aws_build_dcp_from_cl.sh if desired.

# Synthesis strategy.
set_property STRATEGY {Flow_PerfOptimized_high} [get_runs synth_1]

# Don't infer DSPs for the 1-bit adder.
set_property USE_DSP no [current_fileset]

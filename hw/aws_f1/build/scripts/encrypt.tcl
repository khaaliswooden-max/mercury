# encrypt.tcl — Vivado IP encryption stub.
#
# The HDK calls this with $CL_DIR set to the developer_designs/cl_mercury
# path. Mercury sources are open; we copy them through unchanged but apply
# the HDK's standard encrypt step so the rest of the flow is happy.

set CL_DIR $::env(CL_DIR)
set OUT_DIR $::env(CL_DIR)/build/src_post_encryption

file mkdir $OUT_DIR

foreach f [glob $CL_DIR/design/*.sv $CL_DIR/design/*.vh] {
    file copy -force $f $OUT_DIR/[file tail $f]
}

# If you ever want to encrypt for IP distribution, uncomment and supply a key:
# encrypt -key $CL_DIR/build/scripts/encryption.key \
#         -lang verilog \
#         [glob $OUT_DIR/*.sv]

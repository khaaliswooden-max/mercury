#!/usr/bin/env bash
# build_afi.sh — driver for the AWS HDK DCP + AFI build.
#
# Prereqs (on the FPGA Developer AMI):
#   - `git clone https://github.com/aws/aws-fpga.git`
#   - `source aws-fpga/hdk_setup.sh`
#
# This script copies Mercury's CL into the HDK's developer_designs slot,
# invokes the HDK's standard DCP builder, then registers the AFI from the
# resulting tarball.
#
# Required env vars:
#   HDK_DIR    — path to aws-fpga/hdk (set by hdk_setup.sh)
#   S3_BUCKET  — your AFI staging bucket, e.g. "mercury-afi-staging"
#   S3_DCP_KEY — object key for the DCP tarball, e.g. "dcp/phase35.tar"

set -euo pipefail
cd "$(dirname "$0")/../../.."

: "${HDK_DIR:?HDK_DIR not set — did you source hdk_setup.sh?}"
: "${S3_BUCKET:?S3_BUCKET not set}"
: "${S3_DCP_KEY:?S3_DCP_KEY not set}"

CL_DIR="$HDK_DIR/cl/developer_designs/cl_mercury"

echo "═══ 1. stage Mercury CL into $CL_DIR"
mkdir -p "$CL_DIR/design" "$CL_DIR/verif/tests" "$CL_DIR/build/scripts"
cp hw/rtl/*.sv                         "$CL_DIR/design/"
cp hw/aws_f1/design/*.sv               "$CL_DIR/design/"
cp hw/aws_f1/design/*.vh               "$CL_DIR/design/"
cp hw/aws_f1/verif/tests/*             "$CL_DIR/verif/tests/"
cp hw/aws_f1/build/scripts/encrypt.tcl "$CL_DIR/build/scripts/" 2>/dev/null || true
cp hw/aws_f1/build/scripts/synth.tcl   "$CL_DIR/build/scripts/" 2>/dev/null || true

echo "═══ 2. run HDK DCP build (this takes several hours)"
cd "$CL_DIR/build/scripts"
./aws_build_dcp_from_cl.sh -foreground

echo "═══ 3. locate built tarball"
TARBALL=$(ls -t "$CL_DIR/build/checkpoints/to_aws/"*.Developer_CL.tar | head -1)
echo "    found: $TARBALL"

echo "═══ 4. upload to S3"
aws s3 cp "$TARBALL" "s3://${S3_BUCKET}/${S3_DCP_KEY}"

echo "═══ 5. register AFI"
aws ec2 create-fpga-image \
    --name "mercury-phase35-$(date +%Y%m%d-%H%M)" \
    --description "Mercury bit-serial Subleq CPU (Phase 3.5)" \
    --input-storage-location "Bucket=${S3_BUCKET},Key=${S3_DCP_KEY}" \
    --logs-storage-location  "Bucket=${S3_BUCKET},Key=logs/"

echo "═══ done. AFI registration is asynchronous; poll with:"
echo "    aws ec2 describe-fpga-images --owners self"

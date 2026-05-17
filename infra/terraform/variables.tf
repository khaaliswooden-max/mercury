# variables.tf — inputs.
#
# Edit values via terraform.tfvars, environment variables (TF_VAR_*), or
# the CLI (-var). aws_region must be one of the F1-supported regions:
# us-east-1, us-west-2, eu-west-1, ap-southeast-2 (verify current list
# at https://aws.amazon.com/ec2/instance-types/f1/).

variable "aws_region" {
  description = "AWS region. Must be F1-enabled for synthesis output to be usable."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix for resource naming."
  type        = string
  default     = "mercury"
}

variable "environment" {
  description = "Environment tag (dev, staging, prod). Used in resource names."
  type        = string
  default     = "dev"
}

variable "github_owner" {
  description = "GitHub org/user that owns the repo (for OIDC trust)."
  type        = string
  default     = "khaaliswooden-max"
}

variable "github_repo" {
  description = "Repo name."
  type        = string
  default     = "mercury"
}

variable "codebuild_image" {
  description = <<EOT
Docker image for CodeBuild. The default uses Amazon's standard image, which
DOES NOT include Vivado. To run the actual AFI synthesis you must either:
  (a) push a custom image to ECR derived from the FPGA Developer AMI, OR
  (b) replace CodeBuild with an EC2 launch from the FPGA Developer AMI.
See infra/README.md §"Vivado licensing" for the trade-offs.
EOT
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
}

variable "codebuild_compute_type" {
  description = "CodeBuild compute. Vivado synthesis wants at least LARGE."
  type        = string
  default     = "BUILD_GENERAL1_LARGE"
}

variable "enable_graviton_runner" {
  description = <<EOT
Provision a t4g.small as a self-hosted GitHub Actions runner for the Rust /
iverilog side. Optional; GitHub-hosted runners work fine for the
conformance gates. Default off to avoid a recurring instance bill.
EOT
  type        = bool
  default     = false
}

variable "graviton_instance_type" {
  description = "Instance type for the optional self-hosted runner."
  type        = string
  default     = "t4g.small"
}

# versions.tf — toolchain and provider pinning.
#
# Pinning aws-provider major version protects against silent breaking
# changes. Minor and patch versions float so security patches land
# automatically when terraform init -upgrade runs.

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "mercury"
      Phase     = "4"
      ManagedBy = "terraform"
      Repo      = "github.com/khaaliswooden-max/mercury"
    }
  }
}

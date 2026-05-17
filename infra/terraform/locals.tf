# locals.tf — derived values and naming convention.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"

  # Bucket names must be globally unique; suffix with account ID.
  artifacts_bucket_name = "${local.name_prefix}-afi-artifacts-${data.aws_caller_identity.current.account_id}"
  logs_bucket_name      = "${local.name_prefix}-afi-logs-${data.aws_caller_identity.current.account_id}"

  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  # GitHub OIDC subject claim — restricts the role to this repo, any branch
  # or PR. Tighten further with branch refs in production.
  github_oidc_subject = "repo:${var.github_owner}/${var.github_repo}:*"
}

# outputs.tf — values needed by GitHub Actions workflows.

output "aws_region" {
  value = local.region
}

output "afi_artifacts_bucket" {
  value       = aws_s3_bucket.afi_artifacts.bucket
  description = "S3 bucket for DCP tarballs and build artifacts."
}

output "afi_logs_bucket" {
  value       = aws_s3_bucket.afi_logs.bucket
  description = "S3 bucket for CodeBuild and AFI registration logs."
}

output "codebuild_project_name" {
  value       = aws_codebuild_project.synth.name
  description = "Pass to aws codebuild start-build --project-name."
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "Configure as AWS_ROLE_TO_ASSUME in repo secrets."
}

output "graviton_runner_instance_id" {
  value       = var.enable_graviton_runner ? aws_instance.graviton_runner[0].id : null
  description = "Instance ID of the self-hosted runner (null if disabled)."
}

# codebuild.tf — synthesis pipeline.
#
# This project runs infra/buildspec/synth.yml on a CodeBuild worker. The
# default image (amazonlinux2-x86_64-standard) does NOT include Vivado;
# the buildspec will fail past the "verify Vivado" step until you replace
# `codebuild_image` with an ECR image you've built from the FPGA Developer
# AMI. See infra/README.md.
#
# Builds are NOT triggered automatically — they fire only via GitHub
# Actions' workflow_dispatch (.github/workflows/synth.yml) or manual
# `aws codebuild start-build` calls. This prevents accidental multi-hour
# spend on every PR.

resource "aws_codebuild_project" "synth" {
  name          = "${local.name_prefix}-synth"
  description   = "Mercury — Vivado synthesis and AFI registration"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 480 # minutes; Vivado typically 180–360

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.afi_artifacts.bucket
    path      = "builds"
    name      = "synth-output.zip"
    packaging = "ZIP"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "S3_BUCKET"
      value = aws_s3_bucket.afi_artifacts.bucket
    }

    environment_variable {
      name  = "S3_LOGS_BUCKET"
      value = aws_s3_bucket.afi_logs.bucket
    }

    environment_variable {
      name  = "AWS_REGION"
      value = local.region
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.name_prefix}-synth"
      stream_name = "synth"
    }

    s3_logs {
      status   = "ENABLED"
      location = "${aws_s3_bucket.afi_logs.bucket}/codebuild"
    }
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/${var.github_owner}/${var.github_repo}.git"
    git_clone_depth = 1
    buildspec       = "infra/buildspec/synth.yml"
  }

  source_version = "main"
}

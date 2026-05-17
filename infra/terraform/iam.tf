# iam.tf — service roles for CodeBuild and GitHub Actions OIDC.

# ----------------------------------------------------------------------------
# CodeBuild service role
# ----------------------------------------------------------------------------

data "aws_iam_policy_document" "codebuild_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${local.name_prefix}-codebuild"
  assume_role_policy = data.aws_iam_policy_document.codebuild_trust.json
}

data "aws_iam_policy_document" "codebuild_permissions" {
  statement {
    sid = "CloudWatchLogs"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/${local.name_prefix}-*",
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/${local.name_prefix}-*:*",
    ]
  }

  statement {
    sid = "S3Artifacts"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.afi_artifacts.arn,
      "${aws_s3_bucket.afi_artifacts.arn}/*",
      aws_s3_bucket.afi_logs.arn,
      "${aws_s3_bucket.afi_logs.arn}/*",
    ]
  }

  statement {
    sid = "FpgaImageRegistration"

    actions = [
      "ec2:CreateFpgaImage",
      "ec2:DescribeFpgaImages",
      "ec2:CopyFpgaImage",
    ]

    resources = ["*"] # CreateFpgaImage does not support resource-level perms
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "${local.name_prefix}-codebuild-policy"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild_permissions.json
}

# ----------------------------------------------------------------------------
# GitHub Actions OIDC provider and role
# ----------------------------------------------------------------------------
# Thumbprint is published by GitHub; pinning protects against MITM. Update
# from https://github.blog/changelog/ if GitHub rotates its CA.

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_oidc_subject]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.name_prefix}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}

data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid = "StartCodeBuild"

    actions = [
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds",
      "codebuild:ListBuildsForProject",
    ]

    resources = [aws_codebuild_project.synth.arn]
  }

  statement {
    sid = "ReadArtifacts"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.afi_artifacts.arn,
      "${aws_s3_bucket.afi_artifacts.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${local.name_prefix}-github-actions-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}

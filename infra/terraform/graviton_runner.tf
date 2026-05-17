# graviton_runner.tf — optional self-hosted GitHub Actions runner on t4g.
#
# Off by default. Toggle with `terraform apply -var enable_graviton_runner=true`.
#
# Rationale: Mercury's Rust+iverilog conformance gates take <1 minute on a
# GitHub-hosted x86 runner, which is free for public repos. A Graviton
# runner is included for thematic reasons (Landauer-friendly perf-per-watt
# fits the Mercury project's energy-aware framing) and as scaffolding if
# the test matrix grows. Production environments should prefer ephemeral
# runners (Actions Runner Controller on EKS) over this long-lived instance.

data "aws_ami" "amazon_linux_2023_arm64" {
  count       = var.enable_graviton_runner ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-arm64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_iam_role" "graviton_runner" {
  count = var.enable_graviton_runner ? 1 : 0
  name  = "${local.name_prefix}-graviton-runner"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "graviton_ssm" {
  count      = var.enable_graviton_runner ? 1 : 0
  role       = aws_iam_role.graviton_runner[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "graviton_runner" {
  count = var.enable_graviton_runner ? 1 : 0
  name  = "${local.name_prefix}-graviton-runner"
  role  = aws_iam_role.graviton_runner[0].name
}

resource "aws_security_group" "graviton_runner" {
  count       = var.enable_graviton_runner ? 1 : 0
  name        = "${local.name_prefix}-graviton-runner"
  description = "Egress only; SSM Session Manager for admin"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "graviton_runner" {
  count                  = var.enable_graviton_runner ? 1 : 0
  ami                    = data.aws_ami.amazon_linux_2023_arm64[0].id
  instance_type          = var.graviton_instance_type
  iam_instance_profile   = aws_iam_instance_profile.graviton_runner[0].name
  vpc_security_group_ids = [aws_security_group.graviton_runner[0].id]

  user_data = <<-EOT
    #!/bin/bash
    set -eux
    dnf update -y
    dnf install -y git iverilog gcc

    # Install Rust as ec2-user.
    sudo -u ec2-user bash -c '
      curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    '

    # GitHub Actions runner registration requires a one-time token retrieved
    # from the GitHub API. Out of scope for terraform; document in
    # infra/README.md and use SSM Session Manager to register.
  EOT

  tags = {
    Name = "${local.name_prefix}-graviton-runner"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

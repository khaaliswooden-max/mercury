# Infrastructure (Phase 4)

This directory contains the AWS infrastructure-as-code and CI configuration
that turns the Phase 3.5 simulation work into a reproducible AFI build
pipeline. The boundary is clear:

- **GitHub Actions (free, fast)** — runs the Phase 2 / 3 / 3.5 conformance
  gates on every PR. No AWS credentials touched.
- **AWS CodeBuild (paid, slow)** — runs Vivado synthesis on manual trigger
  to produce a DCP tarball, then registers an AFI. Touches AWS.

```
infra/
├── README.md                  this file
├── terraform/                 buckets, IAM, CodeBuild, optional Graviton
│   ├── versions.tf
│   ├── variables.tf
│   ├── locals.tf
│   ├── s3.tf
│   ├── iam.tf
│   ├── codebuild.tf
│   ├── graviton_runner.tf     opt-in via enable_graviton_runner=true
│   └── outputs.tf
└── buildspec/
    └── synth.yml              CodeBuild's pipeline definition

.github/
└── workflows/
    ├── conformance.yml        PR gate (free, GitHub-hosted)
    └── synth.yml              manual workflow_dispatch → CodeBuild
```

## What gets created

| Resource | Purpose | Recurring cost |
|---|---|---|
| `mercury-dev-afi-artifacts-<acct>` | S3 bucket: DCP tarballs, AFI inputs | pennies/mo |
| `mercury-dev-afi-logs-<acct>` | S3 bucket: CodeBuild + AFI logs (90-day TTL) | pennies/mo |
| `mercury-dev-codebuild` | IAM role: CodeBuild → S3 + EC2 FPGA APIs | $0 |
| `mercury-dev-github-actions` | IAM role: GitHub OIDC → start CodeBuild | $0 |
| GitHub OIDC provider | Federates `repo:.../mercury:*` to AWS | $0 |
| `mercury-dev-synth` | CodeBuild project, fires only via workflow_dispatch | per-minute when running |
| `mercury-dev-graviton-runner` | EC2 t4g.small (optional, off by default) | ~$10–15/mo if on |

**Verify all current pricing before applying.** The cost figures above are
order-of-magnitude only; AWS prices change.

## One-time setup

### 1. Apply the Terraform

```bash
cd infra/terraform

# Optional but recommended: configure a remote backend for state.
# The local backend (default) is fine for solo development.

terraform init
terraform fmt -check
terraform validate
terraform plan -var github_owner=<your-gh-user>
terraform apply -var github_owner=<your-gh-user>
```

Note the outputs — you'll wire them into GitHub next:

```
afi_artifacts_bucket    = "mercury-dev-afi-artifacts-..."
codebuild_project_name  = "mercury-dev-synth"
github_actions_role_arn = "arn:aws:iam::...:role/mercury-dev-github-actions"
```

### 2. Configure the GitHub repo

In the repo's Settings:

- **Secrets** → New repository secret:
  - `AWS_ROLE_TO_ASSUME` = the `github_actions_role_arn` output
- **Variables** → New repository variable:
  - `AWS_REGION` = your region (matches the Terraform output)
  - `CODEBUILD_PROJECT_NAME` = the `codebuild_project_name` output
- **Actions** → General → set Workflow permissions to "Read repository
  contents and packages permissions" (id-token write is granted per-workflow).

### 3. Vivado licensing (the hard part)

CodeBuild's default Linux image does NOT include Vivado, and Vivado is
licensed software. There are three supported paths for the synth job:

**Path A — Build a custom CodeBuild image (recommended for repeated builds).**
On the AWS FPGA Developer AMI, build a Docker image containing Vivado and
the HDK, push to ECR, then set the Terraform variable:

```bash
terraform apply -var codebuild_image="<acct>.dkr.ecr.<region>.amazonaws.com/mercury-fpga-build:latest"
```

**Path B — Use an EC2 instance from the FPGA Developer AMI directly.**
Skip CodeBuild entirely for the synthesis step. Launch an instance, SSH in,
and run `hw/aws_f1/build/scripts/build_afi.sh` by hand. The S3 bucket and
IAM artifacts from this Terraform are still useful for storing the DCP.

**Path C — Use AWS Image Builder.** Produce a Vivado-bearing AMI on a
schedule, then run an EC2 task instead of CodeBuild. Best for teams.

The Terraform here defaults to Path A's *plumbing* (CodeBuild project, IAM,
S3) without the *image* (you must supply it). The `synth.yml` buildspec has
an explicit `vivado -version` gate that fails fast if Vivado isn't on PATH,
so you get a clear "build the image first" error rather than a confusing
mid-synthesis failure.

## What runs when

| Event | Workflow | What it does | Cost |
|---|---|---|---|
| PR opened / push to main | `conformance.yml` | cargo test, both `conformance.sh` gates, both `cl_conformance.sh` gates | $0 |
| Manual "Run workflow" → synth | `synth.yml` | AWS OIDC, start CodeBuild, optionally wait | minutes of GHA + CodeBuild |

The PR gate must pass before triggering a synth run. Don't burn synthesis
hours on a broken bit-serial datapath.

## Optional: Graviton self-hosted runner

```bash
terraform apply -var enable_graviton_runner=true
```

This is **off by default**. GitHub-hosted runners are adequate for the
Mercury workload (the full conformance matrix runs in under a minute). The
Graviton runner exists as scaffolding for two reasons:

1. **Perf-per-watt** — t4g.small is Landauer-friendlier than equivalent
   x86, which is thematically consistent with Mercury's energy-aware
   framing.
2. **Self-hosted patterns** — if the test matrix grows to include longer
   FPGA-emulated runs, having a configured runner saves the next iteration.

Production teams should use ephemeral runners (Actions Runner Controller
on EKS) rather than this long-lived instance. Register the runner manually
via SSM Session Manager after the instance comes up:

```bash
aws ssm start-session --target $(terraform output -raw graviton_runner_instance_id)
# inside the session:
sudo su - ec2-user
mkdir actions-runner && cd actions-runner
curl -o actions-runner.tar.gz -L https://github.com/actions/runner/releases/download/v2.319.1/actions-runner-linux-arm64-2.319.1.tar.gz
tar xzf actions-runner.tar.gz
./config.sh --url https://github.com/<owner>/mercury --token <one-time-token-from-github>
sudo ./svc.sh install
sudo ./svc.sh start
```

## Verification

Both validators run cleanly against the Phase 4 commit:

```bash
cd infra/terraform && terraform fmt -check && terraform validate
actionlint .github/workflows/*.yml
```

The state of the world after `terraform apply`:

- Buckets exist, versioned, encrypted, public-access-blocked.
- IAM roles trust only the configured GitHub repo's OIDC subject.
- CodeBuild project exists but has never run.
- No EC2 instances unless `enable_graviton_runner=true`.

What `terraform apply` does NOT do, by design:

- Trigger any synthesis runs.
- Upload any artifacts to S3.
- Register any AFIs.

Those actions are explicit: open the Actions tab → Run workflow → synth.

## Tearing it all down

```bash
terraform destroy
```

S3 buckets with objects refuse to delete by default; either set
`force_destroy = true` on the buckets first (and re-apply), or empty them
through the console / `aws s3 rm --recursive` first. AFIs registered to
your account are not managed by this Terraform and must be deregistered
separately with `aws ec2 delete-fpga-image`.

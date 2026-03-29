# Hybrid AI DevOps Pipeline

A production-grade Infrastructure-as-Code pipeline combining GitHub Copilot
custom agents, Claude Code, and Digger to deploy AWS resources from
plain-English requirements — with zero always-on servers and three explicit
human approval gates.

```
You write PR → tf-requirement (Copilot) validates spec
  → You approve → @claude implements HCL
    → CI auto-repairs failures (safeguarded)
      → tf-reviewer (Copilot) gates security + cost
        → digger plan → You review → digger apply
          → @claude verifies deployment → promote to prod
```

---

## Architecture

| Component | Role | System |
|-----------|------|--------|
| `tf-requirement.agent.md` | Parse PR → validated HCL spec | Copilot |
| `tf-reviewer.agent.md` | Checkov + Infracost security gate | Copilot |
| `claude-code.yml` | @claude mention handler | Claude Code |
| `claude-code-autofix.yml` | CI auto-repair (4 safeguard layers) | Claude Code |
| `terraform.yml` | fmt · validate · tflint · Checkov · Terratest | GitHub Actions |
| `digger.yml` | Terraform plan/apply orchestration | Digger |
| `CLAUDE.md` | Claude Code system prompt + Terraform rules | — |

**Zero always-on infrastructure.** Everything runs on ephemeral GitHub Actions
runners. Terraform state lives in S3 + DynamoDB (created by the bootstrap
module, ~$0.05/month). OIDC authentication — no static AWS credentials stored.

---

## Prerequisites

| Tool | Version |
|------|---------|
| Terraform / OpenTofu | ≥ 1.6 |
| GitHub Copilot | Business or Enterprise |
| AWS CLI | v2 |
| Go (Terratest) | ≥ 1.22 |
| gh CLI | latest |

---

## Setup

### 1 — Bootstrap Terraform state (run once per AWS account)

```bash
cd terraform/bootstrap

# Dev account
AWS_PROFILE=dev terraform apply \
  -var="env=dev" \
  -var="github_repo=your-org/your-repo"

# Prod account
AWS_PROFILE=prod terraform apply \
  -var="env=prod" \
  -var="github_repo=your-org/your-repo"
```

Copy the outputs — you need:
- `state_bucket_name` → `TF_STATE_BUCKET`
- `lock_table_name`   → `TF_LOCK_TABLE`
- `github_actions_role_arn` → role ARN for each account

### 2 — Set GitHub Actions variables and secrets

**Settings → Secrets and variables → Actions → Variables:**
```
AWS_DEV_ACCOUNT_ID   = 111111111111
AWS_PROD_ACCOUNT_ID  = 222222222222
AWS_REGION           = us-east-1
TF_STATE_BUCKET      = tf-state-dev-111111111111
TF_LOCK_TABLE        = tf-locks-dev
```

**Settings → Secrets:**
```
DIGGER_TOKEN         = (from digger.dev after installing the GitHub App)
ANTHROPIC_API_KEY    = sk-ant-...
INFRACOST_API_KEY    = ico-...  (free at infracost.io)
```

### 3 — Install Digger GitHub App

Go to https://digger.dev, install the GitHub App on your repo, and copy
the `DIGGER_TOKEN` to your repo secrets.

### 4 — Install Claude Code GitHub App

```bash
# Option A — from your terminal (recommended for Anthropic API users)
claude
/install-github-app

# Option B — manual
# Visit https://github.com/apps/claude and install on your repo
# Then add ANTHROPIC_API_KEY to repo secrets
```

### 5 — Configure MCP servers for Copilot

**Settings → Copilot → MCP servers:**
```json
{
  "mcpServers": {
    "terraform": {
      "command": "npx",
      "args": ["-y", "@hashicorp/terraform-mcp-server"]
    },
    "aws-docs": {
      "command": "uvx",
      "args": ["awslabs.aws-documentation-mcp-server@latest"]
    }
  }
}
```

**Settings → Environments → copilot:**
```
INFRACOST_API_KEY = ico-...
```

### 6 — Configure GitHub Environments

**Settings → Environments:**
- `dev` — no protection rules (auto-deploy on merge)
- `prod` — add Required reviewers (yourself or your team)

### 7 — Create GitHub labels

```bash
bash scripts/setup-labels.sh
```

### 8 — Commit and merge

The agent files in `.github/agents/` appear in the Copilot dropdown
immediately after merging to the default branch.

---

## Using the pipeline

### Deploy a new AWS resource

1. **Open a PR** using the `terraform_resource` template:
   ```
   Title: feat: deploy S3 bucket for media uploads

   What: S3 bucket
   Config: versioning on, AES-256 encryption, no public access,
           lifecycle: abort incomplete MPU after 7 days
   Environments: dev and prod
   Outputs: bucket ARN and name to SSM
   ```

2. **tf-requirement agent** activates, queries the Terraform MCP server
   for live provider schemas, and posts a validated HCL spec.

3. **Review the spec.** Click **"Approve & implement"** in the Copilot panel.

4. **Claude Code** implements the Terraform module, runs `terraform validate`
   and `tflint`, and opens a PR to `dev`.

5. **GitHub Actions** runs `fmt → validate → tflint → Checkov → Terratest`.
   If any step fails, Claude Code auto-fixes it silently. If the failure is
   unfixable (IAM, provider version, AWS quota), Claude adds `no-autofix`
   and posts `[needs-human]`.

6. **tf-reviewer agent** posts a Checkov + Infracost report. On a clean
   review it approves the PR and posts `@claude verify...` for post-deploy.

7. Comment `digger plan` → review the output → comment `digger apply`.

8. **Claude Code** verifies the deployed resources and posts a pass/fail
   checklist.

9. **Promote to prod:** Open a PR from `dev` → `main`. GitHub Environment
   approval is required before `digger apply` runs against prod.

### PR comment commands

| Command | Effect |
|---------|--------|
| `digger plan` | Run `terraform plan` for changed projects |
| `digger plan -p dev` | Plan a specific project |
| `digger apply` | Apply after plan review (requires PR approval) |
| `digger unlock` | Release a stuck state lock |
| `@claude <task>` | Ask Claude Code to implement, fix, explain, or verify |

### Auto-fix safeguards

The auto-fix workflow has four protection layers:

| Layer | Mechanism |
|-------|-----------|
| 1 | `--max-turns 10` — hard cap per session |
| 2 | `concurrency: cancel-in-progress: true` — one session per PR |
| 3 | `${{ github.run_attempt }}` — stops after attempt 2, escalates |
| 4 | Error class blocklist — IAM/credentials/quota → escalate, never fix |

Add the `no-autofix` label to any PR to disable auto-fix entirely.
Include `[skip-autofix]` in a commit message to skip auto-fix for that push.

---

## File structure

```
.github/
  agents/
    tf-requirement.agent.md   Copilot: parse PR → validated spec
    tf-reviewer.agent.md      Copilot: Checkov + Infracost gate
  workflows/
    claude-code.yml           Claude Code: @claude mention handler
    claude-code-autofix.yml   Claude Code: CI auto-repair (safeguarded)
    terraform.yml             CI: fmt · validate · tflint · Checkov · Digger · Terratest
  copilot-instructions.md     Global Copilot conventions
  labels.yml                  Label definitions
  PULL_REQUEST_TEMPLATE/
    terraform_resource.md     Structured requirement template
  ISSUE_TEMPLATE/
    autofix-escalation.md     Pre-filled template for Claude escalations

terraform/
  bootstrap/main.tf           One-time: S3 state + DynamoDB lock + OIDC role
  modules/s3/
    main.tf                   S3 module (AWS provider 5.x, all sub-resources separate)
    variables.tf
    outputs.tf
  environments/
    dev/main.tf               Dev root module
    prod/main.tf              Prod root module

tests/
  s3_test.go                  Terratest — live AWS verification
  go.mod

scripts/
  smoke-test.sh               Post-apply AWS CLI smoke tests
  setup-labels.sh             One-time label creation

CLAUDE.md                     Claude Code system prompt
.tflint.hcl                   TFLint rules
.checkov.yaml                 Checkov skip list
.gitignore
digger.yml                    Digger project config + plan/apply hooks
```

---

## Cost

| Component | Cost |
|-----------|------|
| Terraform state (S3 + DynamoDB) | ~$0.05/month |
| Digger (open source) | $0 |
| GitHub Actions | Within existing allowance |
| Claude Code — simple fmt fix | ~$0.02/session |
| Claude Code — module implementation | ~$0.10–$0.35/session |
| Infracost (free tier) | $0 |
| Copilot Business | $19/user/month |

Deployed AWS resources billed at normal AWS rates.

---

## Known gaps (future improvements)

1. **Agent evals** — no golden test set for prompt regression detection
2. **Verification timing** — Claude infers deploy completion from PR timeline;
   a `workflow_run` trigger on Digger's apply job would make this explicit
3. **Drift detection** — manual AWS console changes go undetected;
   integrate Spacelift or a scheduled `terraform plan` job
4. **Scoped IAM permissions** — deploy role has broad permissions;
   tighten with a per-module IAM boundary
5. **OPA policy gate** — run policy-as-code at the spec stage, not just
   post-implementation Checkov

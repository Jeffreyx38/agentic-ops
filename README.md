# Hybrid AI DevOps Pipeline

A production-grade Infrastructure-as-Code pipeline combining GitHub Copilot
custom agents and Claude Code to deploy AWS resources from plain-English
requirements — with zero always-on servers and explicit human approval gates.

```
You write PR → tf-requirement (Copilot) validates spec
  → You approve → @claude implements HCL
    → CI: fmt · validate · tflint · plan
      → tf-reviewer (Copilot) gates cost
        → Merge to dev → terraform apply (auto)
          → @claude verifies deployment
            → Promote to prod (requires approval)
```

---

## Architecture

| Component | Role | System |
|-----------|------|--------|
| `tf-requirement.agent.md` | Parse PR → validated HCL spec | Copilot |
| `tf-reviewer.agent.md` | Infracost cost gate | Copilot |
| `claude-code.yml` | @claude mention handler | Claude Code |
| `claude-code-autofix.yml` | CI auto-repair (4 safeguard layers) | Claude Code |
| `terraform.yml` | fmt · validate · tflint · plan · apply | GitHub Actions |
| `CLAUDE.md` | Claude Code system prompt + Terraform rules | — |

**Zero always-on infrastructure.** Everything runs on ephemeral GitHub Actions
runners. Terraform state lives in S3 + DynamoDB (created by the bootstrap
module, ~$0.05/month). OIDC authentication — no static AWS credentials stored.

---

## Prerequisites

| Tool | Version |
|------|---------|
| Terraform | ≥ 1.6 |
| GitHub Copilot | Business or Enterprise |
| AWS CLI | v2 |
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
ANTHROPIC_API_KEY    = sk-ant-...
INFRACOST_API_KEY    = ico-...  (free at infracost.io)
```

### 3 — Install Claude Code GitHub App

```bash
# Option A — from your terminal
claude
/install-github-app

# Option B — manual
# Visit https://github.com/apps/claude and install on your repo
# Then add ANTHROPIC_API_KEY to repo secrets
```

### 4 — Configure MCP servers for Copilot

**Settings → Copilot → Coding agent → MCP servers:**

> **Requirement:** Docker must be installed and running. The official HashiCorp
> deployment method uses the `hashicorp/terraform-mcp-server` Docker image.
> Both the Settings JSON (for the outer Copilot session) and the agent file
> `mcp-servers:` config (for the tf-requirement subagent) must use Docker —
> if they are mismatched the subagent will fail to connect.

```json
{
  "mcpServers": {
    "terraform-mcp": {
      "type": "stdio",
      "command": "docker",
      "args": ["run", "-i", "--rm", "hashicorp/terraform-mcp-server"],
      "env": {},
      "tools": ["search_providers", "get_provider_details", "get_latest_provider_version", "search_modules", "get_module_details"]
    },
    "aws-docs": {
      "type": "stdio",
      "command": "uvx",
      "args": ["awslabs.aws-documentation-mcp-server@latest"],
      "env": {},
      "tools": ["search_documentation", "read_documentation", "recommend"]
    }
  }
}
```

> **Note:** The `tools` field is required by the GitHub Copilot agent runtime
> schema — omitting it causes `Invalid config: "mcp-servers.<server>.tools" is
> required` and the agent will not load.

**Settings → Environments → copilot:**
```
INFRACOST_API_KEY = ico-...
```

### 5 — Configure GitHub Environments

**Settings → Environments:**
- `dev` — no protection rules (auto-deploy on merge to dev)
- `prod` — add Required reviewers (yourself or your team), branch: main only

### 6 — Create GitHub labels

```bash
bash scripts/setup-labels.sh
```

### 7 — Merge agents to main

The agent files in `.github/agents/` appear in the Copilot dropdown
immediately after merging to the default branch.

---

## Using the pipeline

### Deploy a new AWS resource

1. **Open a PR** to `dev` using the `terraform_resource` template:
   ```
   Title: feat: deploy S3 bucket for application logs

   What: S3 bucket
   Config: versioning on, AES-256 encryption, no public access,
           lifecycle: expire objects after 90 days
   Environments: dev and prod
   Outputs: bucket ARN and name to SSM
   ```

2. **Trigger tf-requirement agent** — two ways to invoke it:
   - **Assignees sidebar** — select `tf-requirement` in the PR's right panel
   - **PR comment** — post `@copilot using the tf-requirement agent, analyze this PR and post a validated Terraform spec`

   The agent connects to the Terraform MCP server for live provider schema
   verification and posts a validated HCL spec as a PR comment.

3. **Review the spec.** Comment `@claude Implement the Terraform spec from
   the requirement-validated comment above.` to trigger implementation.

4. **Claude Code** implements the Terraform module, runs `terraform fmt`,
   `validate`, and `tflint`, and commits to the PR branch.

5. **GitHub Actions** runs `validate → plan`. The plan output is posted
   as a PR comment. If any step fails, Claude Code auto-fixes it.

6. **Review the plan**, approve the PR, and merge to `dev`.

7. **terraform apply runs automatically** on merge to `dev`.

8. **Claude Code verifies** — comment `@claude verify the deployed resources`
   and it checks the deployed resources against the spec.

9. **Promote to prod** — open a PR from `dev` → `main`. GitHub Environment
   protection requires your approval before the prod apply runs.

### PR comment commands

| Command | Effect |
|---------|--------|
| `@claude <task>` | Ask Claude Code to implement, fix, explain, or verify |
| `@claude verify the deployed resources` | Post-deploy assertion checklist |

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

## Running Terratest manually

Terratest is not run in CI — it deploys real AWS resources and is too slow
and expensive for every PR. Run it manually when making significant changes
to a module:

```bash
# Prerequisites: AWS credentials with dev account access
export AWS_PROFILE=dev
export AWS_DEFAULT_REGION=us-east-1
export TF_STATE_BUCKET=tf-state-dev-<account_id>
export TF_LOCK_TABLE=tf-locks-dev

cd tests
go mod tidy
go test -v -timeout 30m -run TestS3Module ./...
```

The test deploys the S3 module with a random `test-<id>` name prefix,
asserts versioning, encryption, public access block, lifecycle rules, and
SSM parameters, then destroys everything. It uses the `test` environment
which satisfies the module's `env` validation rule.

**When to run Terratest:**
- Adding a new module for the first time
- Changing module validation logic or IAM boundaries
- After a major AWS provider version bump

**When not to run Terratest:**
- Simple bug fixes or description updates
- Environment wiring changes (adding a new module call)
- Anything where `terraform validate` + plan output is sufficient

---

## File structure

```
.github/
  agents/
    tf-requirement.agent.md   Copilot: parse PR → validated spec
    tf-reviewer.agent.md      Copilot: Infracost cost gate
  workflows/
    claude-code.yml           Claude Code: @claude mention handler
    claude-code-autofix.yml   Claude Code: CI auto-repair (safeguarded)
    terraform.yml             CI: fmt · validate · tflint · plan · apply
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
  s3_test.go                  Terratest — run manually, not in CI
  go.mod

scripts/
  smoke-test.sh               Post-apply AWS CLI smoke tests
  setup-labels.sh             One-time label creation

CLAUDE.md                     Claude Code system prompt
.tflint.hcl                   TFLint rules
.gitignore
```

---

## Cost

| Component | Cost |
|-----------|------|
| Terraform state (S3 + DynamoDB) | ~$0.05/month |
| GitHub Actions | Within existing allowance |
| Claude Code — simple fmt fix | ~$0.02/session |
| Claude Code — module implementation | ~$0.10–$0.35/session |
| Infracost (free tier) | $0 |
| Copilot Business | $19/user/month |

Deployed AWS resources billed at normal AWS rates.

---

## Known gaps (future improvements)

1. **Drift detection** — manual AWS console changes go undetected;
   add a scheduled `terraform plan` job
2. **Scoped IAM permissions** — deploy role has broad permissions;
   tighten with a per-module IAM boundary
3. **Multi-account state** — both dev and prod currently share the same
   state bucket; separate state buckets per account for stricter isolation
4. **Agent evals** — no golden test set for tf-requirement prompt regression

---

## Troubleshooting

### terraform-mcp MCP server fails to start

**Symptom:** `MCP server failed to start: MCP error -32000: Connection closed`
in the Agents tab when tf-requirement runs.

**Cause:** The `npx`-based launcher crashes on startup in the Copilot agent
sandbox. The official HashiCorp deployment method is Docker.

**Fix:** Ensure both the Settings JSON **and** the agent file use Docker:

- Settings → Copilot → Coding agent → MCP servers → use `"command": "docker"`
  with `"args": ["run", "-i", "--rm", "hashicorp/terraform-mcp-server"]`
- `.github/agents/tf-requirement.agent.md` `mcp-servers.terraform-mcp` →
  same Docker config

Both must match. If Settings JSON uses `npx` and the agent file uses Docker
(or vice versa), the subagent will fail even though the outer session connects.

### tf-requirement agent shows "Invalid config"

**Symptom:** Assignees sidebar shows
`Invalid config: "mcp-servers.<server>.tools" is required`

**Fix:** The `tools:` array is **required** in the agent file's `mcp-servers`
config. Do not remove it, even if you think it's optional.

### @copilot comment falls through to outer session

**Symptom:** Log shows `Proceeding without custom agent` — the outer Copilot
session handles the request instead of invoking tf-requirement.

**Cause:** The outer session sometimes handles the request directly rather than
delegating to the subagent. Both paths now produce a spec, but only the
subagent path uses the Terraform MCP server for live schema verification.
# Copilot instructions — Terraform pipeline

Applies to every Copilot response in this repository.

## Architecture

Two AI systems with distinct roles:

**Copilot custom agents** (structured approval gates):
- `tf-requirement` — parses PRs, validates specs, presents human approval
- `tf-reviewer` — cost and quality gate

**Claude Code** (@claude mentions + auto-fix):
- Implements Terraform modules after human approval
- Auto-fixes CI failures (fmt, validate, tflint)
- Responds to reviewer comments automatically
- Verifies deployed resources post-deploy

Copilot agents = structured gating. Claude Code = reactive implementation.
Never suggest implementing code via a Copilot agent.

## Pipeline flow

1. PR opened → tf-requirement agent validates spec → human approves
2. @claude implements module → CI runs fmt/validate/tflint/plan
3. Plan output posted as PR comment for review
4. PR merged to dev → terraform apply runs automatically
5. PR merged to main → terraform apply runs with human approval gate (GitHub Environment)

## AWS provider 5.x — separate resources (never inline blocks)

- `aws_s3_bucket_versioning`
- `aws_s3_bucket_server_side_encryption_configuration`
- `aws_s3_bucket_public_access_block`
- `aws_s3_bucket_lifecycle_configuration`
- `aws_s3_bucket_policy`

## Naming: `{env}-{service}-{resource_type}` — lowercase, hyphens

## Mandatory tags on every resource
```hcl
tags = merge(var.tags, {
  Environment = var.env
  ManagedBy   = "terraform-pipeline"
})
```

## Security defaults
- S3: block all public access, AES256, HTTPS-only policy
- IAM: no `*` in Action + Resource together
- No 0.0.0.0/0 on port 22, 3389, or database ports

## State safety
- `for_each` over `count` for collections
- `moved {}` blocks on every rename/refactor
- `lifecycle { prevent_destroy = true }` on stateful prod resources

## Module structure
`main.tf` + `variables.tf` + `outputs.tf` — all three required.
All variables: `type` + `description`. All outputs: `description`.

## SSM exports
`/app/{env}/{service}/{output_name}` via `aws_ssm_parameter`.

## Never do
- `terraform apply` or `terraform destroy`
- Hardcode AWS account IDs or regions
- Inline blocks deprecated in AWS provider 5.x
- `count` for resources that have a `for_each` alternative
- Modify backend state configuration
- Push directly to `main` or `dev`
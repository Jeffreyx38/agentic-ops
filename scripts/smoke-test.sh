#!/usr/bin/env bash
# scripts/smoke-test.sh — post-apply AWS CLI verification
# Usage: bash scripts/smoke-test.sh <env>

set -euo pipefail

ENV=${1:-dev}
REGION=${AWS_DEFAULT_REGION:-us-east-1}
PASS=0; FAIL=0

ok()  { echo "  PASS  $1"; ((PASS++)); }
err() { echo "  FAIL  $1"; ((FAIL++)); }

echo ""
echo "Smoke test — env: $ENV"
echo "─────────────────────"

TF_OUT="/tmp/tf-outputs-${ENV}.json"
if [[ ! -f "$TF_OUT" ]]; then
  cd "terraform/environments/$ENV"
  terraform output -json > "$TF_OUT"
  cd - > /dev/null
fi

BUCKET=$(jq -r '.media_bucket_name.value // empty' "$TF_OUT" 2>/dev/null || echo "")

if [[ -z "$BUCKET" ]]; then
  echo "No bucket output found — skipping S3 checks"
else
  aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null \
    && ok "Bucket $BUCKET exists" || err "Bucket $BUCKET not found"

  STATUS=$(aws s3api get-bucket-versioning --bucket "$BUCKET" --region "$REGION" \
    --query "Status" --output text 2>/dev/null || echo "error")
  [[ "$STATUS" == "Enabled" ]] && ok "Versioning enabled" || err "Versioning not enabled ($STATUS)"

  BLOCK=$(aws s3api get-public-access-block --bucket "$BUCKET" --region "$REGION" \
    --query "PublicAccessBlockConfiguration.BlockPublicAcls" --output text 2>/dev/null || echo "false")
  [[ "$BLOCK" == "True" ]] && ok "Public access blocked" || err "Public access NOT blocked"

  SSM_PATH="/app/$ENV/s3/media-bucket-arn"
  aws ssm get-parameter --name "$SSM_PATH" --region "$REGION" \
    --query "Parameter.Value" --output text > /dev/null 2>&1 \
    && ok "SSM $SSM_PATH exists" || err "SSM $SSM_PATH missing"
fi

echo ""
echo "$((PASS + FAIL)) checks: $PASS passed, $FAIL failed"
[[ "$FAIL" -gt 0 ]] && { echo "Smoke test FAILED"; exit 1; }
echo "Smoke test PASSED"

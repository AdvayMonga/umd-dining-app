#!/bin/bash
# Update Lambda function code from the files in lambda/.
# Infra (IAM roles, dependency layer, EventBridge schedules) already exists;
# this only ships code. Requires credentials for AWS account 296433594974,
# e.g.:  AWS_PROFILE=umd-prod ./scripts/deploy.sh [scraper|embedding|all]
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="${1:-all}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

deploy() {
  local fn="$1"; shift
  zip -q -j "$TMP/$fn.zip" "$@"
  aws lambda update-function-code --function-name "$fn" \
    --zip-file "fileb://$TMP/$fn.zip" \
    --query '{Function:FunctionName,Sha:CodeSha256}' --output json
  aws lambda wait function-updated --function-name "$fn"
  echo "✓ $fn updated"
}

case "$TARGET" in
  scraper)   deploy umd-dining-scraper handler.py scraper_core.py ;;
  embedding) deploy umd-dining-embedding-worker embedding_handler.py embeddings.py ;;
  all)       deploy umd-dining-scraper handler.py scraper_core.py
             deploy umd-dining-embedding-worker embedding_handler.py embeddings.py ;;
  *) echo "usage: deploy.sh [scraper|embedding|all]"; exit 1 ;;
esac

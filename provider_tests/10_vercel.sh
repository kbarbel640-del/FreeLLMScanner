#!/usr/bin/env bash
# vercel.sh — Vercel AI Gateway Provider Test
# Endpoint: https://ai-gateway.vercel.sh/v1
# API key: VERCEL_API_KEY
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_lib.sh"

PROVIDER="vercel"
BASE="https://ai-gateway.vercel.sh/v1"
CHAT_URL="$BASE/chat/completions"
MODEL_URL="$BASE/models"
TOML="$SCRIPT_DIR/../agents/vercel.toml"

API_KEY_ENV=$(toml_get "$TOML" "api_key_env")
API_KEY=$(resolve_api_key "$API_KEY_ENV")

# Free: API-Pricing (0-0) oder -free/-:free-Suffix; Fallback statisch.
free_models() {
  local key="${1:-}"
  local out
  out=$(api_free_table "$MODEL_URL" "$key" | awk -F'|' '$2=="TRUE" || $1 ~ /-free|:free|free$/ {print $1}')
  if [[ -z "$out" ]]; then
    cat <<'EOF'
openai/gpt-oss-20b
mistral/ministral-8b
mistral/codestral
EOF
  else
    echo "$out"
  fi
}

free_status() { default_free_status "$1"; }
test_one() { test_model "$CHAT_URL" "$1" "$API_KEY"; }

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_module_tests
fi
#!/usr/bin/env bash
# openrouter.sh — OpenRouter Provider Test
# Endpoint: https://openrouter.ai/api/v1
# API key: OPENROUTER_API_KEY
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_lib.sh"

PROVIDER="openrouter"
BASE="https://openrouter.ai/api/v1"
CHAT_URL="$BASE/chat/completions"
MODEL_URL="$BASE/models"
TOML="$SCRIPT_DIR/../agents/openrouter.toml"

API_KEY_ENV=$(toml_get "$TOML" "api_key_env")
API_KEY=$(resolve_api_key "$API_KEY_ENV")

# Free: API-Pricing (0-0) oder :free-Suffix; Fallback statisch.
free_models() {
  local key="${1:-}"
  local out
  out=$(api_free_table "$MODEL_URL" "$key" | awk -F'|' '$2=="TRUE" || $1 ~ /:free/ {print $1}')
  if [[ -z "$out" ]]; then
    cat <<'EOF'
openai/gpt-oss-120b:free
meta-llama/llama-3.3-70b-instruct:free
google/gemma-4-31b-it:free
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
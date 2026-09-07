#!/usr/bin/env bash
# kilo.sh — Kilo AI Provider Test
# Endpoint: https://api.kilo.ai/api/gateway
# API key: KILO_API_KEY
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_lib.sh"

PROVIDER="kilo"
BASE="https://api.kilo.ai/api/gateway"
CHAT_URL="$BASE/v1/chat/completions"
MODEL_URL="$BASE/v1/models"
TOML="$SCRIPT_DIR/../agents/kilo.toml"

API_KEY_ENV=$(toml_get "$TOML" "api_key_env")
API_KEY=$(resolve_api_key "$API_KEY_ENV")

# Free: API-Pricing (isFree/0-0) oder :free-Suffix; Fallback statisch.
free_models() {
  local key="${1:-}"
  local out
  out=$(api_free_table "$MODEL_URL" "$key" | awk -F'|' '$2=="TRUE" || $1 ~ /:free/ {print $1}')
  if [[ -z "$out" ]]; then
    cat <<'EOF'
kilo-auto/free
stepfun/step-3.7-flash:free
nvidia/nemotron-3-ultra-550b-a55b:free
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
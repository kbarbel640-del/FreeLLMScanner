#!/usr/bin/env bash
# cloudflare.sh — Cloudflare Workers AI Provider Test
# Endpoint: https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/v1
# API key: CLOUDFLARE_API_KEY

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_lib.sh"

PROVIDER="cloudflare"
# Account ID aus TOML hardcoded
ACCOUNT_ID="5d475b73c61f6fb8cee10424e8511065"
BASE="https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/ai/v1"
CHAT_URL="$BASE/chat/completions"
MODEL_URL="$BASE/models"

TOML="$SCRIPT_DIR/../.files/agents/cloudflare.toml"
API_KEY_ENV=$(toml_get "$TOML" "api_key_env")
API_KEY=$(resolve_api_key "$API_KEY_ENV")

echo "Provider: $PROVIDER"
echo "API Key: ${API_KEY:+(set) $API_KEY_ENV}"
echo ""

if [[ -z "$API_KEY" ]]; then
  echo "SKIP — $API_KEY_ENV not set"
  exit 0
fi

echo "=== Free Models ==="
FREE_MODELS=(
  "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
  "@cf/qwen/qwen3-30b-a3b-fp8"
  "@cf/meta/llama-4-scout-17b-16e-instruct"
)

for model in "${FREE_MODELS[@]}"; do
  printf "  %-50s " "$model"
  result=$(test_model "$CHAT_URL" "$model" "$API_KEY")
  if [[ -z "$result" ]]; then
    fail
  else
    echo "OK"
  fi
done
echo ""

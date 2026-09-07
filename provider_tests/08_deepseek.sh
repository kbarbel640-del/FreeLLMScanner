#!/usr/bin/env bash
# deepseek.sh — DeepSeek Provider Test
# Endpoint: https://api.deepseek.com
# API key: DEEPSEEK_API_KEY

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_lib.sh"

PROVIDER="deepseek"
BASE="https://api.deepseek.com"
CHAT_URL="$BASE/chat/completions"
MODEL_URL="$BASE/models"

TOML="$SCRIPT_DIR/../.files/agents/deepseek.toml"
API_KEY_ENV=$(toml_get "$TOML" "api_key_env")
API_KEY=$(resolve_api_key "$API_KEY_ENV")

echo "Provider: $PROVIDER"
echo "API Key: ${API_KEY:+(set) $API_KEY_ENV}"
echo ""

if [[ -z "$API_KEY" ]]; then
  echo "SKIP — $API_KEY_ENV not set"
  exit 0
fi

# DeepSeek hat keine echten free modelle
echo "=== Available Models ==="
FREE_MODELS=(
  "deepseek-v4-flash"
  "deepseek-v4-pro"
)

for model in "${FREE_MODELS[@]}"; do
  printf "  %-25s " "$model"
  result=$(test_model "$CHAT_URL" "$model" "$API_KEY")
  if [[ -z "$result" ]]; then
    fail
  else
    echo "OK"
  fi
done
echo ""

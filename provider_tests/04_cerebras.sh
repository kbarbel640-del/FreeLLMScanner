#!/usr/bin/env bash
# cerebras.sh — Cerebras Provider Test
# Endpoint: https://api.cerebras.ai/v1
# API key: CEREBRAS_API_KEY

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_lib.sh"

PROVIDER="cerebras"
BASE="https://api.cerebras.ai/v1"
CHAT_URL="$BASE/chat/completions"
MODEL_URL="$BASE/models"

TOML="$SCRIPT_DIR/../.files/agents/cerebras.toml"
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
  "zai-glm-4.7"
  "gemma-4-31b"
  "gpt-oss-120b"
)

for model in "${FREE_MODELS[@]}"; do
  printf "  %-40s " "$model"
  result=$(test_model "$CHAT_URL" "$model" "$API_KEY")
  if [[ -z "$result" ]]; then
    fail
  else
    echo "OK"
  fi
done
echo ""

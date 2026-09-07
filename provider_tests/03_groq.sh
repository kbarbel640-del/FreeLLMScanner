#!/usr/bin/env bash
# groq.sh — Groq Provider Test
# Endpoint: https://api.groq.com/openai/v1
# API key: GROQ_API_KEY

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_lib.sh"

PROVIDER="groq"
BASE="https://api.groq.com/openai/v1"
CHAT_URL="$BASE/chat/completions"
MODEL_URL="$BASE/models"

TOML="$SCRIPT_DIR/../.files/agents/groq.toml"
API_KEY_ENV=$(toml_get "$TOML" "api_key_env")
API_KEY=$(resolve_api_key "$API_KEY_ENV")

echo "Provider: $PROVIDER"
echo "API Key: ${API_KEY:+(set) $API_KEY_ENV}"
echo ""

if [[ -z "$API_KEY" ]]; then
  echo "SKIP — $API_KEY_ENV not set"
  exit 0
fi

# Free models — Groq hat keine :free suffix, preise checken
echo "=== All Models from API ==="
models=$(fetch_models "$MODEL_URL" "$API_KEY")
count=$(echo "$models" | wc -l)
echo "Total: $count"
echo ""

echo "=== Free Models ==="
for mid in $models; do
  echo "  $mid"
done
echo ""

echo "=== Testing Free Models ==="
FREE_MODELS=(
  "llama-3.3-70b-versatile"
  "llama-3.1-8b-instant"
  "qwen/qwen3-32b"
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

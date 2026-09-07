#!/usr/bin/env bash
# nvidia.sh — NVIDIA NIM Provider Test
# Endpoint: https://integrate.api.nvidia.com/v1
# API key: NVIDIA_API_KEY

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_lib.sh"

PROVIDER="nvidia"
BASE="https://integrate.api.nvidia.com/v1"
CHAT_URL="$BASE/chat/completions"
MODEL_URL="$BASE/models"

TOML="$SCRIPT_DIR/../.files/agents/nvidia.toml"
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
  "nvidia/nemotron-3-super-120b-a12b"
  "nvidia/nemotron-3-ultra-550b-a55b"
  "nvidia/nemotron-3-nano-30b-a3b"
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

#!/usr/bin/env bash
# mistral.sh — Mistral AI Provider Test
# Endpoint: https://api.mistral.ai/v1
# API key: MISTRAL_API_KEY
#
# Mistral "Free Mode": ratenlimitierte Zugriff auf ALLE aktuellen (nicht-deprecated)
# Chat/Code-Modelle im enthaltenen Monatskontingent. Es gibt keine separate
# "nur-kostenlos"-Modellliste — die Beschränkung liegt im Volumen, nicht im Modell.
#
# Autoritativ ist die Ausgabe von /v1/models für den konkreten Schlüssel.
# Hier gefiltert auf capabilities.completion_chat == true (Embeddings, OCR,
# Moderation und Audio-Modelle werden übersprungen — sie laufen nicht über
# /chat/completions).
#
# Deprecated-Modelle (devstral, pixtral, magistral, mistral-nemo etc.) liefert
# die API für diesen Schlüssel nicht mehr; dadurch beschränkt sich die Liste
# automatisch auf die aktuellen Modelle.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_lib.sh"

PROVIDER="mistral"
BASE="https://api.mistral.ai/v1"
CHAT_URL="$BASE/chat/completions"
MODEL_URL="$BASE/models"

TOML="$SCRIPT_DIR/../agents/mistral.toml"
API_KEY_ENV=$(toml_get "$TOML" "api_key_env")
API_KEY=$(resolve_api_key "$API_KEY_ENV")

echo "Provider: $PROVIDER"
echo "API Key: ${API_KEY:+(set) $API_KEY_ENV}"
echo ""

if [[ -z "$API_KEY" ]]; then
  echo "SKIP — $API_KEY_ENV not set"
  exit 0
fi

echo "=== Chat-fähige Modelle (Free Mode) ==="
CHAT_MODELS=()
while IFS= read -r m; do
  [[ -n "$m" ]] && CHAT_MODELS+=("$m")
done < <(curl_get "$MODEL_URL" "$API_KEY" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for m in d.get('data', []):
        if m.get('capabilities', {}).get('completion_chat') is True:
            print(m['id'])
except Exception:
    pass
")

if [[ ${#CHAT_MODELS[@]} -eq 0 ]]; then
  echo "  Keine Chat-Modelle von $MODEL_URL ermittelbar"
  exit 0
fi

echo "  ${#CHAT_MODELS[@]} Modelle ($MODEL_URL). Test ratelimit-freundlich (~1 req/s):"
echo ""
for model in "${CHAT_MODELS[@]}"; do
  printf "  %-40s " "$model"
  result=$(test_model "$CHAT_URL" "$model" "$API_KEY")
  if [[ "$result" == "OK" ]]; then
    pass
  elif [[ "$result" == ERROR:* ]]; then
    echo -e "${RED}FAIL${NC} (${result#ERROR: })"
  else
    fail
  fi
  sleep 1
done
echo ""
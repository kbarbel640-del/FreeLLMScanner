#!/usr/bin/env bash
# opencode.sh — OpenCode Zen Provider Test
# Endpoint: https://opencode.ai/zen/v1
# Kein API-Key nötig (Authorization: Bearer public), Free-Modelle sind
# User-Agent-Gated: test_zencode in _lib.sh setzt opencode-UA + x-opencode-*.
# Bei Ratenlimit rotiert test_zencode automatisch die IP über den PVPN-Proxy.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_lib.sh"

PROVIDER="opencode"
BASE="https://opencode.ai/zen/v1"
CHAT_URL="$BASE/chat/completions"
MODEL_URL="$BASE/models"
TOML="$SCRIPT_DIR/../agents/opencode.toml"

API_KEY_ENV=""
API_KEY=""

# Free-Modelle aus der API: IDs mit -free/**free-Suffix plus big-pickle.
free_models() {
  local key="${1:-}"
  curl_get "$MODEL_URL" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    for m in d.get('data', []):
        mid=m.get('id','')
        if mid=='big-pickle' or 'free' in mid.lower():
            print(mid)
except Exception: pass
"
}

free_status() { default_free_status "$1"; }

# Chat-Test über das UA-Gate (bearer public + opencode-UA + x-opencode-Header)
test_one() {
  test_zencode "$CHAT_URL" "$1"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_module_tests
fi
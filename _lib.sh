# _lib.sh — Shared functions for provider tests
set -euo pipefail

# Proxy ausschalten (SOCKS5 kann curl bremsen/kaputtmachen)
unset ALL_PROXY
unset HTTP_PROXY
unset HTTPS_PROXY

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}"; }
fail() { echo -e "${RED}FAIL${NC}"; }
skip() { echo -e "${YELLOW}SKIP${NC}"; }
warn() { echo -e "${YELLOW}WARN${NC}: $1"; }

# GET mit timeout, bearer auth
curl_get() {
  local url="$1"
  local token="${2:-}"
  if [[ -n "$token" ]]; then
    curl -s --max-time 20 -H "Authorization: Bearer $token" "$url"
  else
    curl -s --max-time 20 "$url"
  fi
}

# --- OpenCode Zen Free Tier ---
# Free-Modelle laufen ohne API-Key (Authorization: Bearer public), sind aber
# User-Agent-Gated: nur "User-Agent: opencode/<version>" + x-opencode-* Header
# entsperren sie. Bei Ratenlimit/Fehlern wird die IP über den PVPN-Proxy
# gewechselt (PVPN_USER + PVPN_PASS + PVPN_HOSTS, Default: bekannte Hosts).
PVPN_HOSTS="${PVPN_HOSTS:-nl-ams.pvdata.host se-sto.pvdata.host}"
ZPROXY_IDX=0

_zopen_headers() {
  printf '%s\n' \
    -H "Authorization: Bearer public" \
    -H "User-Agent: opencode/1.15.0 ai-sdk/provider-utils/4.0.23 runtime/bun/1.3.13" \
    -H "x-opencode-client: cli" \
    -H "x-opencode-project: global" \
    -H "x-opencode-request: msg_$(date +%s%N)" \
    -H "x-opencode-session: ses_$(date +%s%N)"
}

_zopen_proxy() {
  local hosts=(${PVPN_HOSTS:-})
  if [[ ${#hosts[@]} -eq 0 || -z "${PVPN_USER:-}" || -z "${PVPN_PASS:-}" ]]; then
    echo ""; return 1
  fi
  echo "socks5://${PVPN_USER}:${PVPN_PASS}@${hosts[$((ZPROXY_IDX % ${#hosts[@]}))]}"
}

# Single Chat-Completion für OpenCode Zen Free Tier ($1=url, $2=model, $3=proxy oder leer)
test_zencode_once() {
  local url="$1" model="$2" proxy="$3"
  local proxy_args=()
  [[ -n "$proxy" ]] && proxy_args=(-x "$proxy")
  curl -s --max-time 25 "${proxy_args[@]}" -X POST "$url" \
    -H "Content-Type: application/json" \
    $(_zopen_headers) \
    -d '{"model":"'"$model"'","messages":[{"role":"user","content":"Say exactly: OK"}],"max_tokens":5}' \
    2>/dev/null
}

# Wie test_model, aber für OpenCode Free Tier: erst ohne Proxy; schlägt es fehl
# (Rate-Limit/Upstream), wird über PVPN-Proxy die IP rotiert. Gibt "OK" oder
# "ERROR: <msg>" zurück.
test_zencode() {
  local url="$1" model="$2"
  local hosts=(${PVPN_HOSTS:-})
  local max=1 run=0 body result last_err="ERROR: no response"
  if [[ -n "${PVPN_USER:-}" && -n "${PVPN_PASS:-}" && ${#hosts[@]} -gt 0 ]]; then
    max=$((1 + ${#hosts[@]}))
  fi
  while (( run < max )); do
    run=$((run + 1))
    local proxy=""
    if (( run > 1 )); then
      proxy=$(_zopen_proxy) || break
    fi
    body=$(test_zencode_once "$url" "$model" "$proxy")
    if [[ -z "$body" ]]; then
      ZPROXY_IDX=$((ZPROXY_IDX + 1)); last_err="ERROR: no response"; continue
    fi
    result=$(echo "$body" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    if 'error' in d:
        print('ERROR:', d['error'].get('message','?'))
    else:
        print('OK')
except Exception:
    print('ERROR: unparseable')
" 2>/dev/null | head -1)
    if [[ "$result" == "OK" ]]; then
      echo "OK"; return 0
    fi
    last_err="ERROR: ${result#ERROR: }"
    ZPROXY_IDX=$((ZPROXY_IDX + 1))
  done
  echo "$last_err"
}

# POST chat completion, returns "OK" on success, empty on fail
test_model() {
  local url="$1"
  local model="$2"
  local token="${3:-}"

  local extra_args=()
  if [[ -n "$token" ]]; then
    extra_args+=(-H "Authorization: Bearer $token")
  fi

  local response
  response=$(curl -s --max-time 25 \
    -X POST "$url" \
    -H "Content-Type: application/json" \
    "${extra_args[@]}" \
    -d '{"model":"'"$model"'","messages":[{"role":"user","content":"Say exactly: OK"}],"max_tokens":5}' \
    2>/dev/null)

  echo "$response" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    if 'error' in d:
        print('ERROR:', d['error'].get('message','?'))
    else:
        print('OK')
except:
    print('')
" 2>/dev/null | head -1
}

# Read api_key_env from TOML
toml_get() {
  local toml="$1"
  local key="$2"
  grep "^$key" "$toml" 2>/dev/null | cut -d'"' -f2 || echo ""
}

# Get API key from env var name
resolve_api_key() {
  local var_name="$1"
  if [[ -z "$var_name" ]]; then
    echo ""
    return 0
  fi
  echo "${!var_name:-}"
}

# ---- Modul-Konvention ----
# Jede Provider-Moduldatei (provider_tests/0X_<name>.sh) definiert:
#   free_models(key)      -> zeilenweise IDs der Free-Modelle
#   free_status(id)       -> "free" | "paid" (Default: Membership in free_models)
#   test_one(model)       -> "OK" | "ERROR: <msg>" (Default: test_model)
# plus Provider-Metadaten (PROVIDER, BASE, CHAT_URL, MODEL_URL, API_KEY, ...).
# Bei direkter Ausführung (: standalone) läuft run_module_tests, beim Sourcing nicht.

# Generischer Parser für /models: liefert pro Modell "id|TRUE|FALSE|prompt/comp".
# free = isFree-Feld oder pricing-Dict mit prompt+completion == 0.
# Fehlendes/leeres pricing gilt NICHT als free.
api_free_table() {
  local url="$1" token="${2:-}"
  local auth=()
  [[ -n "$token" ]] && auth=(-H "Authorization: Bearer $token")
  curl -s --max-time 15 "${auth[@]}" "$url" 2>/dev/null | python3 -c "
import json,sys
def fnum(v, d=None):
    if v is None: return d
    if isinstance(v,(int,float)): return float(v)
    s=str(v).strip()
    try: return float(s)
    except ValueError: return d
try:
    d=json.load(sys.stdin)
    data=d.get('data') or d.get('models')
    if data is None and isinstance(d.get('result'), dict):
        data=d['result'].get('models')
    if isinstance(data, list):
        for m in data:
            mid=m.get('id') or m.get('name','')
            free=False; cost='?/?'
            if m.get('isFree') is True: free=True
            p=m.get('pricing')
            if isinstance(p, dict) and p:
                a=fnum(p.get('prompt') or p.get('input'))
                b=fnum(p.get('completion') or p.get('output'))
                if a is not None and b is not None:
                    cost=f'{a:g}/{b:g}'
                    if a==0 and b==0: free=True
            print(f'{mid}|{\"TRUE\" if free else \"FALSE\"}|{cost}')
    elif isinstance(data, dict):
        for k,v in data.items(): print(f'{k}|FALSE|?/?')
except Exception: pass
"
}

# Default-Free-Status: free, wenn id in der moduleigenen free_models-Liste.
default_free_status() {
  if free_models "$API_KEY" 2>/dev/null | grep -qx "$1"; then echo free; else echo paid; fi
}

# Standalone-Runner für Moduldateien (nur bei direkter Ausführung).
run_module_tests() {
  echo "Provider: $PROVIDER"
  echo "API Key: ${API_KEY:+(set) $API_KEY_ENV}"
  echo ""
  if [[ -z "$API_KEY" && "$PROVIDER" != "opencode" ]]; then
    echo "SKIP — $API_KEY_ENV not set"
    exit 0
  fi
  local ms=()
  readarray -t ms < <(free_models "$API_KEY")
  if [[ ${#ms[@]} -eq 0 ]]; then
    echo "  Keine Free-Modelle ermittelbar"
    exit 0
  fi
  echo "=== Free Models (${#ms[@]}) ==="
  for m in "${ms[@]}"; do
    printf "  %-42s " "$m"
    r=$(test_one "$m")
    if [[ "$r" == "OK" ]]; then
      pass
    elif [[ "$r" == ERROR:* ]]; then
      echo -e "${RED}FAIL${NC} (${r#ERROR: })"
    else
      fail
    fi
  done
  echo ""
}

# Fetch model list from /models endpoint
fetch_models() {
  local url="$1"
  local token="${2:-}"
  curl_get "$url" "$token" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    data=d.get('data', d.get('models', d.get('result',{}).get('models', [])))
    if isinstance(data, list):
        for m in data:
            mid=m.get('id', m.get('name',''))
            if mid:
                print(mid)
    elif isinstance(data, dict):
        for k,v in data.items():
            print(k)
except: pass
" 2>/dev/null
}

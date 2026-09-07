# _lib.sh — Shared functions for provider tests
set -euo pipefail

# Lokale .env automatisch laden. Dadurch funktionieren sowohl der Hauptscanner
# als auch die einzelnen provider_tests ohne vorheriges `source .env`.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$LIB_DIR/.env" ]]; then
  set -a
  source "$LIB_DIR/.env"
  set +a
fi

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

# Provider-spezifischen Abstand zwischen Test-Requests ermitteln.
# Beispiel: OPENROUTER_RATE_LIMIT_SECONDS=1.5
provider_rate_limit_seconds() {
  local provider="$1"
  local var
  var="$(printf '%s_RATE_LIMIT_SECONDS' "$provider" | tr '[:lower:]-' '[:upper:]_')"
  printf '%s\n' "${!var:-1}"
}

provider_from_url() {
  case "$1" in
    *opencode.ai*) echo opencode ;;
    *openrouter.ai*) echo openrouter ;;
    *kilo.ai*) echo kilo ;;
    *nvidia.com*) echo nvidia ;;
    *groq.com*) echo groq ;;
    *cerebras.ai*) echo cerebras ;;
    *vercel.sh*) echo vercel ;;
    *deepseek.com*) echo deepseek ;;
    *mistral.ai*) echo mistral ;;
    *cloudflare.com*) echo cloudflare ;;
    *) echo unknown ;;
  esac
}

# Harte Quoten erkennen, bei denen weiteres Testen im selben Lauf keinen Sinn hat.
is_hard_provider_limit() {
  local msg="${1,,}"
  [[ "$msg" == *"free-models-per-day"* || \
     "$msg" == *"daily limit"* || \
     "$msg" == *"daily quota"* || \
     "$msg" == *"per day"* ]]
}

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
# User-Agent-Gated. Die PrivateVPN-Hostnames koennen dynamisch von der Website
# geholt oder in .env als PVPN_HOSTS gesetzt werden.

# Cache-Datei und Gueltigkeitsdauer fuer PVPN-Hosts
PVPN_CACHE_FILE="/tmp/pvpn_hosts_cache"
PVPN_CACHE_SECONDS=${PVPN_CACHE_SECONDS:-3600}  # 1 Stunde Default
PVPN_DEFAULT_HOSTS=(
  ar-bue.pvdata.host
  au-bri.pvdata.host
  au-mel.pvdata.host
  au-per.pvdata.host
  au-syd.pvdata.host
  at-wie.pvdata.host
  be-bru.pvdata.host
  br-sao.pvdata.host
  bg-sof.pvdata.host
  ca-mon.pvdata.host
  ca-tor.pvdata.host
  ca-van.pvdata.host
  cl-san.pvdata.host
  co-bog.pvdata.host
  cr-san.pvdata.host
  hr-zag.pvdata.host
  cy-lim.pvdata.host
  cz-pra.pvdata.host
  dk-cop.pvdata.host
  ee-tal.pvdata.host
  fi-esp.pvdata.host
  fr-par.pvdata.host
  de-ber.pvdata.host
  de-fra.pvdata.host
  gr-ath.pvdata.host
  hk-hon.pvdata.host
  hu-bud.pvdata.host
  is-rey.pvdata.host
  in-ban.pvdata.host
  in-mum.pvdata.host
  id-jak.pvdata.host
  ie-dub.pvdata.host
  im-bal.pvdata.host
  il-tel.pvdata.host
  it-mil.pvdata.host
  jp-tok.pvdata.host
  lv-rig.pvdata.host
  lt-sia.pvdata.host
  lu-lux.pvdata.host
  my-kua.pvdata.host
  mt-qor.pvdata.host
  mx-mex.pvdata.host
  md-chi.pvdata.host
  nl-ams.pvdata.host
  nz-auc.pvdata.host
  ng-lag.pvdata.host
  no-osl.pvdata.host
  pa-pan.pvdata.host
  pe-lim.pvdata.host
  ph-man.pvdata.host
  pl-tor.pvdata.host
  pt-lis.pvdata.host
  ro-buk.pvdata.host
  rs-bel.pvdata.host
  sg-sin.pvdata.host
  sk-bra.pvdata.host
  za-joh.pvdata.host
  kr-seo.pvdata.host
  es-mad.pvdata.host
  se-got.pvdata.host
  se-kis.pvdata.host
  se-sto.pvdata.host
  ch-zur.pvdata.host
  tw-tai.pvdata.host
  th-ban.pvdata.host
  tr-ist.pvdata.host
  ua-nik.pvdata.host
  ae-dub.pvdata.host
  uk-lon.pvdata.host
  uk-man.pvdata.host
  us-atl.pvdata.host
  us-buf.pvdata.host
  us-chi.pvdata.host
  us-dal.pvdata.host
  us-den.pvdata.host
  us-las.pvdata.host
  us-los.pvdata.host
  us-mia.pvdata.host
  us-jer.pvdata.host
  us-nyc.pvdata.host
  us-pho.pvdata.host
  us-sea.pvdata.host
  vn-hoc.pvdata.host
)

# Fetch PVPN hosts from PrivateVPN website
fetch_pvpn_hosts() {
  local url="https://privatevpn.com/serverlist"
  local tmp_file=$(mktemp)

  echo "Fetching latest PVPN hosts from $url..."
  # Use -L to follow redirects, -k to allow insecure if needed
  if ! curl -Lk -s --max-time 15 -A "Mozilla/5.0" "$url" -o "$tmp_file" 2>/dev/null; then
    echo "Warning: Could not fetch PVPN hosts. Using cache or fallback."
    if [[ -f "$PVPN_CACHE_FILE" && -s "$PVPN_CACHE_FILE" ]]; then
      readarray -t PVPN_HOST_ARRAY < "$PVPN_CACHE_FILE"
      return 0
    else
      PVPN_HOST_ARRAY=("${PVPN_DEFAULT_HOSTS[@]}")
      return 1
    fi
  fi

  # Extract hostnames from the HTML using grep -oE
  # The page may redirect to /en/serverlist, so we follow redirects with -L
  local hosts=()
  local all_hosts
  all_hosts=$(grep -oE '[a-z0-9-]+\.pvdata\.host' "$tmp_file" 2>/dev/null | sort -u || true)
  
  if [[ -n "$all_hosts" ]]; then
    # Read into array, filtering empty lines
    while IFS= read -r host; do
      [[ -n "$host" ]] && hosts+=("$host")
    done <<< "$all_hosts"
  fi

  if [[ ${#hosts[@]} -eq 0 ]]; then
    rm -f "$tmp_file"
    echo "Warning: No hosts extracted. Using cache or fallback."
    if [[ -f "$PVPN_CACHE_FILE" && -s "$PVPN_CACHE_FILE" ]]; then
      readarray -t PVPN_HOST_ARRAY < "$PVPN_CACHE_FILE"
      return 0
    else
      PVPN_HOST_ARRAY=("${PVPN_DEFAULT_HOSTS[@]}")
      return 1
    fi
  fi

  # Save to cache
  printf '%s\n' "${hosts[@]}" > "$PVPN_CACHE_FILE"
  touch -d "@$(( $(date +%s) + PVPN_CACHE_SECONDS ))" "$PVPN_CACHE_FILE" 2>/dev/null || true

  PVPN_HOST_ARRAY=("${hosts[@]}")
  rm -f "$tmp_file"
  echo "Fetched ${#hosts[@]} PVPN hosts. Cache saved to $PVPN_CACHE_FILE"
  return 0
}

# Initialize PVPN_HOST_ARRAY
init_pvpn_hosts() {
  # If PVPN_HOSTS is set in .env, use that
  if [[ -n "${PVPN_HOSTS:-}" ]]; then
    read -r -a PVPN_HOST_ARRAY <<< "$PVPN_HOSTS"
    return 0
  fi

  # Check cache (if not older than PVPN_CACHE_SECONDS)
  if [[ -f "$PVPN_CACHE_FILE" && -s "$PVPN_CACHE_FILE" ]]; then
    local current_time=$(date +%s)
    local file_mtime=$(stat -c %Y "$PVPN_CACHE_FILE" 2>/dev/null || echo 0)
    local cache_age=$((current_time - file_mtime))
    if [[ $cache_age -lt $PVPN_CACHE_SECONDS ]]; then
      readarray -t PVPN_HOST_ARRAY < "$PVPN_CACHE_FILE"
      return 0
    fi
  fi

  # Fetch from website
  fetch_pvpn_hosts
}

# Initialize PVPN hosts on script start
init_pvpn_hosts

# Index in einer Datei, weil test_model()/test_zencode() oft in einer
# Command-Substitution laufen und ein Shell-Zähler dort verloren ginge.
_zproxy_idx_file() { echo "/tmp/freellmscanner_$$_zproxy_idx"; }

_zproxy_idx_get() {
  local f idx=0
  f=$(_zproxy_idx_file)
  if [[ -f "$f" ]]; then
    idx=$(<"$f")
    [[ "$idx" =~ ^[0-9]+$ ]] || idx=0
  fi
  echo "$idx"
}

_zproxy_idx_set() {
  echo "$1" > "$(_zproxy_idx_file)"
}

_zproxy_advance() {
  local n="${#PVPN_HOST_ARRAY[@]}"
  (( n > 0 )) || return 0
  _zproxy_idx_set $(( $(_zproxy_idx_get) + 1 ))
}

_zopen_proxy() {
  local hosts=("${PVPN_HOST_ARRAY[@]}")
  local idx
  if [[ ${#hosts[@]} -eq 0 || -z "${PVPN_USER:-}" || -z "${PVPN_PASS:-}" ]]; then
    echo ""; return 1
  fi
  idx=$(_zproxy_idx_get)
  echo "socks5://${PVPN_USER}:${PVPN_PASS}@${hosts[$((idx % ${#hosts[@]}))]}"
}

# Fehler, bei denen ein anderer Exit-Host helfen kann (Ratenlimit, 5xx, Upstream).
is_rotatable_limit() {
  local msg="${1,,}"
  [[ "$msg" == *"rate limit"* || \
     "$msg" == *"too many requests"* || \
     "$msg" == *"try again later"* || \
     "$msg" == *"internal server error"* || \
     "$msg" == *"upstream"* || \
     "$msg" == *"unavailable"* || \
     "$msg" == *"overloaded"* || \
     "$msg" == *"timeout"* || \
     "$msg" == *"temporarily"* || \
     "$msg" == *"bad gateway"* || \
     "$msg" == *"unparseable"* ]]
}

# Single Chat-Completion für OpenCode Zen Free Tier ($1=url, $2=model, $3=proxy oder leer)
test_zencode_once() {
  local url="$1" model="$2" proxy="$3"
  local proxy_args=()
  local header_args=(
    -H "Authorization: Bearer public"
    -H "User-Agent: opencode/1.15.0 ai-sdk/provider-utils/4.0.23 runtime/bun/1.3.13"
    -H "x-opencode-client: cli"
    -H "x-opencode-project: global"
    -H "x-opencode-request: msg_$(date +%s%N)"
    -H "x-opencode-session: ses_$(date +%s%N)"
  )
  [[ -n "$proxy" ]] && proxy_args=(-x "$proxy")
  curl -s --max-time 25 "${proxy_args[@]}" -X POST "$url" \
    -H "Content-Type: application/json" \
    "${header_args[@]}" \
    -d '{"model":"'"$model"'","messages":[{"role":"user","content":"Say exactly: OK"}],"max_tokens":5}' \
    2>/dev/null
}

_zencode_parse() {
  echo "$1" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    if 'error' in d:
        print('ERROR:', d['error'].get('message','?'))
    else:
        print('OK')
except Exception:
    print('ERROR: unparseable')
" 2>/dev/null | head -1
}

# OpenCode ohne Proxy (Fallback, wenn PVPN nicht konfiguriert ist).
test_opencode() {
  local url="$1" model="$2"
  local body
  body=$(test_zencode_once "$url" "$model" "")
  if [[ -z "$body" ]]; then
    echo "ERROR: no response"
    return 0
  fi
  _zencode_parse "$body"
}

# OpenCode-Test mit Round-Robin über die PVPN-Hosts.
# OPENCODE_PROXY_ROUND_ROBIN=0 schaltet die Proxy-Rotation komplett aus.
# Jeder Versuch nimmt den nächsten Host; nach Erfolg/Misserfolg bleibt der
# Zeiger dort, damit der nächste Modelltest nicht dieselbe IP benutzt.
test_zencode() {
  local url="$1" model="$2"

  if [[ "${OPENCODE_PROXY_ROUND_ROBIN:-1}" != "1" ]]; then
    test_opencode "$url" "$model"
    return 0
  fi

  local hosts=("${PVPN_HOST_ARRAY[@]}")
  local max=1 run=0 body result last_err="ERROR: no response" proxy=""
  local cap="${ZPROXY_MAX_TRIES:-12}"
  if [[ -n "${PVPN_USER:-}" && -n "${PVPN_PASS:-}" && ${#hosts[@]} -gt 0 ]]; then
    max=${#hosts[@]}
    (( cap > 0 && cap < max )) && max=$cap
  fi
  while (( run < max )); do
    run=$((run + 1))
    proxy=""
    if [[ -n "${PVPN_USER:-}" && -n "${PVPN_PASS:-}" && ${#hosts[@]} -gt 0 ]]; then
      proxy=$(_zopen_proxy) || break
    fi
    body=$(test_zencode_once "$url" "$model" "$proxy")
    _zproxy_advance
    if [[ -z "$body" ]]; then
      last_err="ERROR: no response"
      continue
    fi
    result=$(_zencode_parse "$body")
    if [[ "$result" == "OK" ]]; then
      echo "OK"; return 0
    fi
    last_err="ERROR: ${result#ERROR: }"
    # Nur bei Ratenlimit/leerer Antwort den nächsten Host versuchen.
    if ! is_rotatable_limit "${result#ERROR: }" && [[ -n "$body" ]]; then
      break
    fi
  done
  echo "$last_err"
}

# POST chat completion. Dieser Pfad wird auch vom Hauptscanner verwendet.
# Deshalb sitzt das Request-Throttling hier und greift automatisch bei
# fetch_free_models.sh --all sowie bei einzelnen Provider-Scans.
test_model() {
  local url="$1"
  local model="$2"
  local token="${3:-}"
  local provider delay marker response result msg

  provider=$(provider_from_url "$url")
  delay=$(provider_rate_limit_seconds "$provider")
  marker="/tmp/freellmscanner_$$_${provider}_hard_limit"

  # Wenn dieser Lauf bereits eine harte Tagesquote getroffen hat, keine
  # weiteren Requests mehr an diesen Provider schicken.
  if [[ -f "$marker" ]]; then
    echo "ERROR: provider daily quota already reached; request skipped"
    return 0
  fi

  # Bewusst vor jedem Test-Request. Dadurch wirkt das auch in Command-
  # Substitutions des Hauptscanners, wo Shell-Zustand sonst verloren ginge.
  sleep "$delay"

  # OpenCode braucht einen eigenen Header-Satz; der generische Bearer-Pfad
  # würde dort die Free-Tier-Requests falsch senden.
  if [[ "$provider" == "opencode" ]]; then
    result=$(test_zencode "$url" "$model")
    if [[ "$result" == ERROR:* ]]; then
      msg="${result#ERROR: }"
      is_hard_provider_limit "$msg" && : > "$marker"
    fi
    echo "$result"
    return 0
  fi

  local extra_args=()
  if [[ -n "$token" ]]; then
    extra_args+=(-H "Authorization: Bearer $token")
  fi

  response=$(curl -s --max-time 25 \
    -X POST "$url" \
    -H "Content-Type: application/json" \
    "${extra_args[@]}" \
    -d '{"model":"'"$model"'","messages":[{"role":"user","content":"Say exactly: OK"}],"max_tokens":5}' \
    2>/dev/null)

  result=$(echo "$response" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    if 'error' in d:
        print('ERROR:', d['error'].get('message','?'))
    else:
        print('OK')
except:
    print('')
" 2>/dev/null | head -1)

  if [[ "$result" == ERROR:* ]]; then
    msg="${result#ERROR: }"
    is_hard_provider_limit "$msg" && : > "$marker"
  fi
  echo "$result"
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
      if is_hard_provider_limit "${r#ERROR: }"; then
        echo "  Provider quota reached — stopping remaining model tests."
        break
      fi
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

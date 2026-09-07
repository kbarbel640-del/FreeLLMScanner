#!/usr/bin/env bash
# fetch_free_models.sh — Dynamischer Free-Modelle-Scanner
#
# Ziel:
# - Keine statischen Modelllisten mehr.
# - Für jeden Provider: /models Endpoint abfragen.
# - Aus der API selbst erkennen, welche Modelle kostenlos sind (basierend auf pricing=0/0 oder :free-Suffix).
# - Nur diese Free-Modelle mit test_model() testen.
# - Bei --check: die dynamisch gefundenen Free-Modelle + Testergebnisse in check_state.json schreiben.
#
# API ist die einzige Source of Truth für Free-Status.
# Wenn Free-Status nicht aus der API erkennbar: "Free status cannot be determined from provider API"
#
# Aufruf:
#   ./fetch_free_models.sh                     → interaktives Menü (scan+test)
#   ./fetch_free_models.sh --all               → alle Provider (scan+test)
#   ./fetch_free_models.sh --no-nvidia         → alle außer nvidia
#   ./fetch_free_models.sh --opencode --kilo   → nur opencode + kilo
#   ./fetch_free_models.sh --list              → nur Listing: zeigt alle Modelle aus API, markiert Free-Modelle
#   ./fetch_free_models.sh --check             → scan + test, schreibt check_state.json und
#                                                 zeigt Alter des letzten Checks je Provider
#   Auswahl-Flags (--all / --<name> / --no-<name>) kombinierbar mit --list / --check
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
TOML_DIR="$BASE/agents"
STATE_FILE="$BASE/check_state.json"
STALE_HOURS=${STALE_HOURS:-24}
STALE_SECS=$((STALE_HOURS * 3600))
source "$BASE/_lib.sh"

# provider|models_url|toml  (chat_url wird abgeleitet: /models -> /chat/completions)
PROVIDERS=(
  "opencode|https://opencode.ai/zen/v1/models|"
  "openrouter|https://openrouter.ai/api/v1/models|openrouter.toml"
  "kilo|https://api.kilo.ai/api/gateway/v1/models|kilo.toml"
  "nvidia|https://integrate.api.nvidia.com/v1/models|nvidia.toml"
  "groq|https://api.groq.com/openai/v1/models|groq.toml"
  "cerebras|https://api.cerebras.ai/v1/models|cerebras.toml"
  "vercel|https://ai-gateway.vercel.sh/v1/models|vercel.toml"
  "deepseek|https://api.deepseek.com/v1/models|deepseek.toml"
  "mistral|https://api.mistral.ai/v1/models|mistral.toml"
  "cloudflare|https://api.cloudflare.com/client/v4/accounts/5d475b73c61f6fb8cee10424e8511065/ai/v1/models|cloudflare.toml"
)

ALL_NAMES=()
for e in "${PROVIDERS[@]}"; do
  IFS='|' read -r n _ _ <<< "$e"
  ALL_NAMES+=("$n")
done

is_provider() {
  local name="$1"
  for n in "${ALL_NAMES[@]}"; do
    [[ "$n" == "$name" ]] && return 0
  done
  return 1
}

# Free-Model-Listen je Provider (aus den Modulen 01-10)
free_models_for() {
  case "$1" in
    opencode)
      echo "big-pickle deepseek-v4-flash-free muse-spark-1.3-contributor-free muse-spark-1.2-contributor-free mimo-v2.5-free ling-3.0-flash-fin-free nemotron-3-ultra-free nemotron-3.5-lightning-free"
      ;;
    openrouter)
      echo "openai/gpt-oss-120b:free meta-llama/llama-3.3-70b-instruct:free google/gemma-4-31b-it:free"
      ;;
    kilo)
      echo "kilo-auto/free stepfun/step-3.7-flash:free nvidia/nemotron-3-ultra-550b-a55b:free"
      ;;
    nvidia)
      echo "nvidia/nemotron-3-super-120b-a12b nvidia/nemotron-3-ultra-550b-a55b nvidia/nemotron-3-nano-30b-a3b"
      ;;
    groq)
      echo "llama-3.3-70b-versatile llama-3.1-8b-instant qwen/qwen3-32b"
      ;;
    cerebras)
      echo "zai-glm-4.7 gemma-4-31b gpt-oss-120b"
      ;;
    vercel)
      echo "openai/gpt-oss-20b mistral/ministral-8b mistral/codestral"
      ;;
    deepseek)
      echo "deepseek-v4-flash deepseek-v4-pro"
      ;;
    mistral)
      # Free Mode = ratenlimitierter Zugriff auf ALLE Chat/Code-Modelle.
      # Quelle/Logik: provider_tests/07_mistral.sh (filtert /v1/models auf
      # capabilities.completion_chat). Diese Liste = Snapshot des Schlüssels.
      echo "codestral-2508 codestral-latest mistral-code-latest mistral-code-fim-latest mistral-small-2603 mistral-small-latest mistral-vibe-cli-fast magistral-small-latest voxtral-small-2507 voxtral-small-latest labs-leanstral-1-5-1 labs-leanstral-1-5 ministral-3b-2512 ministral-3b-latest ministral-8b-2512 ministral-8b-latest ministral-14b-2512 ministral-14b-latest mistral-medium-latest mistral-medium mistral-medium-3-5 mistral-medium-3.5 mistral-medium-3 mistral-medium-2604 mistral-vibe-cli-latest mistral-vibe-cli-with-tools magistral-medium-latest"
      ;;
    cloudflare)
      echo "@cf/meta/llama-3.3-70b-instruct-fp8-fast @cf/qwen/qwen3-30b-a3b-fp8 @cf/meta/llama-4-scout-17b-16e-instruct"
      ;;
    *) echo "" ;;
  esac
}

show_menu() {
  echo "=== Free Model Scanner + Tester ==="
  echo ""
  echo "  0  Run all"
  local i=1
  for n in "${ALL_NAMES[@]}"; do
    printf "  %-2d  %s\n" "$i" "$n"
    i=$((i+1))
  done
  echo ""
  echo "  p  Proxy Settings (fetch/update PVPN hosts)"
  echo "  q  Quit"
  echo ""
}

usage() {
  echo "Usage: $0 [--list|--check] [--all] [--<provider>...] [--no-<provider>...]"
  echo ""
  echo "  (no args)          interactive menu (scan + test)"
  echo "  --list             nur Listing: zeigt pro Provider die gelisteten/testbaren Modelle"
  echo "  --check            scan + test, schreibt Results nach check_state.json und"
  echo "                     zeigt, wie lange der letzte Check je Provider her ist (lohnt sich?)"
  echo "  --all              run all providers"
  echo "  --<name>           run only this provider (repeatable)"
  echo "  --no-<name>        exclude this provider (repeatable)"
  echo ""
  echo "Ergebnisse werden nach jedem Lauf (scan/list/check) in results.json gemerged;"
  echo "bei --check zusaetzlich in check_state.json."
  echo ""
  echo "Providers: ${ALL_NAMES[*]}"
  echo ""
  echo "Env: STALE_HOURS=${STALE_HOURS} (Check gilt als 'frisch' bis zu dieser Zeit)"
}

# --- Flags parsen ---
MODE="scan"            # scan | list | check
run_all=false
includes=()
excludes=()
list_flag=false
check_flag=false

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --list) list_flag=true ;;
    --check) check_flag=true ;;
    --all) run_all=true ;;
    --no-*)
      name="${arg#--no-}"
      is_provider "$name" || { echo "Unknown provider: $name"; usage; exit 1; }
      excludes+=("$name")
      ;;
    --*)
      name="${arg#--}"
      is_provider "$name" || { echo "Unknown provider: $name"; usage; exit 1; }
      includes+=("$name")
      ;;
    *)
      echo "Unknown argument: $arg"
      usage
      exit 1
      ;;
  esac
done

if [[ "$list_flag" == true && "$check_flag" == true ]]; then
  echo "Error: --list und --check können nicht kombiniert werden."
  exit 1
fi
[[ "$list_flag" == true ]] && MODE="list"
[[ "$check_flag" == true ]] && MODE="check"

# --- Auswahl auflösen ---
selected=()
if [[ $# -eq 0 ]]; then
  while true; do
    show_menu
    read -rp "Pick: " choice
    case "$choice" in
      0)
        run_all=true
        break
        ;;
      p|P)
        echo ""
        echo "=== Proxy Settings ==="
        echo ""
        echo "  1  Fetch latest PVPN hosts from PrivateVPN website"
        echo "  2  Use manual PVPN hosts (set PVPN_HOSTS in .env)"
        echo "  3  Show current PVPN hosts"
        echo "  b  Back to main menu"
        echo ""
        read -rp "Proxy option: " proxy_choice
        case "$proxy_choice" in
          1)
            echo ""
            fetch_pvpn_hosts
            echo ""
            read -rp "Press Enter to continue... " _
            ;;
          2)
            echo ""
            echo "Set PVPN_HOSTS in your .env file, e.g.:"
            echo "  PVPN_HOSTS=\"us-nyc.pvdata.host us-lax.pvdata.host de-fra.pvdata.host\""
            echo ""
            read -rp "Press Enter to continue... " _
            ;;
          3)
            echo ""
            echo "Current PVPN hosts (${#PVPN_HOST_ARRAY[@]}):"
            printf "  %s\n" "${PVPN_HOST_ARRAY[@]}"
            echo ""
            read -rp "Press Enter to continue... " _
            ;;
          b|B)
            break
            ;;
          *)
            echo "Invalid proxy option: $proxy_choice"
            read -rp "Press Enter to continue... " _
            ;;
        esac
        ;;
      q|Q)
        exit 0
        ;;
      *)
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#ALL_NAMES[@]} ]]; then
          selected=("${ALL_NAMES[$((choice-1))]}")
          break
        else
          echo "Invalid: $choice"
          read -rp "Press Enter to continue... " _
        fi
        ;;
    esac
  done
fi

if [[ ${#includes[@]} -gt 0 ]]; then
  selected=("${includes[@]}")
elif [[ ${#selected[@]} -eq 0 ]]; then
  # ohne explizite Auswahl: --all, oder implizit alle bei --list/--check
  if [[ "$MODE" != "scan" || "$run_all" == true ]]; then
    for n in "${ALL_NAMES[@]}"; do
      skip=false
      for x in "${excludes[@]}"; do
        [[ "$n" == "$x" ]] && skip=true
      done
      $skip || selected+=("$n")
    done
  fi
fi

if [[ ${#selected[@]} -eq 0 ]]; then
  echo "Nothing selected."
  exit 0
fi

# --- Check: alten Status anzeigen (wie lange her, lohnt sich?) ---
report_state() {
  [[ -f "$STATE_FILE" ]] || { echo "Keine check_state.json vorhanden — läuft noch kein Status."; return 0; }
  echo "=== Check-Status (aus $STATE_FILE, frisch bis ${STALE_HOURS}h) ==="
  names=$(IFS='|'; echo "${ALL_NAMES[*]}")
  echo "$names" | sed 's/|/\n/g' | python3 -c "
import json,sys,datetime
names=sys.stdin.read().split()
stale=int(sys.argv[1])
path=sys.argv[2]
if stale<=0: stale=86400
import os
st={}
if os.path.exists(path):
    st=json.load(open(path))
provs=st.get('providers',{})
now=datetime.datetime.now(datetime.timezone.utc)
def parse(s):
    if not s: return None
    try:
        d=datetime.datetime.fromisoformat(s)
        return d if d.tzinfo else d.replace(tzinfo=datetime.timezone.utc)
    except Exception: return None
def fmt(sec):
    sec=int(sec)
    if sec<60: return f'{sec}s'
    if sec<3600: return f'{sec//60}m'
    if sec<86400: return f'{sec//3600}h'
    return f'{sec//86400}d {(sec%86400)//3600}h'
print(f'{\"Provider\":<14}{\"Letzter Check\":<24}{\"Alter\":<10}{\"Free-Tests\":<16}{\"Bewertung\"}')
for n in names:
    p=provs.get(n,{})
    lc=parse(p.get('last_check'))
    tested=p.get('tested',[])
    total=len(tested)
    ok=sum(1 for t in tested if isinstance(t,dict) and t.get('status')=='PASS')
    found=len(p.get('found',[]))
    if lc:
        age=(now-lc).total_seconds()
        verdict=f'ok — frisch' if age<stale else f'lohnt sich — {fmt(age)} alt'
        print(f'{n:<14}{lc.strftime(\"%Y-%m-%d %H:%M\"):<24}{fmt(age):<10}{f\"{ok}/{total} PASS\":<16}{verdict}')
    else:
        print(f'{n:<14}{\"nie\":<24}{\"-\":<10}{\"-\":<16}{\"noch nie gecheckt\"}')
" "$STALE_SECS" "$STATE_FILE"
  echo ""
}

if [[ "$MODE" == "check" ]]; then
  report_state
fi

echo "=== Free Model Scanner + Tester ==="
echo "Mode: $MODE"
echo "Time: $(date -Iseconds)"
echo ""

RESULTS_DIR="$(mktemp -d)"
trap 'rm -rf "$RESULTS_DIR"' EXIT

# --- Provider verarbeiten ---
run_provider() {
  local provider="$1"
  local entry url toml chat_url toml_path api_key api_key_env

  for e in "${PROVIDERS[@]}"; do
    IFS='|' read -r n u t <<< "$e"
    [[ "$n" == "$provider" ]] && { url="$u"; toml="$t"; break; }
  done

  chat_url="${url%/models}/chat/completions"
  toml_path="$TOML_DIR/$toml"

  # Env-Var aus TOML lesen (opencode braucht keinen Key)
  api_key=""
  api_key_env=""
  if [[ -n "$toml" && -f "$toml_path" ]]; then
    api_key_env=$(sed -n 's/^[[:space:]]*api_key_env[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$toml_path" | head -1)
    if [[ -n "$api_key_env" ]]; then
      api_key="${!api_key_env:-}"
    fi
  fi

  echo "--- $provider ---"

  if [[ "$provider" != "opencode" && -z "$api_key" ]]; then
    echo "  No API key ($api_key_env not set) — skip"
    echo ""
    return 0
  fi

  # Step 1: Alle Modelle vom /models Endpoint + Free-Status ermitteln
  local auth_args=()
  if [[ -n "$api_key" ]]; then
    auth_args=(-H "Authorization: Bearer $api_key")
  fi
  local response
  response=$(curl -s --max-time 15 "${auth_args[@]}" "$url" 2>/dev/null || true)

  if [[ -z "$response" ]]; then
    echo "  No response from /models endpoint"
    echo ""
    return 0
  fi

  # Dynamic parsing of models and free status from API response
  # free = True wenn das Modell laut API kostenlos ist:
  #   - isFree-Feld ist true
  #   - pricing-Dict vorhanden und prompt+completion (als Zahl) == 0
  # Fehlendes/leeres pricing gilt NICHT automatisch als free.
  local models_json
  models_json=$(echo "$response" | python3 -c "
import json,sys

def fnum(v, default=None):
    if v is None:
        return default
    if isinstance(v,(int,float)):
        return float(v)
    s=str(v).strip()
    try:
        return float(s)
    except ValueError:
        return default

try:
    d=json.load(sys.stdin)
    data = d.get('data') or d.get('models')
    if data is None and isinstance(d.get('result'), dict):
        data = d['result'].get('models')
    if isinstance(data, list):
        for m in data:
            mid = m.get('id') or m.get('name', '')
            free = False
            cost = '?/?'
            if m.get('isFree') is True:
                free = True
            pricing = m.get('pricing')
            if isinstance(pricing, dict) and pricing:
                p = fnum(pricing.get('prompt') or pricing.get('input'))
                c = fnum(pricing.get('completion') or pricing.get('output'))
                if p is not None and c is not None:
                    cost = f'{p:g}/{c:g}'
                    if p == 0 and c == 0:
                        free = True
            print(f'{mid}|{str(free).upper()}|{cost}')
    elif isinstance(data, dict):
        for k,v in data.items():
            print(f'{k}|FALSE|?/?')
except Exception:
    pass
" 2>/dev/null)

  # Free models aus der API (pricing=0/0, isFree, oder :free/-free-Suffix in der ID)
  # plus Sonderfall big-pickle (immer free bei opencode/zen).
  local free_models=()
  readarray -t free_models < <(echo "$models_json" | while IFS='|' read mid free_str cost; do
    if [[ "$free_str" == "TRUE" || "$mid" == *free || "$mid" == "big-pickle" ]]; then
      echo "$mid"
    fi
  done)

  # Alle in der API gelisteten Modell-IDs (für Filterung der Fallback-Liste)
  local available=()
  readarray -t available < <(echo "$models_json" | while IFS='|' read mid _ _; do
    [[ -n "$mid" ]] && echo "$mid"
  done)

  # Fallback: Wenn die API keinen Free-Status liefert (kein pricing/isFree/:free),
  # nutze die statische Liste free_models_for (gefiltert auf verfügbare Modelle).
  local static_free=()
  static_free=(); read -r -a static_free <<< "$(free_models_for "$provider")"
  if [[ ${#static_free[@]} -gt 0 ]]; then
    local merged=()
    readarray -t merged < <(printf '%s\n' "${free_models[@]:-}" "${static_free[@]}" | awk '!seen[$0]++')
    local filtered=()
    if [[ ${#available[@]} -gt 0 ]]; then
      readarray -t filtered < <(printf '%s\n' "${merged[@]}" | awk '!seen[$0]++' | grep -Fxf <(printf '%s\n' "${available[@]}") || true)
    else
      readarray -t filtered < <(printf '%s\n' "${merged[@]}")
    fi
    free_models=("${filtered[@]}")
  fi

  # Endgültig: free_models auf in der API vorhandene Modelle reduzieren (Dedup)
  local final_free=()
  if [[ ${#available[@]} -gt 0 ]]; then
    readarray -t final_free < <(printf '%s\n' "${free_models[@]:-}" | awk '!seen[$0]++' | grep -Fxf <(printf '%s\n' "${available[@]}") || true)
  else
    readarray -t final_free < <(printf '%s\n' "${free_models[@]:-}" | awk '!seen[$0]++')
  fi
  free_models=("${final_free[@]}")

  # Listing — FREE genau dann, wenn das Modell in der getesteten free_models-Liste ist
  echo "  Available models from API:"
  echo "$models_json" | while IFS='|' read mid free_str cost; do
    if printf '%s\n' "${free_models[@]}" | grep -qx "$mid"; then
      printf "    %-50s [%s]  \033[0;32mFREE\033[0m\n" "$mid" "$cost"
    else
      printf "    %-50s [%s]  \033[0;31mPAID\033[0m\n" "$mid" "$cost"
    fi
  done

  # gelistete Modelle für State merken (nur bei --check)
  if [[ -n "$RESULTS_DIR" ]]; then
    echo "$response" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    data=d.get('data', d.get('models', []))
    for m in data:
        print(m.get('id', m.get('name','')))
except: pass
" 2>/dev/null > "$RESULTS_DIR/found_$provider" || true
  fi

  # Step 2: Nur dynamisch als Free erkannte Modelle testen (wenn --check oder --all)
  if [[ "$MODE" == "list" ]]; then
    echo ""
    return 0
  fi

  if [[ ${#free_models[@]} -eq 0 ]]; then
    echo "  Free status cannot be determined from provider API (no FREE pricing found and no known free models)"
    echo ""
    return 0
  fi

  echo ""
  echo "  === Free Models Test ==="
  for model in "${free_models[@]}"; do
    printf "    %-50s " "$model"
    result=$(test_model "$chat_url" "$model" "$api_key")
    local status msg
    case "$result" in
      OK) status="PASS"; msg=""; pass ;;
      ERROR:*) status="FAIL"; msg="${result#ERROR: }"; echo -e "${RED}FAIL${NC} ($msg)" ;;
      *) status="FAIL"; msg="no response"; fail ;;
    esac
    if [[ -n "$RESULTS_DIR" ]]; then
      echo "$model|$status|$msg" >> "$RESULTS_DIR/tested_$provider"
    fi
  done

  echo ""
}

for p in "${selected[@]}"; do
  run_provider "$p"
done

# --- Results in JSON-Datei mergen (immer) ---
merge_results() {
  local target="$1"
  python3 -c "
import json,os,sys,datetime
basedir=sys.argv[1]; sf=sys.argv[2]
now=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')
st={}
if os.path.exists(sf):
    try: st=json.load(open(sf))
    except Exception: st={}
provs=st.setdefault('providers',{})
for fn in sorted(os.listdir(basedir)):
    if not fn.startswith('found_'):
        continue
    name=fn[len('found_'):]
    with open(os.path.join(basedir,fn)) as f:
        found=[l.strip() for l in f if l.strip()]
    tested=[]
    tf=os.path.join(basedir,'tested_'+name)
    if os.path.exists(tf):
        with open(tf) as f:
            for line in f:
                parts=line.strip().split('|',2)
                if len(parts)>=2:
                    tested.append({'model':parts[0],'status':parts[1],'msg':parts[2] if len(parts)>2 else ''})
    p=provs.setdefault(name,{})
    p['last_check']=now
    p['found']=found
    p['tested']=tested
    if tested:
        npass=sum(1 for t in tested if t['status']=='PASS')
        p['status']='ok' if npass==len(tested) else ('fail' if npass==0 else 'partial')
    else:
        p['status']='no-models'
st['last_run']=now
json.dump(st,open(sf,'w'),indent=2)
print(sf)
" "$RESULTS_DIR" "$target"
}

RESULTS_FILE="$BASE/results.json"
merge_results "$RESULTS_FILE"
echo "Results geschrieben: $RESULTS_FILE"

if [[ "$MODE" == "check" ]]; then
  echo ""
  merge_results "$STATE_FILE"
  echo "State geschrieben: $STATE_FILE"
fi

echo "=== Done ==="
#!/usr/bin/env bash
# test_all.sh — Run all or selected provider tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROVIDERS=(
  "01_opencode.sh"
  "02_kilo.sh"
  "03_groq.sh"
  "04_cerebras.sh"
  "05_nvidia.sh"
  "06_openrouter.sh"
  "07_mistral.sh"
  "08_deepseek.sh"
  "09_cloudflare.sh"
  "10_vercel.sh"
)

show_menu() {
  echo "=== Provider Test Suite ==="
  echo ""
  echo "  0  Run all"
  local i=1
  for p in "${PROVIDERS[@]}"; do
    name="${p%.sh}"
    name="${name#??_}"
    printf "  %-2d  %s\n" "$i" "$name"
    i=$((i+1))
  done
  echo ""
  echo "  q  Quit"
  echo ""
}

if [[ -z "${1:-}" ]]; then
  show_menu
  read -rp "Pick: " choice
else
  choice="$1"
fi

run_all() {
  echo ""
  echo "Running all provider tests..."
  echo "================================"
  for p in "${PROVIDERS[@]}"; do
    echo ""
    echo ">>> $p"
    echo "================================"
    bash "$SCRIPT_DIR/$p"
  done
}

run_one() {
  local idx="$1"
  if [[ "$idx" -ge 1 && "$idx" -le ${#PROVIDERS[@]} ]]; then
    local p="${PROVIDERS[$((idx-1))]}"
    echo ""
    bash "$SCRIPT_DIR/$p"
  else
    echo "Invalid choice: $idx"
    exit 1
  fi
}

case "$choice" in
  0) run_all ;;
  q|Q) exit 0 ;;
  *)
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      run_one "$choice"
    else
      echo "Invalid: $choice"
      exit 1
    fi
    ;;
esac

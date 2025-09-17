#!/usr/bin/env bash
set -euo pipefail

EXAMPLE_FILE="${1:-.env.example}"
ENV_FILE="${2:-.env}"

SHOW_VALUES="${SHOW_VALUES:-false}"      
COLOR="${COLOR:-auto}"                   
STRICT_KEYS="${STRICT_KEYS:-false}"     
EXIT_ON_DIFF="${EXIT_ON_DIFF:-true}"   

if [[ ! -r "$EXAMPLE_FILE" ]]; then
  echo "error: cannot read '$EXAMPLE_FILE'" >&2
  exit 1
fi
if [[ ! -r "$ENV_FILE" ]]; then
  echo "error: cannot read '$ENV_FILE'" >&2
  exit 1
fi

is_tty() { [[ -t 1 ]]; }
use_color=false
case "$COLOR" in
  always) use_color=true ;;
  never)  use_color=false ;;
  auto)   use_color=$(is_tty && echo true || echo false) ;;
  *)      echo "error: COLOR must be auto|always|never" >&2; exit 1 ;;
esac

c_red=""; c_green=""; c_yellow=""; c_dim=""; c_reset=""
if $use_color; then
  c_red=$'\033[31m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_dim=$'\033[2m'; c_reset=$'\033[0m'
fi

parse_env() {
  awk '
  function ltrim(s){ sub(/^[ \t\r\n]+/, "", s); return s }
  function rtrim(s){ sub(/[ \t\r\n]+$/, "", s); return s }
  function trim(s){ return rtrim(ltrim(s)) }
  {
    line=$0
    gsub("\r","",line)
    line=trim(line)
    if (line=="" || line ~ /^#/) next
    sub(/^export[ \t]+/,"",line)
    # Keep only valid ENV keys (A-Z0-9 and _), stop at first =
    split(line, a, "=")
    key=trim(a[1])
    if (key=="" || key !~ /^[A-Za-z_][A-Za-z0-9_]*$/) next
    if (index(line,"=")==0) { val="" } else { val=substr(line, index(line,"=")+1) }
    val=trim(val)
    if ((val ~ /^".*"$/) || (val ~ /^'\''.*'\''$/)) { val=substr(val,2,length(val)-2) }
    print key "\t" val
  }' "$1"
}

declare -A ex env
while IFS=$'\t' read -r k v; do [[ -n "${k:-}" ]] && ex["$k"]="$v"; done < <(parse_env "$EXAMPLE_FILE")
while IFS=$'\t' read -r k v; do [[ -n "${k:-}" ]] && env["$k"]="$v"; done < <(parse_env "$ENV_FILE")

mask() {
  local s="$1"
  $SHOW_VALUES || { echo "(hidden)"; return; }
  echo "$s"
}

missing=()
extra=()
changed=()

for k in "${!ex[@]}"; do
  if [[ -z "${env[$k]+_}" ]]; then
    missing+=("$k")
  else
    if [[ "$STRICT_KEYS" == "true" ]] && [[ "${ex[$k]}" != "${env[$k]}" ]]; then
      changed+=("$k")
    fi
  fi
done
for k in "${!env[@]}"; do
  if [[ -z "${ex[$k]+_}" ]]; then
    extra+=("$k")
  fi
done

diff_found=false
((${#missing[@]})) && diff_found=true
((${#extra[@]})) && diff_found=true
((${#changed[@]})) && diff_found=true

if ! $diff_found; then
  echo "${c_green}✓ No differences between ${EXAMPLE_FILE} and ${ENV_FILE}.${c_reset}"
  exit 0
fi

echo "${c_dim}Comparing ${EXAMPLE_FILE} → ${ENV_FILE}${c_reset}"

if ((${#missing[@]})); then
  echo "${c_red}- Missing in ${ENV_FILE}:${c_reset}"
  for k in "${missing[@]}"; do
    echo "  ${c_red}- ${k}=${c_dim}$(mask "${ex[$k]}")${c_reset}"
  done
fi

if ((${#extra[@]})); then
  echo "${c_green}+ Extra in ${ENV_FILE} (not in example):${c_reset}"
  for k in "${extra[@]}"; do
    echo "  ${c_green}+ ${k}=${c_dim}$(mask "${env[$k]}")${c_reset}"
  done
fi

if ((${#changed[@]})); then
  echo "${c_yellow}~ Present in both, values differ:${c_reset}"
  for k in "${changed[@]}"; do
    echo "  ${c_yellow}~ ${k}${c_reset}"
    if $SHOW_VALUES; then
      echo "    ${c_dim}example:${c_reset} ${ex[$k]}"
      echo "    ${c_dim}env:    ${c_reset} ${env[$k]}"
    fi
  done
fi

$EXIT_ON_DIFF && exit 2 || exit 0

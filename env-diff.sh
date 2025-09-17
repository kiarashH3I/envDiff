#!/usr/bin/env bash
set -euo pipefail

EXAMPLE_FILE="${1:-.env.example}"
ENV_FILE="${2:-.env}"

SHOW_VALUES="${SHOW_VALUES:-true}"
COLOR="${COLOR:-auto}"
EXIT_ON_DIFF="${EXIT_ON_DIFF:-true}"
PLACEHOLDER_PATTERNS="${PLACEHOLDER_PATTERNS:-}"

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

c_red=""; c_green=""; c_yellow=""; c_blue=""; c_dim=""; c_reset=""
if $use_color; then
  c_red=$'\033[31m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_blue=$'\033[34m'; c_dim=$'\033[2m'; c_reset=$'\033[0m'
fi

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
normlower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

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
    split(line, a, "=")
    key=trim(a[1])
    if (key=="" || key !~ /^[A-Za-z_][A-Za-z0-9_]*$/) next
    val=""
    if (index($0,"=")>0) { val=substr($0, index($0,"=")+1) }
    val=trim(val)
    if ((val ~ /^".*"$/) || (val ~ /^'\''.*'\''$/)) { val=substr(val,2,length(val)-2) }
    print key "\t" val
  }' "$1"
}

declare -A ex env
while IFS=$'\t' read -r k v; do [[ -n "${k:-}" ]] && ex["$k"]="$v"; done < <(parse_env "$EXAMPLE_FILE")
while IFS=$'\t' read -r k v; do [[ -n "${k:-}" ]] && env["$k"]="$v"; done < <(parse_env "$ENV_FILE")

mask() { $SHOW_VALUES && printf '%s\n' "$1" || printf '(hidden)\n'; }

is_placeholder() {
  local v="$(trim "$1")"
  [[ -z "$v" ]] && return 0
  [[ "$v" =~ ^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$ ]] && return 1
  case "$(normlower "$v")" in
    yourkeyhere|yourtokenhere|yoursecrethere|yourpasswordhere|yourkey|yourtoken|yoursecret|yourpassword|changeme|replaceme|sample|example|dummy|placeholder|to_be_filled|fillme|setme|none|null|nil|n/a|n\-a|empty) return 0 ;;
  esac
  printf '%s' "$v" | grep -Eiq '^[Xx]{6,}$' && return 0
  printf '%s' "$v" | grep -Eq '^(.)\1{5,}$' && return 0
  printf '%s' "$v" | grep -Eq '^[._\-\*•·]{6,}$' && return 0
  printf '%s' "$v" | grep -Eq '^<[^>]+>$' && return 0
  if [[ -n "$PLACEHOLDER_PATTERNS" ]]; then
    IFS=',' read -r -a pats <<< "$PLACEHOLDER_PATTERNS"
    for p in "${pats[@]}"; do
      [[ -z "$p" ]] && continue
      if printf '%s' "$v" | grep -Eiq -- "$p"; then return 0; fi
    done
  fi
  return 1
}

missing=()
extra=()
changed=()
placeholders=()

for k in "${!ex[@]}"; do
  if [[ -z "${env[$k]+_}" ]]; then
    missing+=("$k")
  else
    if [[ "${ex[$k]}" != "${env[$k]}" ]]; then
      changed+=("$k")
    fi
  fi
done

for k in "${!env[@]}"; do
  if [[ -z "${ex[$k]+_}" ]]; then
    extra+=("$k")
  fi
  if is_placeholder "${env[$k]}"; then
    placeholders+=("$k")
  fi
done

diff_found=false
((${#missing[@]})) && diff_found=true
((${#extra[@]})) && diff_found=true
((${#changed[@]})) && diff_found=true
((${#placeholders[@]})) && diff_found=true

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
    if $SHOW_VALUES; then
      echo "  ${c_yellow}~ ${k}${c_reset}"
      echo "    ${c_dim}example:${c_reset} ${ex[$k]}"
      echo "    ${c_dim}env:    ${c_reset} ${env[$k]}"
    else
      echo "  ${c_yellow}~ ${k}=${c_dim}(hidden) → (hidden)${c_reset}"
    fi
  done
fi

if ((${#placeholders[@]})); then
  echo "${c_blue}! Placeholders or empty in ${ENV_FILE}:${c_reset}"
  for k in "${placeholders[@]}"; do
    echo "  ${c_blue}! ${k}=${c_dim}$(mask "${env[$k]}")${c_reset}"
  done
fi

$EXIT_ON_DIFF && exit 2 || exit 0

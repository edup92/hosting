#!/usr/bin/env bash

# 1) Arguments

path_zip="${1:-}"
path_temp="$(mktemp -d)"
path_playbook="$path_temp/main.yml"
extravars_file="extravars.json"

# 2) Functions

cleanup() { rm -rf "$path_temp"; }
trap cleanup EXIT

# 3) SW requeriments

grep -q '^ID=ubuntu$' /etc/os-release || { echo "ERROR: Runner must be Ubuntu." >&2; exit 7; }

for bin in unzip jq ansible; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: Runner '$bin' not found." >&2
    exit 3
  fi
done

# 4) Error if path is missing or file not found

if [[ -z "$path_zip" || ! -f "$path_zip" ]]; then
  echo "ERROR: Missing or invalid file. Usage: $0 /path/to/playbook.zip" >&2
  exit 2
fi

# 5) Unzip, error if fails or main.yml not found

if ! unzip -q "$path_zip" -d "$path_temp" || [[ ! -f "$path_playbook" ]]; then
  echo "ERROR: Unzip failed or main.yml missing." >&2
  exit 4
fi

# 6) Extravars, generate if not found, error if empty, if not empty, save to extravars_file

if [[ "${extravars+x}" != "x" ]]; then
  jq -n '{}' >"$extravars_file"
elif [[ -z "${extravars//[[:space:]]/}" ]]; then
  echo "Error: extravars exists but is empty" >&2
  exit 1
else
  printf '%s' "$extravars" | jq -S '.' >"$extravars_file"
fi


#!/usr/bin/env bash

# Resolve the manifest key based on service path or shorthand
resolve_manifest_key() {
  local input="$1"

  if [[ "$input" == "omgwtfbbq" || "$input" == "." ]]; then
    echo "."
  elif [[ "$input" == charts/* || "$input" == chart ]]; then
    echo "$input"
  elif [[ "$input" == crates/* ]]; then
    echo "$input"
  else
    # assume shorthand crate name
    echo "crates/$input"
  fi
}

# Get version for any crate/chart/service using manifest key
get_manifest_version() {
  local key
  key=$(resolve_manifest_key "$1")
  jq -r --arg k "$key" '.[$k]' .release-please-manifest.json
}

# Map manifest key (path) to a short service name
# Used for docker tags, repo naming, etc.
service_name_from_path() {
  local key="$1"

  if [[ "$key" == "." ]]; then
    echo "omgwtfbbq"
  elif [[ "$key" == crates/* || "$key" == charts/* ]]; then
    basename "$key"
  elif [[ "$key" == chart ]]; then
    echo "chart-omgwtfbbq"
  else
    echo "$key"  # fallback
  fi
}

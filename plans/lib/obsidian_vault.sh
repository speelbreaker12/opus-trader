#!/usr/bin/env bash

if [[ -n "${__OBSIDIAN_VAULT_SOURCED:-}" ]]; then
  return 0
fi
__OBSIDIAN_VAULT_SOURCED=1

obsidian_vault_default_path() {
  printf '%s\n' "${HOME}/Desktop/Obsidian"
}

obsidian_vault_configured_path() {
  if [[ -n "${OBSIDIAN_VAULT_PATH:-}" ]]; then
    printf '%s\n' "$OBSIDIAN_VAULT_PATH"
  else
    obsidian_vault_default_path
  fi
}

obsidian_vault_missing_message() {
  local mode="${1:?missing mode}"
  local path="${2:?missing path}"

  case "$mode" in
    advisory)
      printf 'WARNING: Obsidian vault not found at %s. Set OBSIDIAN_VAULT_PATH to enable Obsidian workflow features.\n' "$path"
      ;;
    required)
      printf 'ERROR: Obsidian vault not found at %s. Set OBSIDIAN_VAULT_PATH or create that vault before continuing.\n' "$path"
      ;;
    *)
      printf 'ERROR: unknown Obsidian vault mode: %s\n' "$mode"
      return 2
      ;;
  esac
}

resolve_obsidian_vault_path() {
  local mode="${1:?missing mode}"
  local candidate

  candidate="$(obsidian_vault_configured_path)"
  if [[ -d "$candidate" ]]; then
    OBSIDIAN_VAULT_PATH_RESOLVED="$candidate"
    export OBSIDIAN_VAULT_PATH_RESOLVED
    return 0
  fi

  OBSIDIAN_VAULT_PATH_RESOLVED=""
  export OBSIDIAN_VAULT_PATH_RESOLVED
  return 1
}

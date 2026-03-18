#!/usr/bin/env bash
set -euo pipefail

die_invalid() {
  local code="$1"
  local value="$2"
  echo "ERROR: $code (value=${value:-<unset>})" >&2
  exit 1
}

resolve_toggle() {
  local name="$1"
  local default_value="$2"
  local allowed_csv="$3"
  local value="${!name:-$default_value}"
  local allowed=",$allowed_csv,"

  if [[ "$allowed" != *",$value,"* ]]; then
    case "$name" in
      WORKFLOW_SEQUENCE_ENFORCEMENT) die_invalid "INVALID_WORKFLOW_SEQUENCE_ENFORCEMENT" "$value" ;;
      CODEX_STAGE_POLICY) die_invalid "INVALID_CODEX_STAGE_POLICY" "$value" ;;
      CI_REPO_ONLY_ENFORCEMENT) die_invalid "INVALID_CI_REPO_ONLY_ENFORCEMENT" "$value" ;;
      TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY) die_invalid "INVALID_TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY" "$value" ;;
      *) die_invalid "INVALID_TOGGLE_POLICY" "$value" ;;
    esac
  fi

  printf '%s=%s\n' "$name" "$value"
}

resolve_toggle "WORKFLOW_SEQUENCE_ENFORCEMENT" "warn" "warn,block"
resolve_toggle "CODEX_STAGE_POLICY" "warn" "warn,require"
resolve_toggle "CI_REPO_ONLY_ENFORCEMENT" "off" "off,on"
resolve_toggle "TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY" "require" "require,fallback_runtime_fail_closed"

echo "PASS: toggle policy wiring"

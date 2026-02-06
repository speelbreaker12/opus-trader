#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Daytime wrapper: quick verify, no pass flips, no full final verify.
export RPH_VERIFY_MODE="quick"
export RPH_FINAL_VERIFY_MODE="quick"
export RPH_FORBID_MARK_PASS="1"
exec "$SCRIPT_DIR/ralph.sh" "$@"

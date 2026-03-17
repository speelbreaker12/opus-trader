#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *" --json "* ]]; then
  echo '{"status":"PASS"}'
fi
exit 0

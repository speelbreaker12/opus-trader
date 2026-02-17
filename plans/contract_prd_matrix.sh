#!/usr/bin/env bash
set -euo pipefail
python3 "$(dirname "$0")/contract_prd_matrix.py" "$@"

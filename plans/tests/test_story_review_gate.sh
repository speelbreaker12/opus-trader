#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Compatibility shim: historical verify gate name retained at 14g.
# The current equivalent enforcement is story_review_findings_guard.
bash "$ROOT/plans/tests/test_story_review_findings_guard.sh"

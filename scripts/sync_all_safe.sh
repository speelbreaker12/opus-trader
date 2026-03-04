#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${ROOT}" ]]; then
  echo "ERROR: not inside a git repository" >&2
  exit 2
fi
cd "${ROOT}"

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required" >&2
  exit 2
fi

git fetch --all --prune

tmp_out="$(mktemp)"
pull_out="$(mktemp)"
pull_err="$(mktemp)"
trap 'rm -f "${tmp_out}" "${pull_out}" "${pull_err}"' EXIT

while read -r wt; do
  branch="$(git -C "${wt}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "DETACHED")"
  status_count="$(git -C "${wt}" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  upstream="$(git -C "${wt}" rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)"

  if [[ "${status_count}" != "0" ]]; then
    printf 'SKIP_DIRTY|%s|%s|changes=%s\n' "${wt}" "${branch}" "${status_count}" >> "${tmp_out}"
    continue
  fi

  if [[ -z "${upstream}" ]]; then
    printf 'SKIP_NO_UPSTREAM|%s|%s\n' "${wt}" "${branch}" >> "${tmp_out}"
    continue
  fi

  counts="$(git -C "${wt}" rev-list --left-right --count "${upstream}"...HEAD 2>/dev/null || echo 'ERR ERR')"
  behind="$(printf '%s' "${counts}" | awk '{print $1}')"
  ahead="$(printf '%s' "${counts}" | awk '{print $2}')"

  if [[ "${behind}" == "0" && "${ahead}" == "0" ]]; then
    printf 'OK_UP_TO_DATE|%s|%s|%s\n' "${wt}" "${branch}" "${upstream}" >> "${tmp_out}"
    continue
  fi

  if [[ "${behind}" != "0" && "${ahead}" == "0" ]]; then
    if git -C "${wt}" pull --ff-only >"${pull_out}" 2>"${pull_err}"; then
      printf 'FF_UPDATED|%s|%s|%s|behind=%s\n' "${wt}" "${branch}" "${upstream}" "${behind}" >> "${tmp_out}"
    else
      err_tail="$(tail -n 2 "${pull_err}" | tr '\n' ' ')"
      printf 'SKIP_PULL_FAILED|%s|%s|%s|%s\n' "${wt}" "${branch}" "${upstream}" "${err_tail}" >> "${tmp_out}"
    fi
    continue
  fi

  printf 'SKIP_DIVERGED|%s|%s|%s|behind=%s|ahead=%s\n' "${wt}" "${branch}" "${upstream}" "${behind}" "${ahead}" >> "${tmp_out}"
done < <(git worktree list --porcelain | awk '/^worktree /{print $2}')

cat "${tmp_out}"

echo
echo "Summary:"
for kind in OK_UP_TO_DATE FF_UPDATED SKIP_DIRTY SKIP_NO_UPSTREAM SKIP_DIVERGED SKIP_PULL_FAILED; do
  count="$(grep -c "^${kind}|" "${tmp_out}" || true)"
  printf '  %s=%s\n' "${kind}" "${count}"
done

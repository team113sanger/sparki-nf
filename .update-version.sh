#!/bin/bash
# Rewrite this repository's version in every file that records it.
#
# Each TARGETS entry is "<repo-relative path>|<extended regex>". The regex must
# match exactly one line in its file and capture three groups - before, the
# version, after - so the rewrite preserves that file's quoting and column
# alignment. Every target is pre-flighted before anything is written: if any
# file is missing, or any regex matches zero or several lines, nothing changes.
#
# Usage:  ./.update-version.sh 1.2.3
#
# Sanity check after adapting it: run it to a throwaway version and back to the
# current one - `git diff` should then be empty.

set -Eeuo pipefail

TARGETS=(
  "assets/run_pathogen_id.sh|^(REVISION=\")([0-9]+\.[0-9]+\.[0-9]+)(\")$"
  "nextflow.config|^([[:space:]]*version[[:space:]]*=[[:space:]]*')([0-9]+\.[0-9]+\.[0-9]+)(')$"
)

function die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

NEW_VERSION="${1:-}"
[[ -n "${NEW_VERSION}" ]] || die "usage: $0 <X.Y.Z>"
[[ "${NEW_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z (got: ${NEW_VERSION})"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO_ROOT}"

# ---- Pre-flight: verify every target before writing any of them. ----
for target in "${TARGETS[@]}"; do
  path="${target%%|*}"
  regex="${target#*|}"
  [[ -f "${path}" ]] || die "${path} does not exist"
  count="$(grep -cE "${regex}" "${path}" || true)"
  (( count == 1 )) || die "${path}: regex matched ${count} lines, expected exactly 1 (regex: ${regex})"
done

# ---- Rewrite. ----
for target in "${TARGETS[@]}"; do
  path="${target%%|*}"
  regex="${target#*|}"
  old="$(grep -E "${regex}" "${path}" | sed -E "s|${regex}|\2|")"
  sed -i -E "s|${regex}|\1${NEW_VERSION}\3|" "${path}"
  printf '%-32s %s -> %s\n' "${path}" "${old}" "${NEW_VERSION}"
done

printf '\nDone. Review with `git diff`, then update CHANGELOG.md before cutting the release.\n'

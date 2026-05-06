#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>" >&2
  echo "Example: $0 0.3.1" >&2
  exit 2
fi

version="$1"
tag="v$version"

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid semantic version: $version" >&2
  exit 1
fi

for path in CHANGELOG.md Info.plist .github/workflows/release.yml .github/scripts/changelog-section.sh; do
  if [[ ! -f "$path" ]]; then
    echo "Missing required release file: $path" >&2
    exit 1
  fi
done

if git rev-parse "$tag" >/dev/null 2>&1; then
  echo "Tag already exists locally: $tag" >&2
  exit 1
fi

set +e
git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1
ls_remote_status=$?
set -e

if [[ $ls_remote_status -eq 0 ]]; then
  echo "Tag already exists on origin: $tag" >&2
  exit 1
elif [[ $ls_remote_status -eq 2 ]]; then
  :
else
  echo "git ls-remote failed while checking origin tag $tag" >&2
  exit "$ls_remote_status"
fi

if ! grep -q 'tags:' .github/workflows/release.yml || ! grep -q 'v\*\.\*\.\*' .github/workflows/release.yml; then
  echo "Release workflow does not appear to be semver tag-triggered." >&2
  exit 1
fi

if ! .github/scripts/changelog-section.sh "$version" >/tmp/freeflow-release-notes.md; then
  echo "Could not extract CHANGELOG.md section for $version" >&2
  exit 1
fi

if [[ ! -s /tmp/freeflow-release-notes.md ]]; then
  echo "Extracted changelog section is empty for $version" >&2
  exit 1
fi

if ! grep -q "^## \\[$version\\]" /tmp/freeflow-release-notes.md; then
  echo "Extracted changelog section has an unexpected heading." >&2
  exit 1
fi

echo "Release checks passed for $tag"
echo
cat /tmp/freeflow-release-notes.md

#!/usr/bin/env bash
set -euo pipefail
upstream=free-dam-man/cf-global-edge-node-skill
target=${GITHUB_REPOSITORY:-KUAILESHANGWEI/edge-skill}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# An empty release list is normal; API errors must not be treated as success.
gh api "repos/$upstream/releases?per_page=100" > "$tmp/releases.json"
tag=$(python3 - "$tmp/releases.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    releases = json.load(f)
for release in releases:
    if not release['draft'] and not release['prerelease']:
        print(release['tag_name'])
        break
PY
)
if [ -z "$tag" ]; then
  echo 'Upstream has no published stable release.'
  exit 0
fi
mkdir "$tmp/assets"
gh release download "$tag" --repo "$upstream" --dir "$tmp/assets"
if ! gh release view "$tag" --repo "$target" >/dev/null 2>&1; then
  gh release create "$tag" --repo "$target" --title "$tag" --notes "Assets mirrored from $upstream."
fi
find "$tmp/assets" -type f -print0 | while IFS= read -r -d '' asset; do
  gh release upload "$tag" "$asset" --repo "$target" --clobber
done

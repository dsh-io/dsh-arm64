#!/usr/bin/env bash
# Publish rootfs + overlay + manifest to a GitHub release. Idempotent:
# re-uploads with --clobber when the release already exists.
set -euo pipefail

STAGE="${1:?usage: publish-release.sh <stage-dir> <version>}"
VER="${2:?version required}"

cd "${STAGE}"

URL="https://github.com/dsh-io/dsh-arm64/releases/download/v${VER}/dsh-arm64-rootfs-${VER}.tar.xz"
python3 - "$URL" <<'EOF'
import json, sys
m = json.load(open('manifest.json'))
m['url'] = sys.argv[1]
json.dump(m, open('manifest.json', 'w'))
EOF
echo "==> manifest:"
cat manifest.json

ASSETS=()
for f in "dsh-arm64-rootfs-${VER}.tar.xz" rootfs.sha256sums manifest.json \
         "overlay/dsh-arm64-${VER}.tar.gz" overlay/sha256sums.txt; do
  if [ -f "$f" ]; then
    ASSETS+=("$f")
  else
    echo "!! missing asset: $f (skipped)"
  fi
done
[ "${#ASSETS[@]}" -gt 0 ] || { echo "!! no assets to publish" >&2; exit 1; }

if gh release view "v${VER}" >/dev/null 2>&1; then
  gh release upload "v${VER}" "${ASSETS[@]}" --clobber
else
  gh release create "v${VER}" "${ASSETS[@]}" \
    --title "dsh-arm64 ${VER}" --notes "overlay + bookworm rootfs"
fi

echo "==> release v${VER} assets:"
gh release view "v${VER}" --json assets --jq '.assets[].name'
#!/usr/bin/env bash
set -euo pipefail

# dsh-arm64 overlay build. Supply-chain controlled: the full dependency tree
# is installed OFFLINE from the vendored npm cache (vendor/npm-cache.tar.gz
# split into <100MB parts for GitHub's file limit + vendor/package-lock.json).
# No registry access at build time; the lockfile's integrity hashes pin every
# package, so tampered or withdrawn upstream versions cannot change the
# artifact.
#
# Since dsh 0.1.7 the tree carries several native addons, all delivered as
# per-platform optional packages (@koromix/koffi-linux-arm64,
# @img/sharp-linux-arm64, sherpa-onnx-linux-arm64, node-pty prebuilds, ...),
# so nothing compiles on the build host as long as the vendored cache carries
# the linux-arm64 tarballs — which the REGENERATE_VENDOR path below ensures
# via --cpu/--os/--libc. node-pty additionally falls back to a source rebuild
# if its bundled prebuild fails to load.
#
# To bump the dsh baseline, regenerate vendor/: run the script with
# REGENERATE_VENDOR=1 on any networked host (the lockfile + cache are resolved
# for linux/arm64 via --cpu/--os/--libc, so no arm64 machine is needed) and
# commit the new vendor/package-lock.json + vendor/npm-cache.tar.gz.

BASELINE="${1:-0.1.7-rc.2}"
STAGE="${2:-/tmp/dsh-arm64-stage}"
VENDOR="$(cd "$(dirname "$0")/.." && pwd)/vendor"

if [ -n "${REGENERATE_VENDOR:-}" ]; then
  # Resolution only — no scripts run, nothing is executed for the target
  # platform, so this works on any host architecture.
  echo "==> regenerating vendor lockfile + npm cache for dsh@${BASELINE} (linux/arm64)"
  rm -rf "${STAGE}"
  mkdir -p "${STAGE}"
  cd "${STAGE}"
  cat > package.json <<EOF
{
  "name": "dsh-arm64-stage",
  "version": "1.0.0",
  "private": true,
  "dependencies": { "@deepseek-ai/dsh": "${BASELINE}" }
}
EOF
  npm_config_cache="${STAGE}/.npm-cache" \
    npm install --cpu=arm64 --os=linux --libc=glibc --ignore-scripts \
    --registry=https://registry.npmmirror.com --no-audit --no-fund 2>&1 | tail -4
  mkdir -p "${VENDOR}"
  cp package-lock.json "${VENDOR}/package-lock.json"
  rm -f "${VENDOR}"/npm-cache.tar.gz.part-*
  tar -C "${STAGE}" -cz .npm-cache | split -b 90m -d - "${VENDOR}/npm-cache.tar.gz.part-"
  echo "==> vendor updated: ${VENDOR}/package-lock.json + npm-cache.tar.gz.part-*"
  echo "==> commit the lockfile and all part files; the real build runs on arm64"
  exit 0
fi

if [ "$(uname -m)" != "aarch64" ] && [ "$(uname -m)" != "arm64" ]; then
  echo "!! build.sh must run on an arm64 host (got $(uname -m))" >&2
  echo "   (vendor regeneration works anywhere: REGENERATE_VENDOR=1 $0)" >&2
  exit 2
fi

echo "==> dsh-arm64 build: baseline dsh@${BASELINE} into ${STAGE}"

# CI cache fast path: a complete stage skips install + native extraction.
if [ -f "${STAGE}/node_modules/@deepseek-ai/dsh/lib/bin.js" ] \
   && [ -f "${STAGE}/node_modules/@deepseek-ai/dsh/package.json" ] \
   && [ -n "$(find "${STAGE}/node_modules/node-pty" -name 'pty.node' 2>/dev/null | head -1)" ] \
   && [ -n "$(find "${STAGE}/node_modules/koffi" "${STAGE}/node_modules/@koromix" -name '*.node' 2>/dev/null | head -1)" ]; then
  echo "==> stage cache hit: skipping install + native builds"
  cd "${STAGE}"
  node -e "require('node-pty'); require('koffi'); console.log('==> native addons load OK')"
  echo "==> build OK"
  exit 0
fi

rm -rf "${STAGE}"
mkdir -p "${STAGE}"
cd "${STAGE}"

cat > package.json <<EOF
{
  "name": "dsh-arm64-stage",
  "version": "1.0.0",
  "private": true,
  "dependencies": { "@deepseek-ai/dsh": "${BASELINE}" }
}
EOF
cp "${VENDOR}/package-lock.json" package-lock.json
# The cache tarball is vendored as split parts (GitHub's 100MB file limit);
# it carries a .npm-cache/ prefix: unpack into the stage root.
cat "${VENDOR}"/npm-cache.tar.gz.part-* | tar -xzf - -C "${STAGE}"
echo "==> offline install from vendored npm cache (integrity-pinned)"
npm_config_cache="${STAGE}/.npm-cache" npm ci --offline --no-audit --no-fund 2>&1 | tail -4

# node-pty: prefer the bundled linux-arm64 prebuild; only if it fails to load
# do we force a source build (prebuild.js honors npm_config_build_from_source
# by deleting prebuilds/ and falling through to node-gyp).
if ! node -e "require('node-pty')" 2>/dev/null; then
  echo "==> bundled pty.node prebuild failed to load; rebuilding from source"
  npm_config_build_from_source=true npm rebuild node-pty 2>&1 | tail -3
fi

PTY="$(find node_modules/node-pty -name 'pty.node' 2>/dev/null | head -1)"
if [ -z "${PTY}" ]; then
  echo "!! node-pty has no pty.node (prebuild missing and source build failed)" >&2
  exit 1
fi
echo "==> pty.node: ${PTY}"
node -e "require('node-pty'); require('koffi'); console.log('==> native addons load OK')"

# Other platform-delivered binaries in the 0.1.7 tree (presence checks —
# they ship as optional platform packages, so a miss means the vendored
# cache was incomplete, not a compile failure).
for mod in @koromix/koffi-linux-arm64 @img/sharp-linux-arm64 \
           sherpa-onnx-linux-arm64 @vscode/ripgrep-linux-arm64 \
           node-addon-require-builtin-linux-arm64-gnu; do
  if [ ! -d "node_modules/${mod}" ]; then
    echo "!! missing platform package: ${mod} (regenerate vendor/ for linux/arm64)" >&2
    exit 1
  fi
done
echo "==> platform packages present"
echo "==> build OK"

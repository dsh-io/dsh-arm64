#!/usr/bin/env bash
set -euo pipefail

# dsh-arm64 overlay build. Supply-chain controlled: the full dependency tree
# is installed OFFLINE from the vendored npm cache (vendor/npm-cache.tar.zst +
# vendor/package-lock.json). No registry access at build time; the lockfile's
# integrity hashes pin every package, so tampered or withdrawn upstream
# versions cannot change the artifact. Only node-pty is compiled on the host.
#
# To bump the dsh baseline, regenerate vendor/: run the script with
# REGENERATE_VENDOR=1 on a networked arm64 host and commit the new
# vendor/package-lock.json + vendor/npm-cache.tar.zst.

BASELINE="${1:-0.1.0-rc.6}"
STAGE="${2:-/tmp/dsh-arm64-stage}"
VENDOR="$(cd "$(dirname "$0")/.." && pwd)/vendor"

if [ "$(uname -m)" != "aarch64" ] && [ "$(uname -m)" != "arm64" ]; then
  echo "!! build.sh must run on an arm64 host (got $(uname -m))" >&2
  exit 2
fi

echo "==> dsh-arm64 build: baseline dsh@${BASELINE} into ${STAGE}"

# CI cache fast path: a complete stage skips install + node-pty compile.
if [ -f "${STAGE}/node_modules/@deepseek-ai/dsh/lib/bin.js" ] \
   && [ -f "${STAGE}/node_modules/@deepseek-ai/dsh/package.json" ] \
   && [ -n "$(find "${STAGE}/node_modules/node-pty" -name 'pty.node' 2>/dev/null | head -1)" ]; then
  echo "==> stage cache hit: skipping install + compile"
  cd "${STAGE}"
  node -e "require('node-pty'); console.log('==> pty.node loads OK')"
  echo "==> build OK"
  exit 0
fi

rm -rf "${STAGE}"
mkdir -p "${STAGE}"
cd "${STAGE}"

if [ -n "${REGENERATE_VENDOR:-}" ]; then
  echo "==> regenerating vendor lockfile + npm cache (network required)"
  cat > package.json <<EOF
{
  "name": "dsh-arm64-stage",
  "version": "1.0.0",
  "private": true,
  "dependencies": { "@deepseek-ai/dsh": "${BASELINE}" }
}
EOF
  npm_config_cache="${STAGE}/.npm-cache" \
    npm install --registry=https://registry.npmmirror.com --no-audit --no-fund 2>&1 | tail -4
  mkdir -p "${VENDOR}"
  cp package-lock.json "${VENDOR}/package-lock.json"
  tar -C "${STAGE}" -czf "${VENDOR}/npm-cache.tar.gz" .npm-cache
  echo "==> vendor updated: ${VENDOR}/package-lock.json + npm-cache.tar.gz"
else
  cat > package.json <<EOF
{
  "name": "dsh-arm64-stage",
  "version": "1.0.0",
  "private": true,
  "dependencies": { "@deepseek-ai/dsh": "${BASELINE}" }
}
EOF
  cp "${VENDOR}/package-lock.json" package-lock.json
  # The cache tarball carries a .npm-cache/ prefix: unpack into the stage root.
  tar -xzf "${VENDOR}/npm-cache.tar.gz" -C "${STAGE}"
  echo "==> offline install from vendored npm cache (integrity-pinned)"
  npm_config_cache="${STAGE}/.npm-cache" npm ci --offline --no-audit --no-fund 2>&1 | tail -4
fi

npm rebuild node-pty 2>&1 | tail -3

PTY="$(find node_modules/node-pty -name 'pty.node' 2>/dev/null | head -1)"
if [ -z "${PTY}" ]; then
  echo "!! node-pty failed to compile: no pty.node produced" >&2
  exit 1
fi
echo "==> pty.node: ${PTY}"
node -e "require('node-pty'); console.log('==> pty.node loads OK')"
echo "==> build OK"

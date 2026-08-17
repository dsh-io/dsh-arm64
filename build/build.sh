#!/usr/bin/env bash
set -euo pipefail

BASELINE="${1:-0.1.0-rc.6}"
STAGE="${2:-/tmp/dsh-arm64-stage}"

if [ "$(uname -m)" != "aarch64" ] && [ "$(uname -m)" != "arm64" ]; then
  echo "!! build.sh must run on an arm64 host (got $(uname -m))" >&2
  exit 2
fi

echo "==> dsh-arm64 build: baseline dsh@${BASELINE} into ${STAGE}"
rm -rf "${STAGE}"
mkdir -p "${STAGE}"
cd "${STAGE}"

npm init -y >/dev/null 2>&1
npm install "@deepseek-ai/dsh@${BASELINE}" --no-audit --no-fund 2>&1 | tail -4
npm rebuild node-pty 2>&1 | tail -3

PTY="$(find node_modules/node-pty -name 'pty.node' 2>/dev/null | head -1)"
if [ -z "${PTY}" ]; then
  echo "!! node-pty failed to compile: no pty.node produced" >&2
  exit 1
fi
echo "==> pty.node: ${PTY}"
node -e "require('node-pty'); console.log('==> pty.node loads OK')"
echo "==> build OK"
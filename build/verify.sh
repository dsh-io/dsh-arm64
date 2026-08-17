#!/usr/bin/env bash
set -euo pipefail

STAGE="${1:?usage: verify.sh <stage-dir>}"
cd "${STAGE}"

node -e "require('node-pty'); console.log('==> pty.node loads OK')"

echo "==> booting dsh web (60s window)..."
timeout 60 node --expose-internals node_modules/@deepseek-ai/dsh/lib/bin.js web > boot.log 2>&1 || true
if grep -qi "node-pty\|pty.node" boot.log; then
  echo "!! node-pty errors in boot log:" >&2
  grep -i "node-pty\|pty.node" boot.log >&2
  exit 1
fi
if grep -qi "error" boot.log; then
  echo "!! other boot errors in boot log:" >&2
  grep -i "error" boot.log >&2
  exit 1
fi
echo "==> boot OK: no node-pty errors"
#!/usr/bin/env bash
set -euo pipefail

STAGE="${1:?usage: verify.sh <stage-dir>}"
cd "${STAGE}"

node -e "require('node-pty'); require('koffi'); require('sharp'); console.log('==> native addons load OK')"
node -e "const s=require('sherpa-onnx-node'); console.log('==> sherpa-onnx OK')" 2>/dev/null \
  || echo "==> sherpa-onnx skipped (experimental voice input, lazy-loaded)"

echo "==> exercising pty spawn (new web terminal uses node-pty)..."
node -e "
const pty = require('node-pty');
const t = pty.spawn('echo', ['PTY_SPAWN_OK'], { name: 'xterm', cols: 80, rows: 24, cwd: process.cwd(), env: process.env });
let out = '';
t.onData((d) => { out += d; });
setTimeout(() => {
  t.kill();
  if (!out.includes('PTY_SPAWN_OK')) { console.error('!! pty spawn produced no output'); process.exit(1); }
  console.log('==> pty spawn OK');
}, 3000);
" || { echo "!! pty spawn FAILED" >&2; exit 1; }

echo "==> booting dsh web (60s window)..."
timeout 60 node --expose-internals node_modules/@deepseek-ai/dsh/lib/bin.js web > boot.log 2>&1 || true
if grep -qi "node-pty\|pty.node\|koffi" boot.log; then
  echo "!! native-addon errors in boot log:" >&2
  grep -i "node-pty\|pty.node\|koffi" boot.log >&2
  exit 1
fi
if grep -qi "error" boot.log; then
  echo "!! other boot errors in boot log:" >&2
  grep -i "error" boot.log >&2
  exit 1
fi
echo "==> boot OK: no node-pty errors"
#!/usr/bin/env bash
set -euo pipefail

# Full-chain verification on the host: unpack the rootfs artifact, boot the
# dsh web engine inside proot (0-error window), smoke the agent shell.
STAGE="${1:?usage: verify-rootfs.sh <rootfs.tar.xz> [work-dir]}"
WORK="${2:-/tmp/dsh-arm64-rootfs-verify}"

if [ "$(uname -m)" != "aarch64" ] && [ "$(uname -m)" != "arm64" ]; then
  echo "!! verify-rootfs.sh must run on an arm64 host (got $(uname -m))" >&2
  exit 2
fi
command -v proot >/dev/null || apt-get install -y proot >/dev/null

rm -rf "${WORK}"
mkdir -p "${WORK}/rootfs"
tar -xJf "${STAGE}" -C "${WORK}/rootfs"

[ -x "${WORK}/rootfs/usr/local/bin/node" ] || { echo "!! node missing" >&2; exit 1; }
[ -f "${WORK}/rootfs/root/.dsh-arm64/node_modules/@deepseek-ai/dsh/lib/bin.js" ] \
  || { echo "!! dsh missing" >&2; exit 1; }

# NOTE: no --kill-on-exit — Ubuntu's proot 5.4 lacks it; the app ships a
# newer static build where it exists.
PROOT_ARGS=(-0 -r "${WORK}/rootfs" -b /dev:/dev -b /proc:/proc -b /sys:/sys -w /root)

echo "==> agent shell smoke:"
proot "${PROOT_ARGS[@]}" -- /usr/bin/env -i HOME=/root \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TERM=xterm-256color \
  bash -c 'echo SHELL_OK; id -u; node --version; which node bash' || { echo "!! shell smoke FAILED" >&2; exit 1; }

echo "==> booting dsh web (60s window)..."
timeout 60 proot "${PROOT_ARGS[@]}" -- /usr/bin/env -i HOME=/root \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TERM=xterm-256color \
  DSH_HOME=/root/.dsh \
  node --expose-internals /root/.dsh-arm64/node_modules/@deepseek-ai/dsh/lib/bin.js web \
  > "${WORK}/boot.log" 2>&1 || true
if grep -qi "error\|pty.node" "${WORK}/boot.log"; then
  echo "!! boot errors:" >&2
  grep -i "error\|pty.node" "${WORK}/boot.log" >&2
  exit 1
fi
echo "==> verify OK: shell smoke + dsh web boot clean"

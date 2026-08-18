#!/usr/bin/env bash
set -euo pipefail

# Full-chain verification on the host: unpack the rootfs artifact, boot the
# dsh web engine inside chroot (0-error window), smoke the agent shell.
# chroot (not proot) is used because Ubuntu's proot 5.4 lacks --kill-on-exit
# / `--` and segfaults on arm64 runners; the app ships a newer static proot
# where those exist.
STAGE="${1:?usage: verify-rootfs.sh <rootfs.tar.xz> [work-dir]}"
WORK="${2:-/tmp/dsh-arm64-rootfs-verify}"

if [ "$(uname -m)" != "aarch64" ] && [ "$(uname -m)" != "arm64" ]; then
  echo "!! verify-rootfs.sh must run on an arm64 host (got $(uname -m))" >&2
  exit 2
fi
[ "$(id -u)" = "0" ] || { echo "!! verify-rootfs.sh needs root (chroot)" >&2; exit 2; }

rm -rf "${WORK}"
mkdir -p "${WORK}/rootfs"
tar -xJf "${STAGE}" -C "${WORK}/rootfs"

[ -x "${WORK}/rootfs/usr/local/bin/node" ] || { echo "!! node missing" >&2; exit 1; }
[ -f "${WORK}/rootfs/root/.dsh-arm64/node_modules/@deepseek-ai/dsh/lib/bin.js" ] \
  || { echo "!! dsh missing" >&2; exit 1; }

# /proc for node's process introspection inside the chroot.
if [ -d "${WORK}/rootfs/proc" ] && [ -z "$(ls -A "${WORK}/rootfs/proc" 2>/dev/null || true)" ]; then
  mount --bind /proc "${WORK}/rootfs/proc"
  trap 'umount "${WORK}/rootfs/proc" 2>/dev/null || true' EXIT
fi

CHROOT_ENV=(HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TERM=xterm-256color)

echo "==> agent shell smoke:"
chroot "${WORK}/rootfs" /usr/bin/env -i "${CHROOT_ENV[@]}" \
  bash -c 'echo SHELL_OK; id -u; node --version; which node bash' || { echo "!! shell smoke FAILED" >&2; exit 1; }

echo "==> booting dsh web (60s window)..."
timeout 60 chroot "${WORK}/rootfs" /usr/bin/env -i "${CHROOT_ENV[@]}" DSH_HOME=/root/.dsh \
  node --expose-internals /root/.dsh-arm64/node_modules/@deepseek-ai/dsh/lib/bin.js web \
  > "${WORK}/boot.log" 2>&1 || true
if grep -qi "error\|pty.node" "${WORK}/boot.log"; then
  echo "!! boot errors:" >&2
  grep -i "error\|pty.node" "${WORK}/boot.log" >&2
  exit 1
fi
echo "==> verify OK: shell smoke + dsh web boot clean"

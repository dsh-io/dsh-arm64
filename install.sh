#!/usr/bin/env bash
set -euo pipefail

VERSION=""
DEST="${HOME}/.dsh-arm64"
REPO="dsh-io/dsh-arm64"

usage() {
  cat <<'EOF'
Usage: install.sh [--version VERSION] [--dir DIR]
  --version VERSION  Pin a specific release (e.g. 0.1.0-rc.6); default: latest
  --dir DIR          Install directory; default: ~/.dsh-arm64
  --help             Show this help
EOF
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
    --dir) DEST="${2:?--dir needs a value}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done

if [ "$(uname -m)" != "aarch64" ] && [ "$(uname -m)" != "arm64" ]; then
  echo "!! dsh-arm64 targets Linux aarch64 only (got $(uname -m))" >&2
  exit 2
fi

NODE_V="$(node -v 2>/dev/null || true)"
if [ -z "${NODE_V}" ]; then
  echo "!! Node.js >= 22 is required by the dsh runtime. Install Node first." >&2
  exit 2
fi

API="https://api.github.com/repos/${REPO}/releases/${VERSION:+tags/}${VERSION:-latest}"
echo "==> resolving release..."
TAG="$(curl -fsSL "${API}" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
if [ -z "${TAG}" ]; then
  echo "!! could not resolve release (${API})" >&2
  exit 1
fi
echo "==> release ${TAG}"

BASE="https://github.com/${REPO}/releases/download/${TAG}"
TARBALL="dsh-arm64-${TAG#v}.tar.gz"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "==> downloading ${TARBALL}"
curl -fsSL "${BASE}/${TARBALL}" -o "${TMP}/${TARBALL}"
curl -fsSL "${BASE}/sha256sums.txt" -o "${TMP}/sha256sums.txt"

echo "==> verifying sha256"
( cd "${TMP}" && sha256sum -c sha256sums.txt )

mkdir -p "${DEST}"
echo "==> unpacking to ${DEST}"
tar xzf "${TMP}/${TARBALL}" -C "${DEST}"

echo
echo "==> installed to ${DEST}"
echo "    start the harness:   ${DEST}/node_modules/.bin/dsh web"
echo "    first run walks you through API key and profile setup (dsh built-in init)."
echo "    remove it:           rm -rf ${DEST}"
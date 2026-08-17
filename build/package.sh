#!/usr/bin/env bash
set -euo pipefail

STAGE="${1:?usage: package.sh <stage-dir> <out-dir> <version>}"
OUT="${2:?out dir required}"
VERSION="${3:?version required}"

mkdir -p "${OUT}"
cp install.sh "${STAGE}/install.sh"
TARBALL="${OUT}/dsh-arm64-${VERSION}.tar.gz"
tar czf "${TARBALL}" -C "${STAGE}" node_modules install.sh
cd "${OUT}"
sha256sum "dsh-arm64-${VERSION}.tar.gz" > sha256sums.txt
sha256sum -c sha256sums.txt
echo "==> packaged ${TARBALL}"
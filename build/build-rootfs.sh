#!/usr/bin/env bash
set -euo pipefail

BASELINE="${1:-0.1.0-rc.6}"
STAGE="${2:-/tmp/dsh-arm64-rootfs-stage}"
NODE_VERSION="${3:-22.16.0}"
NODE_MIRROR="${NODE_MIRROR:-https://npmmirror.com/mirrors/node}"

if [ "$(uname -m)" != "aarch64" ] && [ "$(uname -m)" != "arm64" ]; then
  echo "!! build-rootfs.sh must run on an arm64 host (got $(uname -m))" >&2
  exit 2
fi
if [ "$(id -u)" != "0" ]; then
  echo "!! build-rootfs.sh needs root (debootstrap)" >&2
  exit 2
fi
command -v debootstrap >/dev/null || {
  echo "!! debootstrap not found (apt install debootstrap)" >&2
  exit 2
}

echo "==> rootfs build: Debian bookworm + node ${NODE_VERSION} + dsh@${BASELINE}"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/rootfs" "${STAGE}/work"
cd "${STAGE}"

# ---- 1. debootstrap bookworm minbase (arm64) ----
debootstrap --variant=minbase --arch=arm64 bookworm rootfs \
  http://mirrors.tuna.tsinghua.edu.cn/debian/ >/dev/null

# ---- 2. trim: docs, man, locales, apt caches ----
rm -rf rootfs/usr/share/doc rootfs/usr/share/man rootfs/usr/share/locale \
  rootfs/usr/share/info rootfs/var/lib/apt/lists rootfs/var/cache/apt/archives/*

# ---- 3. glibc Node 22 (official binary tarball -> /usr/local) ----
curl -fsSL --retry 3 --retry-all-errors \
  -o work/node.tar.xz "${NODE_MIRROR}/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-arm64.tar.xz"
tar -xJf work/node.tar.xz -C rootfs/usr/local --strip-components=1 \
  --exclude='*/CHANGELOG.md' --exclude='*/README.md' --exclude='*/LICENSE' \
  --exclude='*/include' --exclude='*/share/man' --exclude='*/share/doc'
rootfs/usr/local/bin/node --version | grep -q "v${NODE_VERSION}" \
  || { echo "!! node version mismatch" >&2; exit 1; }

# ---- 4. dsh overlay (the existing dsh-arm64 artifact) -> /root/.dsh-arm64 ----
curl -fsSL --retry 3 --retry-all-errors \
  -o work/overlay.tar.gz "https://github.com/dsh-io/dsh-arm64/releases/download/v${BASELINE}/dsh-arm64-${BASELINE}.tar.gz"
mkdir -p rootfs/root/.dsh-arm64
tar -xzf work/overlay.tar.gz -C rootfs/root/.dsh-arm64 \
  --exclude='install.sh'
[ -f rootfs/root/.dsh-arm64/node_modules/@deepseek-ai/dsh/lib/bin.js ] \
  || { echo "!! overlay missing dsh bin.js" >&2; exit 1; }

# ---- 5. mirrors + workspace (moved from the app's runtime applyMirrors) ----
cat > rootfs/etc/apt/sources.list <<'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware
EOF
cat > rootfs/etc/pip.conf <<'EOF'
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
EOF
cat > rootfs/etc/npmrc <<'EOF'
registry=https://registry.npmmirror.com
EOF
mkdir -p rootfs/root/.cargo
cat > rootfs/root/.cargo/config.toml <<'EOF'
[source.crates-io]
replace-with = 'tuna'
[source.tuna]
registry = "sparse+https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/"
EOF
mkdir -p rootfs/etc/profile.d
cat > rootfs/etc/profile.d/dsh-mirrors.sh <<'EOF'
export GOPROXY=https://goproxy.cn,direct
export GO111MODULE=on
EOF
cat > rootfs/root/.bashrc <<'EOF'
export GOPROXY=https://goproxy.cn,direct
export GO111MODULE=on
EOF
cat > rootfs/root/.gemrc <<'EOF'
---
:sources:
- https://mirrors.tuna.tsinghua.edu.cn/rubygems/
EOF
mkdir -p rootfs/root/.config/composer
cat > rootfs/root/.config/composer/config.json <<'EOF'
{
  "repositories": [
    { "type": "composer", "url": "https://mirrors.aliyun.com/composer/" }
  ]
}
EOF
cat > rootfs/root/.condarc <<'EOF'
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
EOF
mkdir -p rootfs/root/projects

# ---- 6. drop device nodes (proot binds the host /dev; device entries
#           break unprivileged tar extraction and Android-side unpack) ----
rm -rf rootfs/dev && mkdir -p rootfs/dev

# ---- 7. package rootfs.tar.xz + sha256 ----
tar -cJf "dsh-arm64-rootfs-${BASELINE}.tar.xz" -C rootfs .
sha256sum "dsh-arm64-rootfs-${BASELINE}.tar.xz" > rootfs.sha256sums
sha256sum -c rootfs.sha256sums
du -h "dsh-arm64-rootfs-${BASELINE}.tar.xz"
echo "==> rootfs build OK"

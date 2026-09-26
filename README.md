# dsh-arm64

Official deployment package for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`) on **Linux aarch64**.

`npm install @deepseek-ai/dsh` pulls a large tree with many platform-specific
native binaries (`node-pty`, `koffi`, `sharp`/`libvips`, `sherpa-onnx`,
`ripgrep`, `libreoffice-kit`, `node-addon-system`...) that npm resolves at
install time — fragile and slow on ARM hardware. This project pre-builds the
full dsh dependency tree (native binaries included) on a GitHub arm64 runner,
and ships the result as a downloadable release.

## Quick install

### Option A — single script (no Node tooling required)

```bash
curl -fsSL https://raw.githubusercontent.com/dsh-io/dsh-arm64/main/install.sh | bash
```

Installs to `~/.dsh-arm64` (use `--dir` and `--version` to change):

```bash
curl -fsSL https://raw.githubusercontent.com/dsh-io/dsh-arm64/main/install.sh | bash -s -- --version 0.1.7-rc.2
```

### Option B — npm thin installer

```bash
npx @dsh-io/dsh-arm64-install@latest
```

Both entries download the release artifact from GitHub Releases, verify its
sha256 checksum, and unpack it — nothing is compiled on your machine.

## Start the harness

```bash
~/.dsh-arm64/node_modules/.bin/dsh web
```

The first run walks you through API key and profile setup using dsh's built-in
initialization (no pre-baked profiles shipped here).

## Requirements

- Linux on `aarch64` (Apple Silicon machines are NOT supported — run `dsh`
  natively on macOS or use an ARM Linux VM/container)
- Node.js >= 22.19 (required by dsh dependencies such as `@deepseek-ai/libreoffice-kit`)
- `curl`, `tar`, `sha256sum`

## How it works

| Piece | Role |
| --- | --- |
| `build/build.sh` | installs `@deepseek-ai/dsh@<VERSION>` on arm64 **offline** from the vendored npm cache; platform binaries land as optional packages, `node-pty` falls back to a source rebuild only if its bundled linux-arm64 prebuild fails |
| `build/verify.sh` | loads both native addons, spawns a real pty, boots `dsh web` headlessly and fails on any native-module error |
| `build/package.sh` | produces `dsh-arm64-<VERSION>.tar.gz` + `sha256sums.txt` |
| `vendor/` | `package-lock.json` + `npm-cache.tar.gz.part-*` (split under GitHub's 100MB file limit) — the integrity-pinned dependency tree; regenerate with `REGENERATE_VENDOR=1 ./build/build.sh <VERSION>` on any networked host |
| `.github/workflows/build.yml` | runs the pipeline on `ubuntu-24.04-arm`, uploads artifacts, publishes the release |
| `install.sh` | zero-dependency installer (parses the GitHub Releases API) |
| `installer/` | `@dsh-io/dsh-arm64-install` npm package (same logic, thin wrapper) |

Releases are tagged `v<VERSION>` where `<VERSION>` matches the bundled dsh
baseline (e.g. `v0.1.7-rc.2` ships `dsh@0.1.7-rc.2`).

## Why not on npm directly?

Installing dsh via npm resolves and fetches dozens of platform-specific
native packages (with source-compile fallbacks), which is exactly the
failure/dependency burden this project exists to avoid — so the runtime
itself is never published to npm. Only the thin installer (which downloads a
prebuilt artifact) lives there.

## Verify a release manually

```bash
curl -fsSLo /tmp/d.tgz https://github.com/dsh-io/dsh-arm64/releases/download/v0.1.7-rc.2/dsh-arm64-0.1.7-rc.2.tar.gz
curl -fsSLo /tmp/s.txt https://github.com/dsh-io/dsh-arm64/releases/download/v0.1.7-rc.2/sha256sums.txt
(cd /tmp && sha256sum -c s.txt) && tar xzf /tmp/d.tgz -C ~/.dsh-arm64
```

## Roadmap

- Termux/Android aarch64 packaging
- Windows arm64 (node-pty ships win32-arm64 prebuilds upstream, pending dsh itself)

## License

MIT. `dsh-arm64` is an independent distribution of DeepSeek Harness, which is
itself MIT-licensed. This project is not affiliated with DeepSeek.

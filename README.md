# dsh-arm64

Official deployment package for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`) on **Linux aarch64**.

dsh bundles `node-pty`, which compiles from source at install time and ships no
prebuilt binary for Linux arm64 — so `npm install` fails on ARM hardware. This
project pre-builds the full dsh dependency tree (including a compiled `pty.node`)
on a GitHub arm64 runner, and ships the result as a downloadable release.

## Quick install

### Option A — single script (no Node tooling required)

```bash
curl -fsSL https://raw.githubusercontent.com/dsh-io/dsh-arm64/main/install.sh | bash
```

Installs to `~/.dsh-arm64` (use `--dir` and `--version` to change):

```bash
curl -fsSL https://raw.githubusercontent.com/dsh-io/dsh-arm64/main/install.sh | bash -s -- --version 0.1.0-rc.6
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
- Node.js >= 22 (used by the dsh runtime itself)
- `curl`, `tar`, `sha256sum`

## How it works

| Piece | Role |
| --- | --- |
| `build/build.sh` | installs `@deepseek-ai/dsh@<VERSION>` on arm64, rebuilds `node-pty` from source |
| `build/verify.sh` | boots `dsh web` headlessly and fails on any `node-pty` error |
| `build/package.sh` | produces `dsh-arm64-<VERSION>.tar.gz` + `sha256sums.txt` |
| `.github/workflows/build.yml` | runs the pipeline on `ubuntu-24.04-arm`, uploads artifacts |
| `install.sh` | zero-dependency installer (parses the GitHub Releases API) |
| `installer/` | `@dsh-io/dsh-arm64-install` npm package (same logic, thin wrapper) |

Releases are tagged `v<VERSION>` where `<VERSION>` matches the bundled dsh
baseline (e.g. `v0.1.0-rc.6` ships `dsh@0.1.0-rc.6`).

## Why not on npm directly?

Installing dsh via npm triggers `node-pty`'s postinstall compile step, which is
exactly the failure this project exists to avoid — so the runtime itself is never
published to npm. Only the thin installer (which downloads a prebuilt artifact)
lives there.

## Verify a release manually

```bash
curl -fsSLo /tmp/d.tgz https://github.com/dsh-io/dsh-arm64/releases/download/v0.1.0-rc.6/dsh-arm64-0.1.0-rc.6.tar.gz
curl -fsSLo /tmp/s.txt https://github.com/dsh-io/dsh-arm64/releases/download/v0.1.0-rc.6/sha256sums.txt
(cd /tmp && sha256sum -c s.txt) && tar xzf /tmp/d.tgz -C ~/.dsh-arm64
```

## Roadmap

- Termux/Android aarch64 packaging
- Windows arm64 (node-pty ships win32-arm64 prebuilds upstream, pending dsh itself)
- Automatic release publication from CI

## License

MIT. `dsh-arm64` is an independent distribution of DeepSeek Harness, which is
itself MIT-licensed. This project is not affiliated with DeepSeek.
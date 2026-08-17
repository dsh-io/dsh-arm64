# dsh-arm64 — Design

Date: 2026-08-17
Status: Approved (user: "可以，没有问题", after npm-entry correction)

## Positioning

Official dsh-io deployment package for DeepSeek Harness on **Linux aarch64**. Solves the trust
shortfall of community packs (hand-built binaries, no audit trail): every artifact is built from
source in public CI, ships with sha256 checksums, and installs through a double entry (npm thin
installer + zero-dep shell script).

## Why artifacts on GitHub Releases, not npm

- npm installing `@deepseek-ai/dsh` triggers node-pty's postinstall compile — an npm-distributed
  artifact would force the very compilation the package promises to avoid
- Upstream broken peer chain (`dsh-type-meta` 404) adds failure surface to npm install paths
- Large artifact (dependency tree + prebuilt pty.node) is not what npm is for

npm is used only for the **thin installer entry** (~KB, no binaries).

## Architecture

```
dsh-arm64/
├── .github/workflows/build.yml   # CI reproducible build pipeline
├── build/
│   ├── build.sh                  # install dsh baseline + compile node-pty (arm64) + assemble tree
│   ├── verify.sh                 # smoke: load pty.node + boot dsh web without node-pty errors
│   └── package.sh                # tarball + sha256sums.txt
├── installer/                    # npm thin installer package (@dsh-io/dsh-arm64-install)
│   ├── package.json
│   └── bin/dsh-arm64-install.mjs
├── install.sh                    # zero-dep fallback entry (download → verify → unpack → configure)
├── profiles/                     # headless/web profile config templates
└── README.md
```

## Build pipeline (reproducible, auditable)

1. Trigger: `v*` tag push or manual `workflow_dispatch`
2. Runner: GitHub hosted **arm64** runner (`ubuntu-24.04-arm`; fallback: qemu emulation on x64)
3. Steps:
   - Node 22 (via actions/setup-node)
   - `npm install @deepseek-ai/dsh@0.1.0-rc.6` (pinned baseline; npm skips the broken peer gracefully)
   - `npm rebuild node-pty` → compiles `pty.node` from source on arm64
   - `build/verify.sh`: `node -e "require('node-pty')"` loads; `timeout 60 dsh web` boots without
     node-pty errors
   - `build/package.sh`: tarball (dsh tree + prebuilt pty.node + profiles + install.sh) + `sha256sums.txt`
   - `gh release create` with assets + checksums; every log line public

## Installer entries (equivalent, shared logic)

### npm thin installer — `@dsh-io/dsh-arm64-install`

`npx @dsh-io/dsh-arm64-install@latest` (or `--version 0.1.0-rc.6` to pin):
1. Resolve latest release (or pinned) via GitHub Releases API
2. Download tarball + `sha256sums.txt`
3. Verify checksum (abort on mismatch)
4. Unpack to `~/.dsh-arm64`
5. Print API-key configuration hint and `dsh` start command

The installer always resolves release metadata via the GitHub API — it never hardcodes tarball URLs.

### Zero-dep entry — `bash install.sh` (in repo and inside every release tarball)

Same flow, plain bash + curl; for machines without Node (installer itself needs only bash;
target dsh runtime still requires Node ≥ 22).

## Version policy

- Baseline pinned: `@deepseek-ai/dsh@0.1.0-rc.6` (first known-good official baseline)
- Baseline bump = new tag `v<dsh-baseline-version>` (e.g. `v0.1.0-rc.6`) on this repo → new CI build
  + release; npm installer package keeps its own independent semver, bumped on each release

## Scope boundaries

- Linux aarch64 (Ubuntu/Debian family) only for v0.1.0; Termux and Docker images are follow-ups
- Independent repo; no dependency on dsh-dev / dsh-plugin-skill / identity-sentinel
- No npm distribution of binaries — artifacts exclusively on GitHub Releases

## Error handling

- install.sh / installer: every step checks exit status; checksum mismatch aborts with clear message
- verify.sh failures fail the CI job (no release published)
- Missing Node on target: installer refuses with pointer to install Node ≥ 22

## Testing

- CI: verify.sh smoke test gates the release (pty.node load + dsh web boot)
- Installer logic: dry-run mode (`--print-plan`) + checksum-mismatch test in CI
- install.sh: tested in CI via `bash -n` (syntax) + one clean-environment container run if runner allows

## Toolchain & standards

- Bash 5 (no bashisms beyond `set -euo pipefail`), Node 22 + ESM for installer, npm for packaging
- English CLI output; exit codes 0/1/2 (0 ok, 1 runtime error, 2 usage error)

## Deliverables

- GitHub repo `dsh-io/dsh-arm64` (public), topics: `deepseek-harness`, `arm64`, `deployment`, `dsh`
- GitHub Releases artifacts (tarball + sha256sums.txt) per tagged baseline
- npm package `@dsh-io/dsh-arm64-install` (public, thin)
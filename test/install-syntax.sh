#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "==> syntax check"
bash -n ../install.sh
echo "==> usage error check (expect exit 2)"
bash ../install.sh --bogus 2>/dev/null && { echo "FAIL: expected exit 2"; exit 1; }
echo "==> help exits 0"
bash ../install.sh --help >/dev/null
echo "==> all checks passed"
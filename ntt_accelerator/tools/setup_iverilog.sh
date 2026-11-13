#!/bin/sh
# Debian/Ubuntu/WSL: download official distro package; no sudo/system install.
set -eu
PROJECT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$PROJECT_DIR/build/tools"
cd "$PROJECT_DIR/build/tools"
command -v apt-get >/dev/null
command -v dpkg-deb >/dev/null
apt-get download iverilog
set -- ./iverilog_*.deb
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo 'Expected exactly one Icarus package in build/tools; inspect that directory.' >&2
  exit 1
fi
dpkg-deb -x "$1" iverilog
sha256sum "$1" > iverilog-package.sha256
echo 'Local Icarus installed. Run: python3 tools/run_tests.py'

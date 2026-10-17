#!/usr/bin/env bash
# Stops any running instance, rebuilds the bundle and launches it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pkill -x Wallflower || true
"$ROOT/scripts/bundle.sh"
open "$ROOT/build/Wallflower.app"

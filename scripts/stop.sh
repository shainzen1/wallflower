#!/usr/bin/env bash
# Stops the running app, if any.
set -euo pipefail

pkill -x Wallflower || true

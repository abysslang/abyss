#!/usr/bin/env bash
set -euo pipefail

exec "${CC:-gcc}" -no-pie "$@" -lm -pthread

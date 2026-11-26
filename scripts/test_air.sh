#!/usr/bin/env bash
set -euo pipefail

compiler=$1
cc=$2
work=$3
mkdir -p "$work"

timeout 10 "$compiler" r tests/compiler/air_cfg.a > "$work/cfg.vm.out"
diff -u tests/compiler/air_cfg.out "$work/cfg.vm.out"
"$compiler" b tests/compiler/air_cfg.a "$work/cfg.c"
"$cc" -std=c99 -D_POSIX_C_SOURCE=200809L "$work/cfg.c" -o "$work/cfg"
timeout 10 "$work/cfg" > "$work/cfg.native.out"
diff -u tests/compiler/air_cfg.out "$work/cfg.native.out"

"$compiler" --dump-air > "$work/demo.out"
diff -u - "$work/demo.out" <<'AIR'
air add
b0:
  v0 = param i32 0
  v1 = param i32 1
  v2 = iadd i32 v0, v1
  ret v2
AIR

cat > "$work/functions.a" <<'ABYSS'
sum :: fn(left, right, last i32) i32 { ret right + (last + left) }
sub :: fn(left, right i32) i32 { left - right }
ABYSS

"$compiler" --dump-air "$work/functions.a" sum > "$work/custom.out"
diff -u - "$work/custom.out" <<'AIR'
air sum
b0:
  v0 = param i32 0
  v1 = param i32 1
  v2 = param i32 2
  v3 = iadd i32 v2, v0
  v4 = iadd i32 v1, v3
  ret v4
AIR

if "$compiler" --dump-air "$work/functions.a" sub > "$work/unsupported.log" 2>&1; then
    exit 1
fi
grep -Fq 'AIR expects an i32 parameter or addition' "$work/unsupported.log"

if "$compiler" --dump-air "$work/functions.a" missing > "$work/missing.log" 2>&1; then
    exit 1
fi
grep -Fq "function 'missing' not found" "$work/missing.log"

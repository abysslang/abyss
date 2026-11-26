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
b0(v0: i32, v1: i32):
  v2 = iadd i32 v0, v1
  ret v2
AIR

cat > "$work/functions.a" <<'ABYSS'
sum :: fn(left, right, last i32) i32 { ret right + (last + left) }
sub :: fn(left, right i32) i32 { left - right }
select :: fn(flag bool, left, right i32) i32 { if flag { left + right } else { right } }
ABYSS

"$compiler" --dump-air "$work/functions.a" sum > "$work/custom.out"
diff -u - "$work/custom.out" <<'AIR'
air sum
b0(v0: i32, v1: i32, v2: i32):
  v3 = iadd i32 v2, v0
  v4 = iadd i32 v1, v3
  ret v4
AIR

"$compiler" --dump-air "$work/functions.a" select > "$work/select.out"
diff -u - "$work/select.out" <<'AIR'
air select
b0(v0: i1, v1: i32, v2: i32):
  branch v0, b1, b2
b1:
  v4 = iadd i32 v1, v2
  jump b3(v4)
b2:
  jump b3(v2)
b3(v7: i32):
  ret v7
AIR

if "$compiler" --dump-air "$work/functions.a" sub > "$work/unsupported.log" 2>&1; then
    exit 1
fi
grep -Fq 'AIR expects a parameter, addition, or if expression' "$work/unsupported.log"

if "$compiler" --dump-air "$work/functions.a" missing > "$work/missing.log" 2>&1; then
    exit 1
fi
grep -Fq "function 'missing' not found" "$work/missing.log"

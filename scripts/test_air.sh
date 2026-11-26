#!/usr/bin/env bash
set -euo pipefail

compiler=$1
work=$2
mkdir -p "$work"

"$compiler" --dump-air > "$work/demo.out"
diff -u - "$work/demo.out" <<'AIR'
air add
b0(v0: i32, v1: i32):
  v2 = stack 4, align 4
  store v2, v0
  v3 = stack 4, align 4
  store v3, v1
  v4 = load i32 v2
  v5 = load i32 v3
  v6 = iadd i32 v4, v5
  ret v6
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
  v3 = stack 4, align 4
  store v3, v0
  v4 = stack 4, align 4
  store v4, v1
  v5 = stack 4, align 4
  store v5, v2
  v6 = load i32 v4
  v7 = load i32 v5
  v8 = load i32 v3
  v9 = iadd i32 v7, v8
  v10 = iadd i32 v6, v9
  ret v10
AIR

"$compiler" --dump-air "$work/functions.a" select > "$work/select.out"
diff -u - "$work/select.out" <<'AIR'
air select
b0(v0: i1, v1: i32, v2: i32):
  v3 = stack 1, align 1
  store v3, v0
  v4 = stack 4, align 4
  store v4, v1
  v5 = stack 4, align 4
  store v5, v2
  v6 = load i1 v3
  branch v6, b1, b2
b1:
  v8 = load i32 v4
  v9 = load i32 v5
  v10 = iadd i32 v8, v9
  jump b3(v10)
b2:
  v11 = load i32 v5
  jump b3(v11)
b3(v7: i32):
  ret v7
AIR

"$compiler" --dump-air "$work/functions.a" > "$work/module.out"
grep -Fq 'air @1 sum(i32, i32, i32) -> i32' "$work/module.out"
grep -Fq 'air @2 sub(i32, i32) -> i32' "$work/module.out"
grep -Fq 'sub i32' "$work/module.out"
grep -Fq 'air @3 select(i1, i32, i32) -> i32' "$work/module.out"

if "$compiler" --dump-air "$work/functions.a" missing > "$work/missing.log" 2>&1; then
    exit 1
fi
grep -Fq "function 'missing' not found" "$work/missing.log"

cat > "$work/edges.a" <<'ABYSS'
keel :: @import("pods/keel")
c99 :: @import("pods/keel/target/c99")
abi :: @import("pods/keel/abi_types")
Arena :: @import("std/allocator").Arena
Os :: @import("core/target").Os
Ty :: keel.Ty
Val :: keel.Val

main :: fn() {
    air := keel.Program.new()
    body := keel.Function.new()
    ty := Ty.i32_
    param_types: [3]Ty = .[ty, ty, Ty.i1]
    params: Slice(Ty) = .{ ptr: &param_types[0], len: 3 }
    entry := body.block()
    repeat := body.block_with_params(params)
    done := body.block()
    body.begin(entry)
    one := body.constant(ty, 1)
    two := body.constant(ty, 2)
    again := body.constant(Ty.i1, 1)
    initial: [3]Val = .[one, two, again]
    args: Slice(Val) = .{ ptr: &initial[0], len: 3 }
    body.jump_with_args(repeat, args)
    body.begin(repeat)
    left := body.parameter(repeat, 0)
    right := body.parameter(repeat, 1)
    stop := body.constant(Ty.i1, 0)
    next: [3]Val = .[right, left, stop]
    swapped: Slice(Val) = .{ ptr: &next[0], len: 3 }
    body.branch_with_args(body.parameter(repeat, 2), repeat, swapped, done, Slice(Val).empty())
    body.begin(done)
    body.ret_value(body.binary(keel.Op.sub, left, right))
    symbol := air.declare("swap", Slice(Ty).empty(), ty, false)
    air.define(symbol, body)
    air.declarations.ptr_at(0).exported = true
    result := abi.Type.new(abi.Kind.scalar)
    result.scalar = ty
    air.abi_types.push(result)
    signature := abi.Type.new(abi.Kind.function)
    signature.inner = 1
    air.abi_types.push(signature)
    air.declarations.ptr_at(0).abi_signature = 2
    arena := Arena.new(4096)
    @import("std/io").write_str(c99.emit(&arena, &air, Os.linux, false))
    air.destroy()
    arena.destroy()
}
ABYSS
"$compiler" b "$work/edges.a" "$work/emit_edges.c"
"${CC:-gcc}" -std=gnu99 -O2 "$work/emit_edges.c" -o "$work/emit_edges"
"$work/emit_edges" > "$work/edges.c"
printf 'int main(void) { return swap() != 1; }\n' >> "$work/edges.c"
"${CC:-gcc}" -std=gnu99 -O2 "$work/edges.c" -o "$work/edges"
timeout 5s "$work/edges"

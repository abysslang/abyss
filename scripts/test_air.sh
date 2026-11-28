#!/usr/bin/env bash
set -euo pipefail

compiler=$1
work=$2
mkdir -p "$work"

"$compiler" --dump-air > "$work/demo.out"
diff -u - "$work/demo.out" <<'AIR'
air add
b0(v0: i32, v1: i32):
  v6 = iadd i32 v0, v1
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
  v9 = iadd i32 v2, v0
  v10 = iadd i32 v1, v9
  ret v10
AIR

"$compiler" --dump-air "$work/functions.a" select > "$work/select.out"
diff -u - "$work/select.out" <<'AIR'
air select
b0(v0: i1, v1: i32, v2: i32):
  branch v0, b1, b3(v2)
b1:
  v10 = iadd i32 v1, v2
  jump b3(v10)
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

for name in diamond swap_loop folded; do
    "$compiler" --dump-air "$PWD/tests/air_optimizations.a" "$name" > "$work/$name.air"
    if grep -Eq ' = (stack|load) |^  store ' "$work/$name.air"; then
        cat "$work/$name.air"
        exit 1
    fi
done
grep -Eq '^b[1-9][0-9]*\(v[0-9]+: i32\):' "$work/diamond.air"
grep -Eq '^b[1-9][0-9]*\(v[0-9]+: i32, v[0-9]+: i32, v[0-9]+: i32\):' "$work/swap_loop.air"
grep -Fq '= const i32 42' "$work/folded.air"
if grep -Eq ' = (iadd|mul|shr|cast) ' "$work/folded.air"; then
    cat "$work/folded.air"
    exit 1
fi
"$compiler" --dump-air "$PWD/tests/air_optimizations.a" escaped > "$work/escaped.air"
grep -Fq '= stack 4, align 4' "$work/escaped.air"
grep -Fq '= load i32' "$work/escaped.air"

"$compiler" --dump-air "$PWD/tests/air_optimizations.a" dce_chain > "$work/dce_chain.air"
if grep -Eq ' = (mul|xor|stack|load) |^  store ' "$work/dce_chain.air"; then
    cat "$work/dce_chain.air"
    exit 1
fi
if [ "$(grep -cE '^b[0-9]+' "$work/dce_chain.air")" -ne 1 ]; then
    cat "$work/dce_chain.air"
    exit 1
fi

"$compiler" --dump-air "$PWD/tests/air_optimizations.a" dead_loop_var > "$work/dead_loop_var.air"
if ! grep -Eq '^b[1-9][0-9]*\(v[0-9]+: i32, v[0-9]+: i32\):$' "$work/dead_loop_var.air"; then
    cat "$work/dead_loop_var.air"
    exit 1
fi

"$compiler" --dump-air "$PWD/tests/air_optimizations.a" cfg_simplify > "$work/cfg_simplify.air"
if grep -Eq 'mul|invert|99' "$work/cfg_simplify.air"; then
    cat "$work/cfg_simplify.air"
    exit 1
fi

"$compiler" --dump-air "$PWD/tests/air_optimizations.a" keep_effects > "$work/keep_effects.air"
grep -Fq 'div i32' "$work/keep_effects.air"

cat > "$work/prune.a" <<'ABYSS'
dead_helper :: fn(x i32) i32 { x * 77 + 1 }
live_helper :: fn(x i32) i32 {
    if x < 0 { ret -x }
    x + 1
}
main :: fn() {
    a := if 1 > 2 { dead_helper(3) } else { live_helper(4) }
    print(a)
}
ABYSS
"$compiler" --dump-air "$work/prune.a" > "$work/prune.air"
if grep -Fq 'dead_helper' "$work/prune.air"; then
    cat "$work/prune.air"
    exit 1
fi
grep -Fq 'live_helper' "$work/prune.air"

cat > "$work/edges.a" <<'ABYSS'
keel :: @import("pods/keel")
c99 :: @import("pods/keel/target/c99")
mem2reg :: @import("pods/keel/opt/mem2reg")
fall :: @import("std/sys").fall
abi :: @import("pods/keel/abi_types")
Arena :: @import("std/allocator").Arena
Os :: @import("core/target").Os
Ty :: keel.Ty
Val :: keel.Val

preserve :: fn() i32 {
    body := keel.Function.new()
    block := body.block()
    body.begin(block)
    location := body.stack(4, 4)
    value := body.load(Ty.i32_, location)
    body.store(location, body.constant(Ty.i32_, 1))
    body.ret_value(value)
    changed := mem2reg.run(&body, 8)
    body.destroy()
    if changed { 1 } else { 0 }
}

main :: fn() {
    if preserve() != 0 { #fall }
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

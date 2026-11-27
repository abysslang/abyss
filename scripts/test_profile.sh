#!/usr/bin/env bash
set -euo pipefail

compiler=$1
work=$2
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$work"

cat > "$work/value.a" <<'ABYSS'
value :: fn() i32 { 17 }
ABYSS
cat > "$work/main.a" <<'ABYSS'
other :: @import("./value")
identity :: fn(T type, value T) T { value }
offset :: fn() i32 { 5 }

main :: fn() {
    value := cmpt { offset() }
    print(identity(other.value() + value))
}
ABYSS
"$compiler" b "$work/main.a" "$work/plain.c"
"$compiler" b --profile=tsv "$work/main.a" "$work/detailed.c" 2>"$work/detailed.tsv"
"$compiler" b --profile=summary "$work/main.a" "$work/summary.c" 2>"$work/summary.tsv"
cmp "$work/plain.c" "$work/detailed.c"
cmp "$work/plain.c" "$work/summary.c"
[[ $("$compiler" r --profile=tsv "$work/main.a" 2>"$work/vm.tsv") == 22 ]]
"$compiler" b --profile "$work/main.a" "$work/human.c" 2>"$work/human.txt"
rg -q '^Compile: .* ms .* lines/s' "$work/human.txt"
rg -q 'type checker and comptime' "$work/human.txt"
rg -q 'unification \(subset of type\)' "$work/human.txt"
if "$compiler" b --profile=unknown "$work/main.a" "$work/invalid.c" 2>"$work/invalid.txt"; then
    exit 1
fi
rg -q -- '--profile expects' "$work/invalid.txt"

if [[ ${ABYSS_TEST_OBJECT:-false} == true ]]; then
    "$compiler" b --emit-obj --hosted "$work/main.a" "$work/plain.o"
    "$compiler" b --emit-obj --hosted --profile=tsv "$work/main.a" "$work/detailed.o" 2>"$work/elf.tsv"
    cmp "$work/plain.o" "$work/detailed.o"
fi

cat > "$work/clock.a" <<'ABYSS'
time :: @import("std/time")

main :: fn() i32 {
    if not time.supported() { ret 1 }
    start := time.Instant.now()
    end := time.Instant.try_now()
    if end.is_none() or end.unwrap().checked_duration_since(start).is_none() { ret 2 }
    if start.duration_since(start).as_nanos() != 0 { ret 3 }
    earlier: time.Instant = .{ ticks: 1 }
    later: time.Instant = .{ ticks: 3000000001 }
    if earlier.checked_duration_since(later).is_some() { ret 4 }
    if earlier.duration_since(later).as_nanos() != 0 { ret 5 }
    interval := later.duration_since(earlier)
    if interval.as_nanos() != 3000000000 or interval.as_millis() != 3000.0 or interval.as_secs() != 3.0 {
        ret 6
    }
    start.elapsed()
    0
}
ABYSS
"$compiler" b "$work/clock.a" "$work/clock.c"
"${CC:-cc}" -std=gnu99 -D_POSIX_C_SOURCE=200809L "$work/clock.c" -o "$work/clock"
"$work/clock"

PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$root/scripts" python3 - "$work" <<'PY'
from pathlib import Path
import sys

from bench import parse_profile

work = Path(sys.argv[1])
profile = parse_profile((work / "detailed.tsv").read_text(), True)
summary = parse_profile((work / "summary.tsv").read_text(), False)
assert not summary["phases"]
for key in ("lines", "files", "source_bytes"):
    assert profile[key] == summary[key] and profile[key] > 0
assert profile["files"] >= 2
assert set(profile["phases"]) >= {
    "frontend/lex", "frontend/parse", "frontend/modules", "type/check",
    "type/unify_bind", "type/specialize", "comptime/vm", "backend/lower",
    "backend/mem2reg", "backend/fold", "backend/dce", "backend/cfg", "backend/c99_body",
}
assert all(row["inclusive_ns"] >= row["self_ns"] for row in profile["phases"].values())
vm = parse_profile((work / "vm.tsv").read_text(), True)
assert set(vm["phases"]) >= {"backend/vm_lower", "backend/vm_link"}
assert "backend/c99" not in vm["phases"]
elf = work / "elf.tsv"
if elf.exists():
    native = parse_profile(elf.read_text(), True)
    assert set(native["phases"]) >= {"backend/elf_body", "backend/regalloc", "backend/elf_write"}
PY

for _ in 1 2; do
    python3 "$root/scripts/bench.py" "$work/main.a" --runs 2 --warmup 1 --profile-runs 1 \
        --compiler "$compiler" --records "$work/records" >"$work/bench.log"
done
python3 - "$work/records" <<'PY'
import json
from pathlib import Path
import sys

records = Path(sys.argv[1])
runs = [json.loads(path.read_text()) for path in records.glob("runs/*/*.json")]
assert len(runs) == 2 and len({row["run_id"] for row in runs}) == 2
daily = [json.loads(path.read_text()) for path in records.glob("????-??-??.json")]
for day in daily:
    scores = [row for row in runs if row["started_at"].startswith(day["date"])]
    best, = day["best"].values()
    assert best["run_id"] == min(scores, key=lambda row: row["statistics"]["compile_ns"]["mean"])["run_id"]
    assert (records / best["archive"]).is_file()
assert all(len(row["samples"]) == 2 and len(row["profile_samples"]) == 1 for row in runs)
PY

import argparse
import datetime
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parent.parent
NS_PER_MS = 1_000_000
NS_PER_SECOND = 1_000_000_000
BYTES_PER_MIB = 1_048_576


def nonnegative(value):
    number = int(value)
    if number < 0:
        raise argparse.ArgumentTypeError("expected a nonnegative integer")
    return number


def positive(value):
    number = nonnegative(value)
    if number == 0:
        raise argparse.ArgumentTypeError("expected a positive integer")
    return number


def statistics_for(values):
    ordered = sorted(values)
    return {
        "mean": statistics.fmean(ordered),
        "median": statistics.median(ordered),
        "min": ordered[0],
        "max": ordered[-1],
        "stdev": statistics.pstdev(ordered),
        "p95": ordered[math.ceil(len(ordered) * 0.95) - 1],
    }


def checked(command):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(
            f"{Path(command[0]).name} exited with status {result.returncode}\n"
            f"{result.stdout}{result.stderr}"
        )
    return result


def parse_profile(stderr, detailed):
    found = False
    summary = None
    phases = {}
    for line in stderr.splitlines():
        row = line.split("\t")
        if row[0] == "abyss-profile":
            if found or row != ["abyss-profile", "1"]:
                raise ValueError("unsupported or repeated compiler profile header")
            found = True
        elif found and row[0] == "summary":
            if summary is not None or len(row) != 6:
                raise ValueError("invalid compiler profile summary")
            summary = dict(zip(("compile_ns", "lines", "files", "source_bytes", "peak_rss_bytes"), map(int, row[1:])))
        elif found and row[0] == "phase":
            if len(row) != 5 or row[1] in phases:
                raise ValueError("invalid compiler profile phase")
            phases[row[1]] = dict(zip(("self_ns", "inclusive_ns", "spans"), map(int, row[2:])))
    if summary is None or summary["compile_ns"] <= 0:
        raise ValueError("compiler did not report a valid profile; use a current abyssc")
    if detailed and sum(item["self_ns"] for item in phases.values()) != summary["compile_ns"]:
        raise ValueError("phase times do not sum to the profiled compile time")
    summary["phases"] = phases
    return summary


def sample(compiler, flags, source, output, detailed=False):
    mode = "tsv" if detailed else "summary"
    command = [str(compiler), "b", *flags, f"--profile={mode}", str(source), str(output)]
    started = time.perf_counter_ns()
    result = checked(command)
    elapsed = time.perf_counter_ns() - started
    measurement = parse_profile(result.stderr, detailed)
    measurement["process_ns"] = elapsed
    measurement["output_bytes"] = output.stat().st_size
    return measurement


def aggregate(runs, detailed_runs):
    totals = {
        name: statistics_for([run[name] for run in runs])
        for name in ("compile_ns", "process_ns", "peak_rss_bytes")
    }
    totals["lines_per_second"] = statistics_for(
        [run["lines"] * NS_PER_SECOND / run["compile_ns"] for run in runs]
    )
    phases = {}
    groups = {}
    if detailed_runs:
        profiled_ns = sum(run["compile_ns"] for run in detailed_runs)
        totals["profiled_ns"] = statistics_for([run["compile_ns"] for run in detailed_runs])
        for name in sorted(set().union(*(run["phases"] for run in detailed_runs))):
            values = [run["phases"].get(name, {}) for run in detailed_runs]
            item = {key: statistics.fmean(value.get(key, 0) for value in values)
                    for key in ("self_ns", "inclusive_ns", "spans")}
            item["share_percent"] = sum(value.get("self_ns", 0) for value in values) * 100 / profiled_ns
            phases[name] = item
            group = name.split("/", 1)[0]
            keys = [group]
            if name.startswith("type/unify_"):
                keys.append("unification (subset of type)")
            if group in ("type", "comptime"):
                keys.append("type checker and comptime")
            for key in keys:
                total = groups.setdefault(key, {"self_ns": 0.0, "share_percent": 0.0})
                total["self_ns"] += item["self_ns"]
                total["share_percent"] += item["share_percent"]
    return totals, phases, groups


def write_json(path, value):
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(value, stream, indent=2, sort_keys=True, allow_nan=False)
            stream.write("\n")
        except BaseException:
            temporary.unlink()
            raise
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def archive(directory, record):
    day = record["started_at"][:10]
    runs = directory / "runs" / day
    runs.mkdir(parents=True, exist_ok=True)
    run_path = runs / f"{record['run_id']}.json"
    write_json(run_path, record)
    daily = directory / f"{day}.json"
    with (directory / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        best = json.loads(daily.read_text()) if daily.exists() else {"schema": 1, "date": day, "best": {}}
        key = json.dumps(record["workload"], sort_keys=True)
        current = best["best"].get(key)
        if current is None or record["statistics"]["compile_ns"]["mean"] < current["statistics"]["compile_ns"]["mean"]:
            best["best"][key] = {**record, "archive": str(run_path.relative_to(directory))}
            write_json(daily, best)
            improved = True
        else:
            improved = False
    return run_path, daily, improved


def display(record):
    totals = record["statistics"]
    compile_stats = totals["compile_ns"]
    print(f"\n{record['workload']['source']} | {record['workload']['producer']} compiler → "
          f"{record['workload']['target']} | {record['runs']} runs, {record['warmups']} warmups")
    print(f"Compile: {compile_stats['mean']/NS_PER_MS:.3f} ms mean | "
          f"{compile_stats['median']/NS_PER_MS:.3f} median | {compile_stats['min']/NS_PER_MS:.3f} min | "
          f"{compile_stats['max']/NS_PER_MS:.3f} max | {compile_stats['p95']/NS_PER_MS:.3f} p95 | "
          f"{compile_stats['stdev']/NS_PER_MS:.3f} stddev")
    print(f"Process: {totals['process_ns']['mean']/NS_PER_MS:.3f} ms mean | "
          f"{totals['lines_per_second']['mean']:,.0f} lines/s mean | "
          f"{record['lines']:,} lines in {record['files']} files | {record['output_bytes']:,} output bytes")
    rss = totals["peak_rss_bytes"]
    print(f"Peak RSS: {rss['max']/BYTES_PER_MIB:.2f} MiB max | {rss['mean']/BYTES_PER_MIB:.2f} MiB mean"
          if rss["max"] else "Peak RSS: unavailable on this compiler host")
    if record["phases"]:
        print(f"\nDetailed profile ({record['profile_runs']} separate runs, "
              f"{totals['profiled_ns']['mean']/NS_PER_MS:.3f} ms mean)")
        print(f"{'Phase':<30} {'Self ms':>12} {'Share':>9} {'Inclusive ms':>14} {'Mean spans':>12}")
        for name, item in record["phases"].items():
            print(f"{name:<30} {item['self_ns']/NS_PER_MS:12.3f} {item['share_percent']:8.2f}% "
                  f"{item['inclusive_ns']/NS_PER_MS:14.3f} {item['spans']:12.1f}")
        print("\nGroup totals (exclusive)")
        for name, item in record["groups"].items():
            print(f"{name:<30} {item['self_ns']/NS_PER_MS:12.3f} {item['share_percent']:8.2f}%")


def main():
    parser = argparse.ArgumentParser(description="Benchmark the Abyss compiler and record the best result per UTC day.")
    parser.add_argument("source", nargs="?", type=Path, default=ROOT / "compiler/main.a")
    parser.add_argument("--runs", type=positive, default=5)
    parser.add_argument("--warmup", type=nonnegative, default=2, metavar="COUNT")
    parser.add_argument("--profile-runs", type=nonnegative, default=3, metavar="COUNT")
    parser.add_argument("--elf", action="store_true", help="benchmark a compiler built and linked from its own ELF output")
    parser.add_argument("--target", choices=("c99", "elf"), help="emission target; defaults to ELF with --elf and C99 otherwise")
    parser.add_argument("--records", type=Path, default=ROOT / "benchmarks")
    parser.add_argument("--compiler", type=Path, default=os.environ.get("ABYSS_COMPILER") or ROOT / "tmp/abyssc-current")
    parser.add_argument("--library", action="store_true", help="compile a library instead of an executable")
    args = parser.parse_args()
    original = Path(os.environ.get("ABYSS_BENCH_CWD", os.getcwd()))
    source = (original / args.source).resolve()
    compiler = (original / args.compiler).resolve()
    records = (original / args.records).resolve()
    target = args.target or ("elf" if args.elf else "c99")
    if not source.is_file():
        parser.error(f"source file not found: {source}")
    if not compiler.is_file():
        parser.error(f"compiler not found: {compiler}")
    if (args.elf or target == "elf") and (platform.system(), platform.machine()) != ("Linux", "x86_64"):
        parser.error("ELF benchmarking requires a Linux x86-64 host")
    flags = (["--emit-obj"] + ([] if args.library else ["--hosted"])) if target == "elf" else []
    if args.library:
        flags.append("--library")
    os.environ["ABYSS_DEV"] = str(ROOT)
    (ROOT / "tmp").mkdir(exist_ok=True)
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True)
    started_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with tempfile.TemporaryDirectory(prefix="bench.", dir=ROOT / "tmp") as directory:
        work = Path(directory)
        if args.elf:
            print("Building the benchmark compiler through ELF…", flush=True)
            obj = work / "compiler.o"
            native = work / "abyssc"
            checked([str(compiler), "b", "--emit-obj", "--hosted", str(ROOT / "compiler/main.a"), str(obj)])
            checked(["bash", str(ROOT / "scripts/link_object.sh"), str(obj), "-o", str(native)])
            compiler = native
        output = work / ("output.o" if target == "elf" else "output.c")
        print(f"Running {args.warmup} warmups, {args.runs} timing runs, and {args.profile_runs} profile runs…", flush=True)
        for _ in range(args.warmup):
            sample(compiler, flags, source, output)
        runs = [sample(compiler, flags, source, output) for _ in range(args.runs)]
        detailed = [sample(compiler, flags, source, output, detailed=True) for _ in range(args.profile_runs)]
        for name in ("lines", "files", "source_bytes", "output_bytes"):
            if len({run[name] for run in runs + detailed}) != 1:
                raise RuntimeError(f"{name} changed between benchmark runs")
        totals, phases, groups = aggregate(runs, detailed)
        identity = source.relative_to(ROOT) if source.is_relative_to(ROOT) else source
        record = {
            "schema": 1,
            "run_id": uuid.uuid4().hex,
            "started_at": started_at,
            "revision": revision.stdout.strip() or None,
            "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
            "workload": {
                "source": str(identity),
                "producer": "ELF-built" if args.elf else "standard",
                "target": target,
                "library": args.library,
                "host": f"{platform.node()} {platform.system()} {platform.machine()}",
            },
            "runs": args.runs,
            "warmups": args.warmup,
            "profile_runs": args.profile_runs,
            "lines": runs[0]["lines"],
            "files": runs[0]["files"],
            "source_bytes": runs[0]["source_bytes"],
            "output_bytes": runs[0]["output_bytes"],
            "samples": runs,
            "profile_samples": detailed,
            "statistics": totals,
            "phases": phases,
            "groups": groups,
        }
    display(record)
    run_path, daily, improved = archive(records, record)
    print(f"\nRun: {run_path}\nDaily record: {daily} ({'new best' if improved else 'best unchanged'})")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as error:
        sys.exit(f"bench: {error}")

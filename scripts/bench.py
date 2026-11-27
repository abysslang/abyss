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
LINK_OBJECT = ROOT / "scripts/link_object.sh"


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
    version = 0
    summary = None
    phases = {}
    for line in stderr.splitlines():
        row = line.split("\t")
        if row[0] == "abyss-profile":
            if version or row[1:] not in (["1"], ["2"]):
                raise ValueError("unsupported or repeated compiler profile header")
            version = int(row[1])
        elif version and row[0] == "summary":
            keys = ("compile_ns", "lines", "files", "source_bytes", "peak_rss_bytes")
            if version == 2:
                keys += ("allocated_bytes",)
            if summary is not None or len(row) != len(keys) + 1:
                raise ValueError("invalid compiler profile summary")
            summary = dict(zip(keys, map(int, row[1:])))
        elif version and row[0] == "phase":
            keys = ("self_ns", "inclusive_ns", "spans")
            if version == 2:
                keys += ("allocated_bytes",)
            if len(row) != len(keys) + 2 or row[1] in phases:
                raise ValueError("invalid compiler profile phase")
            phases[row[1]] = dict(zip(keys, map(int, row[2:])))
    if summary is None or summary["compile_ns"] <= 0:
        raise ValueError("compiler did not report a valid profile; use a current abyssc")
    if detailed and sum(item["self_ns"] for item in phases.values()) != summary["compile_ns"]:
        raise ValueError("phase times do not sum to the profiled compile time")
    if version == 2 and sum(item["allocated_bytes"] for item in phases.values()) != summary["allocated_bytes"]:
        raise ValueError("phase allocations do not sum to the reported total")
    summary["phases"] = phases
    return summary


def timed(command):
    started = time.perf_counter_ns()
    result = checked(command)
    return result, time.perf_counter_ns() - started


def link_object(obj, executable):
    return timed(["bash", str(LINK_OBJECT), str(obj), "-o", str(executable)])[1]


def sample(compiler, flags, source, output, detailed=False, executable=None):
    mode = "tsv" if detailed else "summary"
    command = [str(compiler), "b", *flags, f"--profile={mode}", str(source), str(output)]
    result, elapsed = timed(command)
    measurement = parse_profile(result.stderr, detailed)
    measurement["process_ns"] = elapsed
    measurement["output_bytes"] = output.stat().st_size
    if executable is not None:
        measurement["link_ns"] = link_object(output, executable)
    return measurement


def aggregate(runs, detailed_runs):
    totals = {
        name: statistics_for([run[name] for run in runs])
        for name in ("compile_ns", "process_ns", "peak_rss_bytes")
    }
    totals["lines_per_second"] = statistics_for(
        [run["lines"] * NS_PER_SECOND / run["compile_ns"] for run in runs]
    )
    if "link_ns" in runs[0]:
        totals["link_ns"] = statistics_for([run["link_ns"] for run in runs])
    phases = {}
    groups = {}
    if detailed_runs:
        allocation_available = all(run.get("allocated_bytes", 0) > 0 for run in detailed_runs)
        if allocation_available:
            totals["allocated_bytes"] = statistics_for([run["allocated_bytes"] for run in detailed_runs])
        fields = ("self_ns", "inclusive_ns", "spans")
        if allocation_available:
            fields += ("allocated_bytes",)
        profiled_ns = sum(run["compile_ns"] for run in detailed_runs)
        totals["profiled_ns"] = statistics_for([run["compile_ns"] for run in detailed_runs])
        for name in sorted(set().union(*(run["phases"] for run in detailed_runs))):
            values = [run["phases"].get(name, {}) for run in detailed_runs]
            item = {key: statistics.fmean(value.get(key, 0) for value in values)
                    for key in fields}
            item["share_percent"] = sum(value.get("self_ns", 0) for value in values) * 100 / profiled_ns
            phases[name] = item
            group = name.split("/", 1)[0]
            keys = [group]
            for prefix, label in (("type/check", "checking"), ("type/infer", "inference")):
                if name == prefix or name.startswith(prefix + "_"):
                    keys.append(f"{label} (subset of type)")
            if group in ("type", "comptime"):
                keys.append("type checker and comptime")
            for key in keys:
                total = groups.setdefault(key, {"self_ns": 0.0, "share_percent": 0.0})
                total["self_ns"] += item["self_ns"]
                total["share_percent"] += item["share_percent"]
                if allocation_available:
                    total["allocated_bytes"] = total.get("allocated_bytes", 0) + item["allocated_bytes"]
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


def daily_record(directory, day):
    path = directory / f"{day}.json"
    return json.loads(path.read_text()) if path.exists() else {"schema": 1, "date": day, "best": {}}


def compare_history(directory, today, key, mean_ns):
    day = datetime.date.fromisoformat(today["date"])
    comparisons = []
    for offset in range(4):
        date = (day - datetime.timedelta(days=offset)).isoformat()
        baseline = (daily_record(directory, date) if offset else today)["best"].get(key)
        if baseline is None:
            continue
        previous = baseline["statistics"]["compile_ns"]["mean"]
        if previous > 0:
            comparisons.append({
                "date": date,
                "run_id": baseline["run_id"],
                "mean_ns": previous,
                "time_change_percent": (mean_ns - previous) * 100 / previous,
            })
    return comparisons


def archive(directory, record):
    day = record["started_at"][:10]
    runs = directory / "runs" / day
    runs.mkdir(parents=True, exist_ok=True)
    run_path = runs / f"{record['run_id']}.json"
    daily = directory / f"{day}.json"
    with (directory / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        best = daily_record(directory, day)
        key = json.dumps(record["workload"], sort_keys=True)
        current = best["best"].get(key)
        mean_ns = record["statistics"]["compile_ns"]["mean"]
        record["comparisons"] = compare_history(directory, best, key, mean_ns)
        write_json(run_path, record)
        if current is None or mean_ns < current["statistics"]["compile_ns"]["mean"]:
            best["best"][key] = {**record, "archive": str(run_path.relative_to(directory))}
            write_json(daily, best)
            improved = True
        else:
            improved = False
    return run_path, daily, improved


def by_self_time(rows):
    return sorted(rows.items(), key=lambda row: (-row[1]["self_ns"], row[0]))


class Terminal:
    def __init__(self):
        self.color = sys.stdout.isatty() and not os.environ.get("NO_COLOR") and os.environ.get("TERM") != "dumb"
        self.graphics = self.color and (sys.stdout.encoding or "").lower() == "utf-8"

    def paint(self, text, style):
        return f"\x1b[{style}m{text}\x1b[0m" if self.color and style else text

    def section(self, title):
        print("\n" + self.paint(title, "1;36"))

    def bar(self, percent):
        filled = min(12, max(0, round(percent * 12 / 100)))
        return "█" * filled + "░" * (12 - filled) if self.graphics else "#" * filled + "." * (12 - filled)

    def table(self, headers, rows, left=(0,), styles=None):
        styles = styles or {}
        widths = [max(map(len, column)) for column in zip(headers, *rows)]
        separator = " │ " if self.graphics else " | "

        def row_text(row, index):
            cells = []
            for column, (cell, width) in enumerate(zip(row, widths)):
                padded = cell.ljust(width) if column in left else cell.rjust(width)
                style = "1" if index is None else styles.get((index, column))
                cells.append(self.paint(padded, style))
            return self.paint(separator, "2").join(cells)

        print("  " + row_text(headers, None).rstrip())
        line, crossing = ("─", "─┼─") if self.graphics else ("-", "-+-")
        print("  " + self.paint(crossing.join(line * width for width in widths), "2"))
        for index, row in enumerate(rows):
            print("  " + row_text(row, index).rstrip())


def display(record):
    term = Terminal()
    totals = record["statistics"]
    compile_stats = totals["compile_ns"]
    term.section("ABYSS BENCHMARK")
    arrow = "→" if term.graphics else "->"
    print(f"  {record['workload']['source']} | {record['workload']['producer']} compiler {arrow} "
          f"{record['workload']['target']} | {record['runs']} runs, {record['warmups']} warmups\n")
    labels = ("mean", "median", "min", "max", "p95", "stdev")
    term.table(("Timing (ms)", *(label.title() for label in labels)),
               [(label, *(f"{stats[key]/NS_PER_MS:.3f}" for key in labels)) for label, stats in
                (("Compile", compile_stats), ("Process", totals["process_ns"]))],
               styles={(0, 1): "1;36"})
    print(f"\nThroughput: {totals['lines_per_second']['mean']:,.0f} lines/s mean | "
          f"{record['lines']:,} lines in {record['files']} files | {record['output_bytes']:,} output bytes")
    rss = totals["peak_rss_bytes"]
    print(f"Peak RSS: {rss['max']/BYTES_PER_MIB:.2f} MiB max | {rss['mean']/BYTES_PER_MIB:.2f} MiB mean"
          if rss["max"] else "Peak RSS: unavailable on this compiler host")
    if "link_ns" in totals:
        link = totals["link_ns"]
        print(f"ELF link: {link['mean']/NS_PER_MS:.3f} ms mean | "
              f"{link['median']/NS_PER_MS:.3f} median | {link['p95']/NS_PER_MS:.3f} p95")
    if "elf_producer" in record:
        producer = record["elf_producer"]
        print(f"ELF compiler setup: {producer['build_ns']/NS_PER_MS:.3f} ms build | "
              f"{producer['link_ns']/NS_PER_MS:.3f} ms link")
    if record.get("comparisons"):
        term.section("CHANGE VS. DAILY BEST")
        rows, styles = [], {}
        for index, baseline in enumerate(record["comparisons"]):
            change = baseline["time_change_percent"]
            direction = "less time" if change < 0 else "more time"
            result = f"{abs(change):.2f}% {direction}" if change else "unchanged"
            rows.append((baseline["date"], f"{baseline['mean_ns']/NS_PER_MS:.3f}", result))
            styles[index, 2] = "32" if change < 0 else "31" if change > 0 else "2"
        term.table(("UTC date", "Best ms", "Current run"), rows, left=(0, 2), styles=styles)
    if record["phases"]:
        term.section("DETAILED PROFILE  /  SLOWEST FIRST")
        print(f"  {record['profile_runs']} separate runs | "
              f"{totals['profiled_ns']['mean']/NS_PER_MS:.3f} ms mean, "
              f"{totals['profiled_ns']['mean']/compile_stats['mean']:.2f}x baseline")
        allocated = totals.get("allocated_bytes")
        if allocated:
            hottest, item = max(record["phases"].items(), key=lambda row: row[1]["allocated_bytes"])
            print(f"Heap requested: {allocated['mean']/BYTES_PER_MIB:.2f} MiB mean | "
                  f"{hottest} allocated the most ({item['allocated_bytes']/BYTES_PER_MIB:.2f} MiB)")
        else:
            print("Heap requested: unavailable from this compiler")
        print()
        headers = ("Phase", "Self ms", "Share", "Incl. ms", "Mean spans")
        if allocated:
            headers += ("Heap MiB",)
        rows = []
        for name, item in by_self_time(record["phases"]):
            row = (name, f"{item['self_ns']/NS_PER_MS:.3f}", f"{item['share_percent']:.2f}%",
                   f"{item['inclusive_ns']/NS_PER_MS:.3f}", f"{item['spans']:.1f}")
            if allocated:
                row += (f"{item['allocated_bytes']/BYTES_PER_MIB:.2f}",)
            rows.append(row)
        term.table(headers, rows, styles={(index, 2): "1;33" for index in range(min(3, len(rows)))})
        term.section("GROUP TOTALS  /  EXCLUSIVE TIME")
        rows = []
        for name, item in by_self_time(record["groups"]):
            percent = item["share_percent"]
            rows.append((name, f"{item['self_ns']/NS_PER_MS:.3f}", f"{percent:.2f}%", term.bar(percent)))
        term.table(("Group", "Self ms", "Share", "Of compile"), rows, left=(0, 3),
                   styles={(index, 3): "36" for index in range(len(rows))})


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
        elf_producer = None
        if args.elf:
            print("Building the benchmark compiler through ELF…", flush=True)
            obj = work / "compiler.o"
            native = work / "abyssc"
            _, build_ns = timed([str(compiler), "b", "--emit-obj", "--hosted", str(ROOT / "compiler/main.a"), str(obj)])
            elf_producer = {"build_ns": build_ns, "link_ns": link_object(obj, native)}
            compiler = native
        output = work / ("output.o" if target == "elf" else "output.c")
        executable = work / "output" if target == "elf" and not args.library else None
        print(f"Running {args.warmup} warmups, {args.runs} timing runs, and {args.profile_runs} profile runs…", flush=True)
        for _ in range(args.warmup):
            sample(compiler, flags, source, output, executable=executable)
        runs = [sample(compiler, flags, source, output, executable=executable) for _ in range(args.runs)]
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
        if elf_producer is not None:
            record["elf_producer"] = elf_producer
    run_path, daily, improved = archive(records, record)
    display(record)
    print(f"\nRun: {run_path}\nDaily record: {daily} ({'new best' if improved else 'best unchanged'})")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as error:
        sys.exit(f"bench: {error}")

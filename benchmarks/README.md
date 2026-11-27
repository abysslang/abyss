# Compiler benchmarks

```sh
./abyss bench
./abyss bench --elf --warmup 2 --runs 5 --profile-runs 3
./abyss bench tests/01_literals.a --runs 10
```

The runner needs Python 3.9 or later on a POSIX host. It defaults to building
`compiler/main.a` and measuring C99 emission. `--elf` builds the compiler
through its own Linux x86-64 ELF backend and uses that binary for every measured
run. The runner reports that compiler's build and link times separately. When
the workload emits a hosted ELF executable, the runner also times the system
linker after each measured object build. Neither link time affects the compile
score. ELF library builds have no final link.
`--target c99` with `--elf` measures C99 emission by the ELF-built compiler.

Each run launches a fresh compiler process. Warmups condition filesystem caches
and are discarded. Timings report mean, median, min, max, p95, and standard
deviation. Lines include loaded source modules and preludes and exclude expansions
of splices. Throughput uses that count and the compiler's wall time through
output writing. Process time also includes startup and report transport. Peak
RSS is the process high-water mark where available; the runner reports its
maximum and mean across measured runs. The output size is the emitted file size.

The runner collects detailed profiles in separate processes so instrumentation
does not affect the score. Self time is exclusive: nested scopes such as imports,
unification, and compile-time evaluation are attributed to their own rows.
Inclusive time includes descendants, so those numbers can overlap. Shares use
the total wall time of the detailed samples. Instrumentation has overhead,
especially in short, frequently called scopes; treat the profile as a guide to
where time goes and use the baseline runs to measure improvements. The type
profile separates match preparation, HIR synthesis, global checks, template
scanning, inferred type application, compound type rebuilding, and inferred
union adjustment. Short unification operations stay charged to their caller.

Detailed runs also report cumulative successful heap requests through the
compiler's standard allocator, with the bytes charged to the active phase.
The measure counts the full requested size of each realloc. It excludes
internal allocations by libc and allocations made before compilation starts.
Peak RSS measures resident memory; heap requests measure allocation traffic
and can exceed RSS.

To profile a standalone compilation, use `abyssc b --profile main.a main.c`.
`--profile=tsv` writes a versioned report to stderr with integer nanoseconds
and bytes. `--profile=summary` skips phase timers. In VM mode the report
covers compilation and linking and excludes the program's execution.

Every successful benchmark is saved to `benchmarks/runs/YYYY-MM-DD/<run-id>.json`.
`benchmarks/YYYY-MM-DD.json` keeps the lowest mean compile time for each
combination of source, host, compiler producer, and emission options. Dates are
UTC. Each run compares its mean compile time with the existing best for today
and the previous three UTC days when a matching record exists. A lower
percentage means less wall time for the same workload. The records contain raw
samples, phase totals, the Git revision, and the
compiler's SHA-256. These machine-specific files are ignored by Git. Pass
`--records DIR` to use another location.

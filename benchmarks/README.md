# Compiler benchmarks

```sh
./abyss bench
./abyss bench --elf --warmup 2 --runs 5 --profile-runs 3
./abyss bench tests/01_literals.a --runs 10
```

The runner needs Python 3.9 or later on a POSIX host. It defaults to building
`compiler/main.a` and measuring C99 emission. `--elf` builds the compiler
through its own Linux x86-64 ELF backend and uses that binary for every measured
run. The build and link of that binary are outside the measurements.
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
where time goes and use the baseline runs to measure improvements.

To profile a standalone compilation, use `abyssc b --profile main.a main.c`.
`--profile=tsv` writes a versioned report to stderr with integer nanoseconds
and bytes. `--profile=summary` skips phase timers. In VM mode the report
covers compilation and linking and excludes the program's execution.

Every successful benchmark is saved to `benchmarks/runs/YYYY-MM-DD/<run-id>.json`.
`benchmarks/YYYY-MM-DD.json` keeps the lowest mean compile time for each
combination of source, host, compiler producer, and emission options. Dates are
UTC. The records contain raw samples, phase totals, the Git revision, and the
compiler's SHA-256. These machine-specific files are ignored by Git. Pass
`--records DIR` to use another location.

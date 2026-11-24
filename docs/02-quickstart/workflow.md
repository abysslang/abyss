# Tooling & Workflow: `abyssc`, `sonar`, and `abyssfmt`

The Abyss toolchain is three programs:

1. **`abyssc`** — the compiler. It runs programs immediately on its bytecode VM or emits C99 for native builds.
2. **`sonar`** — the package manager and build driver for pods.
3. **`abyssfmt`** — the canonical source formatter.

---

## 1. Installation

### Linux (x86_64)

```sh
curl -fsSL https://raw.githubusercontent.com/abysslang/abyss/main/scripts/install.sh | bash
```

The installer downloads the latest release archive, extracts `abyssc`, `sonar`, and `abyssfmt` into `~/.abyss/bin`, and adds that directory to your shell's `PATH`. Set `ABYSS_INSTALL_DIR` to install elsewhere and `ABYSS_VERSION` to pin a release. The script currently checks for Linux `x86_64`; on other hosts build the toolchain from source (see [Architecture](../01-overview/architecture.md)).

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/abysslang/abyss/main/scripts/install.ps1 | iex
```

### Verifying the installation

Open a new terminal session and check that the tools respond:

```sh
abyssc --version
sonar help
abyssfmt --help
```

## 2. The Fast Loop: Run on the VM

During development, run source directly:

```sh
abyssc r main.a
```

The compiler parses, type-checks, lowers to bytecode, and executes in one process. Nothing is written to disk, so there is no linker latency. The VM also evaluates `cmpt` blocks and `#` splices while type-checking.

`abyssc r` is the right loop for tests, prototypes, and tools. Switch to a native build when you need peak throughput.

The VM is not a full native target. `std/thread` and `std/sys` thread primitives need a native build, C header bindings (`extern ["header.h"]`, `@c_value`) require a hosted native target, SIMD lane operations lower to native vector instructions, and `u128`/`i128` are modeled as 64-bit. `\xNN` and `\u{...}` escapes are decoded by native builds; the VM decodes only `\n`, `\t`, `\r`, `\0`, `\\`, `\"`, and `\'`. Emit C with `abyssc b` for those features.

## 3. The Native Loop: Emit C99

```sh
# emit a translation unit
abyssc b main.a out.c

# build it with your system C compiler
gcc -std=gnu99 -D_POSIX_C_SOURCE=200809L -O3 out.c -o my_program
./my_program
```

If you omit the output path, `abyssc` writes `out.c`. Use `--library` to emit a library-shaped translation unit instead of an executable entry point.

### Cross-compilation

`--target` and `--arch` select the output platform, and the flags may appear anywhere on the command line:

```sh
# WASI
abyssc b --target wasi --arch wasm32 main.a program.c
clang --target=wasm32-wasi -ffreestanding -nostdlib program.c -o program.wasm

# Windows from Linux
abyssc b --target windows --arch x86_64 main.a program.c
x86_64-w64-mingw32-gcc -O3 program.c -o program.exe

# Freestanding
abyssc b --target freestanding --arch x86_64 main.a program.c
```

Supported targets are `linux`, `windows`, `darwin`, `wasi`, and `freestanding`; supported architectures are `x86_64`, `aarch64`, and `wasm32`.

### Module search paths

- `-I <dir>` (or `-I<dir>`) adds a directory to the module search path.
- `--map <prefix>=<path>` rewrites module names before resolution, which is how pods are mounted: `--map json=/abs/path/to/pods/json`.

Both are described in [Modules & Imports](../03-the-guide/08-modules-and-imports.md).

## 4. Packages and Builds with `sonar`

A package is called a **pod** and is described by a `pod.json` manifest.

### Creating a pod

```sh
sonar init my-app
cd my-app
```

This writes a manifest:

```json
{
  "name": "my-app",
  "version": "0.1.0",
  "entry": "main.a",
  "dependencies": {},
  "c_build": {
    "sources": [],
    "include_dirs": [],
    "c_flags": [],
    "ld_flags": []
  }
}
```

`entry` names the source file built by default. A dependency may use `path` for a local pod or `version` and `git` (plus an optional `subdir`) for a remote one. `c_build` describes native sources and linker flags for pods that wrap C libraries.

### Building and running

```sh
sonar build
sonar run
```

`sonar build` compiles the entry file (and any native sources), applying module maps for dependencies. `sonar run` does the same and then executes the binary.

### Dependencies

```sh
sonar add json        # add a pod from the central index
sonar update          # refresh the local index
sonar vendor          # resolve and vendor dependencies into .vendor/
```

Resolution keeps one entry per pod and prefers the highest version seen while every requirement stays satisfied; an unsatisfiable requirement is a version mismatch, and conflicting majors are rejected instead of silently unified. Dependency cycles are detected during traversal and resolved once.

### Tests

```sh
sonar test            # discover and run the pod's test suites
sonar test <target>   # run a specific test target
```

## 5. Formatting with `abyssfmt`

Formatting is canonical, so there is nothing to debate:

```sh
abyssfmt main.a
abyssfmt src/
abyssfmt --width 80 src/
```

The formatter indents with four spaces, separates statements with newlines, and lays out multiline struct and array literals vertically. The default line width is `100`; `--width N` accepts `1`–`1000`. Comments are single-line and start with `--`; the formatter keeps them attached to the line they document. `abyssfmt --help` prints usage.

Run the formatter before committing. A file that is already formatted is left unchanged, so a second run with no diff is a good check.

---

[Previous: Whirlwind Tour](whirlwind-tour.md) | [Next: Basics →](../03-the-guide/01-basics.md)

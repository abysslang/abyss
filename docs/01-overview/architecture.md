# Architecture

Abyss is a self-hosted compiler with a bytecode VM for direct runs and compile-time evaluation, and a C99 backend for native output. Both paths start from typed HIR.

---

## 1. From Source to Program

```
   main.a + imported modules
              │
              ▼
        lexer → parser
              │
              ▼
   HIR tables (u32 ids, flat arrays)
              │
              ▼
   modules + symbols + type unification
              │
      ┌───────┴────────┐
      ▼                ▼
     Bytecode        Keel AIR
      │                │
      ▼                ▼
      VM            C99 output
```

1. **Lex and parse.** Each resolved file is tokenized and parsed into HIR nodes. Modules are parsed on demand, so a program only pays for what it imports.
2. **Resolve modules and symbols.** `@import` resolves a compile-time path to a file, which gets one module identity per compilation. Top-level declarations become members of a namespace value. Preludes (`core/prelude`, `std/prelude`) are loaded first so their names are available everywhere.
3. **Type-check.** Bidirectional unification infers types, resolves generics, and monomorphizes concrete instantiations. Errors point at the offending source location.
4. **Execute or emit.** The VM path lowers typed HIR directly to bytecode. The native path lowers typed HIR to AIR, which Keel translates into a C99 translation unit.

The runtime entry point is emitted by the compiler, not written by hand: hosted native builds route through `std/sys/process`, standalone WASI builds through `std/sys/start`, and both are ordinary Abyss source in `pods/std`.

## 2. Data-Oriented Compiler Core

Classic compilers represent code as deeply nested, pointer-heavy trees. Every traversal chases pointers across the heap and stalls the CPU on cache misses.

The Abyss compiler stores the program differently:

- Nodes, types, and symbols live in dense arrays.
- References are compact 32-bit integer IDs (`HirId`, `TyId`, `SymbolId`) instead of 64-bit pointers.
- Passes sweep those arrays linearly, keeping caches warm.

The payoff is a compiler that parses and type-checks fast enough to be invisible in the edit/run loop.

## 3. The Bytecode VM

`abyssc r main.a` parses, type-checks, compiles to bytecode, and runs in one process. The same VM executes `cmpt` blocks and splices during type checking. Both paths emit bytecode directly, without building AIR or running optimization passes.

Native calls from the VM go through a runtime binding layer built on the platform's foreign-function interface, so `extern` declarations work under `abyssc r` as well as in emitted binaries.

## 4. Keel Backends

`abyssc b main.a out.c` emits one portable C99 translation unit. Compile it with any supported C compiler:

```sh
abyssc b main.a out.c
gcc -std=gnu99 -D_POSIX_C_SOURCE=200809L -O3 out.c -o program
```

Hosted targets use standard C99 declarations and standard library calls. WASI import declarations use compiler attributes (`__attribute__((import_module(...), import_name(...)))`), which is exactly how `clang` marks wasm imports.

Keel emits labels and jumps for basic blocks and uses C temporaries for SSA values.
On each edge, it saves incoming arguments before assigning block parameters so
that a loop can safely swap two values.

Both native backends use the same AIR optimizations. Keel simplifies control flow
(pruning unreachable blocks, collapsing trivial branches, simplifying invariant
block parameters, threading jumps, and merging straight-line blocks), promotes
local scalar stack slots to SSA values (carrying changing values through branches
and loops as block arguments), folds expressions, and eliminates dead
instructions, write-only stack slots, and unreachable program declarations
in-place. Slots with escaping addresses or incompatible memory accesses stay in
memory. The AIR builder folds fixed-width integer expressions when it can, and
Keel runs these passes in an in-place fixed-point pipeline.

To inspect Abyss IR (AIR), run `abyssc --dump-air main.a`. The compiler
finishes type checking and AIR optimization, then prints function bodies as basic blocks and SSA values, along
with globals and external declarations. Pass a function name after the path to inspect
one function and its dependencies. AIR dumping does not execute the program.

On Linux x86-64, Keel can also write a relocatable ELF object directly. Try it
with this `main.a`:

```abyss
main :: fn() i32 { 42 }
```

```sh
abyssc b --target linux --arch x86_64 --emit-obj main.a main.o
ld -o main main.o
./main
echo $?
```

The program exits with status `42`. Keel encodes machine instructions and
relocations itself. Its entry point calls `main` and exits through a Linux
system call, so this program links without an assembler or libc.

For programs that use libc or the hosted standard library, emit a hosted
object and link it with the system runtime:

```sh
abyssc b --emit-obj --hosted main.a main.o
cc -no-pie main.o -lm -pthread -o main
```

The `cc` command only links; the input is already machine code. The backend
allocates registers directly from AIR, using flat tables and a bounded scan.
Short-lived scalar values use registers, selected values carried between
blocks use callee-saved registers, and wide values and spills use stack slots.
The backend supports integers through 128 bits, floating point, indirect
calls, and System V argument and return conventions.
Some wide integer operations need compiler runtime helpers. Use `--library`
to emit exported functions without a program entry point. The ELF backend
knows the glibc layouts and constants used by the standard library. Use C99
for arbitrary C header layouts and constants, or for other platforms.

## 5. Self-Hosting and Fixed-Point Determinism

The compiler compiles itself:

$$\text{abyssc}_{G_1}(\text{main.a}) \rightarrow G_2 \qquad \text{abyssc}_{G_2}(\text{main.a}) \rightarrow G_3$$

Bootstrap verification checks that generation two and generation three
produce byte-identical C source. On Linux x86-64 it then runs an ELF bootstrap,
starting with the C-built compiler and checking that the ELF-built compilers
emit byte-identical objects. The compiler suite compares shared runtime
fixtures across the VM, C99, and ELF on that platform.

## 6. Zero-Dependency Bootstrap

How do you build a self-hosted compiler on a machine that does not have the compiler yet?

Every release ships standalone C sources in an `abyss-bootstrap-c` bundle. On any machine with a basic C compiler:

```sh
gcc -std=gnu99 -D_POSIX_C_SOURCE=200809L -O3 -fomit-frame-pointer bootstrap-linux-x86_64.c -o abyssc
```

That binary is then used to build the real compiler from source. No package manager, no external libraries, no prebuilt binaries required.

---

[Next: Whirlwind Tour →](../02-quickstart/whirlwind-tour.md)

# Architecture

Abyss is a self-hosted compiler with two execution engines: a bytecode VM for instant runs and compile-time evaluation, and a C99 backend for native output. Both consume the same typed program, so a feature works the same way in either engine.

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
  Bytecode VM      C99 codegen
  (immediate run)  (gcc / clang)
```

1. **Lex and parse.** Each resolved file is tokenized and parsed into HIR nodes. Modules are parsed on demand, so a program only pays for what it imports.
2. **Resolve modules and symbols.** `@import` resolves a compile-time path to a file, which gets one module identity per compilation. Top-level declarations become members of a namespace value. Preludes (`core/prelude`, `std/prelude`) are loaded first so their names are available everywhere.
3. **Type-check.** Bidirectional unification infers types, resolves generics, and monomorphizes concrete instantiations. Errors point at the offending source location.
4. **Execute or emit.** The VM executes the typed program immediately, or the C99 backend emits a translation unit that a system C compiler builds natively.

The runtime entry point is emitted by the compiler, not written by hand: hosted native builds route through `std/sys/process`, standalone WASI builds through `std/sys/start`, and both are ordinary Abyss source in `pods/std`.

## 2. Data-Oriented Compiler Core

Classic compilers represent code as deeply nested, pointer-heavy trees. Every traversal chases pointers across the heap and stalls the CPU on cache misses.

The Abyss compiler stores the program differently:

- Nodes, types, and symbols live in dense arrays.
- References are compact 32-bit integer IDs (`HirId`, `TyId`, `SymbolId`) instead of 64-bit pointers.
- Passes sweep those arrays linearly, keeping caches warm.

The payoff is a compiler that parses and type-checks fast enough to be invisible in the edit/run loop.

## 3. The Bytecode VM

`abyssc r main.a` parses, type-checks, compiles to bytecode, and runs in one process. No object files, no linker, no temporary files. The same VM executes `cmpt` blocks and splices during type-checking, which is why compile-time code is written in ordinary Abyss rather than a separate macro language.

Native calls from the VM go through a runtime binding layer built on the platform's foreign-function interface, so `extern` declarations work under `abyssc r` as well as in emitted binaries.

## 4. The C99 Backend

`abyssc b main.a out.c` emits one portable C99 translation unit. Compile it with any supported C compiler:

```sh
abyssc b main.a out.c
gcc -std=gnu99 -D_POSIX_C_SOURCE=200809L -O3 out.c -o program
```

Hosted targets use standard C99 declarations and standard library calls. WASI import declarations use compiler attributes (`__attribute__((import_module(...), import_name(...)))`), which is exactly how `clang` marks wasm imports.

To inspect the experimental Abyss IR (AIR), run `abyssc --dump-air main.a`. The compiler
finishes type checking, then prints function bodies as basic blocks and SSA values, along
with globals and external declarations. Pass a function name after the path to inspect
one function and its dependencies. AIR dumping does not execute the program.

## 5. Self-Hosting and Fixed-Point Determinism

The compiler compiles itself:

$$\text{abyssc}_{G_1}(\text{main.a}) \rightarrow G_2 \qquad \text{abyssc}_{G_2}(\text{main.a}) \rightarrow G_3$$

Multi-generation bootstrap verification checks that generation two and generation three produce byte-identical C source. There is no randomness, timestamp, or environment leakage in the emitted output, which makes the build reproducible across machines. Release and maintainer workflows gate on this fixed point before shipping.

## 6. Zero-Dependency Bootstrap

How do you build a self-hosted compiler on a machine that does not have the compiler yet?

Every release ships standalone C sources in an `abyss-bootstrap-c` bundle. On any machine with a basic C compiler:

```sh
gcc -std=gnu99 -D_POSIX_C_SOURCE=200809L -O3 -fomit-frame-pointer bootstrap-linux-x86_64.c -o abyssc
```

That binary is then used to build the real compiler from source. No package manager, no external libraries, no prebuilt binaries required.

---

[Next: Whirlwind Tour →](../02-quickstart/whirlwind-tour.md)

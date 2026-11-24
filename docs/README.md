# Into the Abyss

*The Official Guide to the Abyss Programming Language*

Abyss is a statically typed, expression-oriented systems language. Programs run immediately on the compiler's bytecode VM, or compile to C99 and run natively. Types, compile-time evaluation, reflection, and modules are ordinary language features rather than bolt-on tooling.

Every chapter is code-first. Examples use the same syntax the compiler accepts; most are complete programs, and short fragments are marked by context.

---

## Table of Contents

### Part I: Overview

Understand the design goals and how source becomes a running program.

- [Philosophy](01-overview/philosophy.md) — Mechanical sympathy, explicit memory, and no hidden runtime.
- [Architecture](01-overview/architecture.md) — The VM, the C99 backend, the data-oriented compiler, and bootstrap determinism.

### Part II: Quick Start

- [Whirlwind Tour](02-quickstart/whirlwind-tour.md) — A runnable tour of values, control flow, data, modules, and compile-time code.
- [Tooling & Workflow](02-quickstart/workflow.md) — Installing the toolchain, running on the VM, producing native binaries, and using `sonar` and `abyssfmt`.

### Part III: The Guide

- [01 - Basics](03-the-guide/01-basics.md) — Bindings, constants, globals, literals, primitive types, operators, strings, and statement separators.
- [02 - Control Flow](03-the-guide/02-control-flow.md) — `if` expressions, `while`, `for`, iterators, exhaustive `match`, and loop control.
- [03 - Functions & Methods](03-the-guide/03-functions-and-methods.md) — Signatures, tail returns, `ret`, receivers, function values, and generic parameters.
- [04 - Structs & Data Types](03-the-guide/04-structs-and-types.md) — Structs, tuples, enums, tagged unions, casts, and runtime type tests.
- [05 - Pointers, Arrays & Memory](03-the-guide/05-pointers-and-memory.md) — Pointers, automatic dereference, arrays, slices, arenas, and owning containers.
- [06 - Generics & Types](03-the-guide/06-generics-and-types.md) — Type parameters, type functions, deferred inference, monomorphization, and type values.
- [07 - Comptime & Metaprogramming](03-the-guide/07-comptime-and-metaprogramming.md) — `cmpt`, splices, generated declarations, reflection, and compile-time failures.
- [08 - Modules & Imports](03-the-guide/08-modules-and-imports.md) — `@import`, module values, path resolution, caching, re-exports, and import cycles.
- [09 - C Interoperability](03-the-guide/09-c-interop.md) — Foreign declarations, exports, C layouts, header bindings, and C strings.

### Part IV: Standard Library Reference

- [01 - Core Primitives](04-reference/01-core.md) — `Str`, `Maybe`, `Choice`, `Slice`, `Range`, iterators, and reflection records.
- [02 - Collections](04-reference/02-collections.md) — `Vec`, `HashMap`, `HashSet`, `Worklist`, `Interner`, and `sort`.
- [03 - I/O & Formatting](04-reference/03-io-and-fmt.md) — `print`, `write`, `printf`, `fmt`, `String`, `Convert`, and ANSI escapes.
- [04 - Filesystem & Paths](04-reference/04-fs-and-path.md) — `File`, `FileStream`, `Dir`, and `Path`.
- [05 - Allocators & Memory](04-reference/05-allocators-and-mem.md) — `Arena`, raw heap primitives, and allocation strategy.
- [06 - System & Threading](04-reference/06-sys-and-threading.md) — Process control, environment, native threads, `Mutex`, and `sleep`.
- [07 - Language Intrinsics](04-reference/07-language-intrinsics.md) — Every `@builtin`, operator, keyword, and literal form.
- [08 - Pods & Testing](04-reference/08-pods-and-testing.md) — The `test`, `json`, and `simd` pods, manifests, and `sonar`.

---

> *"Built for the deep."*

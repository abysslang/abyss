# Philosophy

Abyss is built on a simple premise: **you should understand what your machine is doing.**

Mainstream languages add layer upon layer of abstraction, and writing a plain program increasingly means reasoning about a runtime you never see. Abyss keeps the ergonomics and removes the fog: clean, modern syntax over a small, transparent implementation.

---

## 1. Mechanical Sympathy

Hardware is not an abstract mathematical canvas. It has caches with line sizes, branch predictors, registers, and memory buses.

Abyss encourages data layout and code patterns that work with the hardware. Contiguous arrays beat pointer-chasing linked lists, and Abyss makes writing data-oriented code feel natural instead of ceremonial.

## 2. No Garbage Collector

A garbage collector is convenient until it pauses your program in the middle of an audio callback or a game frame.

Abyss has no garbage collector. You allocate when you need memory and release it when the phase is over. Latency stays deterministic from the first microsecond to the last. The everyday tool for this is the scoped arena described in [Pointers, Arrays & Memory](../03-the-guide/05-pointers-and-memory.md).

## 3. No Hidden Costs

What you write is what executes:

- No hidden copy constructors copying memory behind your back.
- No implicit allocations from ordinary operations.
- No background runtime threads or schedulers.

If an operation takes memory or time, it is visible in the source. Passing a struct by value copies it; passing a pointer does not. Allocating memory names the allocator.

## 4. Modern Ergonomics, Low-Level Soul

Low level does not have to mean archaic:

- Type inference with `:=` and bidirectional unification.
- First-class types that can be passed to and returned from functions.
- Compile-time evaluation with `cmpt`, executed on an integrated bytecode VM.
- Functions without boilerplate: no return type means no return value.
- Exhaustive `match` over enums and tagged unions instead of unchecked fallthrough.

## 5. Portability Through C99

Instead of dragging a multi-gigabyte backend into every installation, the Abyss compiler emits portable C99 that any mainstream C compiler can build at maximum optimization. The same compiler runs your program directly on its bytecode VM during development.

The language, the compiler, the standard library, and the package manager are all written in Abyss. The compiler bootstraps itself: given a C compiler, a single generated C file is enough to produce a working `abyssc`, which then rebuilds the compiler from its own sources.

---

[Next: Architecture →](architecture.md)

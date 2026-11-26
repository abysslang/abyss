# Abyss Compiler Architecture & Codebase Layout

This reference outlines the internal design, compilation phases, central data structures, and directory conventions of the Abyss project.

---

## 1. Directory Structure

```text
abyss/
├── compiler/           # Self-hosting compiler frontend & backends
│   ├── main.a          # Compiler CLI entry point
│   ├── driver.a        # Compiler driver, pipeline orchestration & config
│   ├── engine.a        # Core compilation session state
│   ├── token.a         # Token definitions, TokenStream structure
│   ├── lexer.a         # Fast lexical analyzer
│   ├── modules.a       # Cached module resolution and source loading
│   ├── hir.a           # High-Level Intermediate Representation (HIR) nodes
│   ├── parser/         # Recursive-descent parser producing HIR
│   ├── typer/          # Type synthesis, unification, comptime & reflection
│   ├── lower.a         # Direct HIR to bytecode lowering
│   ├── air/            # Typed HIR to Keel AIR and ABI metadata
│   └── vm/             # Native bytecode VM (vm.a) & VM codegen (codegen.a)
├── pods/               # Standard, library, and tool pods (managed by Sonar & toolchain)
│   ├── keel/           # AIR, CFG editing, and C99 emission
│   ├── core/           # Fundamental language primitives, slices, and reflection
│   ├── std/            # Standard library (fs, allocator, string, path, collections, etc.)
│   ├── json/           # Official JSON parser pod
│   ├── simd/           # Generic SIMD vector primitives and vectorized math
│   ├── sonar/          # The Sonar package manager (self-hosted pod)
│   └── fmt/            # Opinionated code formatter and syntax engine
├── tests/              # Compiler test suite (01..70, errors/, comptime, unit)
└── scripts/            # Test and multi-generation bootstrap scripts
```

`pods/fmt/syntax/` tokenizes source without losing whitespace or comments. `parser.a` keeps significant line breaks and distinguishes trailing comments from standalone ones. `formatter.a` builds layout groups, and `layout.a` measures and renders them. Keep raw string bytes intact. When the formatter cannot parse a source, return the original bytes. Verify a second formatting pass and run `./abyss test-pods` for native and VM formatter coverage.

---

## 2. The Compiler Pipeline

The compilation process flows through sequential, well-defined phases:

```text
Source Files (.a)
       │
       ▼ [Lexer]
TokenStream
       │
       ▼ [Parser]
HirTable, file declarations and lexical scopes
       │
       ▼ [Typer]
On-demand module loading, type checking, unification, comptime and splices
       │
       ▼
    Typed HIR
       ├───────────────────────────────┐
       ▼ [AIR lowering]                ▼ [Bytecode lowering]
   Keel AIR                         Bytecode Instructions
       │                               │
       ▼ [Keel C99]                    ▼ [Abyss VM]
   out.c                            Execution
```

---

## 3. Core Subsystems

### 1. `Nexus` (`compiler/nexus/nexus.a`)
The single source of truth for the compilation session:
- **String Interner**: Deduplicated string pool returning `u32` symbol IDs.
- **Tokens**: Global token arrays indexed by `u32` token handles.
- **HirTable**: Flat pool of HIR nodes (kind, left, right, type).
- **Types**: Unified type table containing primitive, struct, union, and pointer types.

### 2. Module Loading (`compiler/modules.a`)

- The normal parser registers all declarations in a loaded file and releases its tokens afterward.
- The typer resolves `@import` expressions and looks up members by the receiver's namespace type.
- Normalized paths, file symbols, and namespace types are cached per compilation.
- Declarations are typed on demand, so files can refer to each other. The engine loads the core and std preludes before type checking the entry file.

### 3. `Typer` (`compiler/typer/`)
- Bidirectional Hindley-Milner-inspired type inference and constraint unification (`unify.a`).
- Evaluates compile-time expressions (`cmpt`) and AST reflection (`reflection.a`).

### 4. Backends
- **Keel C99** (`pods/keel/target/c99.a`): Emits C99 directly from AIR, using labels, SSA temporaries, and parallel copies for block arguments.
- **Bytecode VM** (`compiler/lower.a`, `compiler/vm/`): Emits and executes bytecode directly for `cmpt` and `./abyss r`. It does not build AIR or run optimization passes.

Keel (`pods/keel`) owns AIR storage, construction, dumping, and C99 emission. It has no compiler imports. The frontend adapter in `compiler/air/lower.a` builds functions through the Keel entry module. Call `block()` for an empty signature, `block_with_params(types)` for a typed signature, and `begin(block)` to emit its body. Use `jump` and `branch` for edges without arguments, or their `_with_args` variants for slices of values. The caller destroys the finished function.

AIR keeps its SSA graph separate from instruction order. `Block`, `Inst`, `Val`, and `Edge` handles stay stable through unrelated edits. The layout keeps links in flat tables so inserting, moving, and unlinking an instruction does not shift its neighbors. Block parameters are values; terminators have no result. Keel tracks operand uses, including edge arguments, so `replace_uses` visits only the affected uses. `remove` rejects an instruction with a live result. `retarget` checks an edge's argument types and arity. Passes are responsible for preserving dominance and restoring a terminator if they remove one.

Run `./abyss emit --dump-air path.a` to lower a checked source file and its runtime
dependencies into a Keel `Program`. With no path the command dumps a small demo; an
optional function name selects a single root. Keel owns function bodies, declarations,
static data, and symbol IDs. AIR values have fixed widths; the frontend lays out
aggregates as byte storage and passes them by address. Mutable locals use stack slots;
expression joins pass SSA values as block arguments. The frontend supplies ABI
signatures and target header references explicitly. Keel translates them into C
declarations, wrappers, and symbolic layout queries. Native builds emit AIR
without an optimization pass.

---

## 4. Stability & Bootstrap Invariants

1. **Abyss Runtime Sources:** C output is generated from the lowered program and the target runtime modules. Keep runtime implementations in Abyss and use `extern` for C ABI declarations and exports. The WASI executable includes an Abyss entry point and heap and links without a C runtime.

2. **Fixed-Point Bootstrap Guarantee:**
   - Any compiler change must be self-hosting and bit-identical.
   - `abyssc -> gen_1 -> gen_2 -> gen_3`: The C output generated by `gen_2` must match `gen_3` bit-by-bit (SHA-256 hash equality).
   - Verified via `./abyss bootstrap` or `./abyss promote`.

3. **Zero Memory Leaks in Arena Phases:**
   - Compilations allocate via phase-bounded arenas. Always verify that temporary buffers are properly freed or arena-scoped.

---

## 5. Linear Decoupled Pipeline & Database Ergonomics

1. **Zero Lowering-to-Typer Callbacks:**
   - The compiler pipeline is strictly one-way: `Lex -> Parse -> Typer / Monomorphize -> Lower -> Codegen`.
   - Lowering must NEVER call back into the Type Checker (`tyck_mono_function`) or cast `db as &Engine`.
   - All monomorphic instances are queued, specialized, typechecked, and snapshotted entirely within the Typer phase before Lowering begins.

2. **Per-Symbol Template Re-Entrancy Tracking:**
   - When evaluating compile-time expressions (`cmpt`) inside generic function bodies, nested non-conflicting generic functions must be allowed to typecheck and snapshot on demand.
   - Re-entrancy guards track individual template symbols (`is_sym_mono_resolving(sym_id)`) rather than coarse global flags, preventing memory corruption while protecting shared template HIR nodes.

3. **Nexus Ergonomic Helpers:**
   - Use unified database primitives:
     - `db.bind_type(slot, ty)`
     - `db.union(s1, s2)`
     - `db.ensure_slot(id)`
     - `db.type_error(id, msg)`

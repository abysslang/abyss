# Working on Abyss

This guide applies across the repository. Read the [development rules](.agents/rules/development.md) before making changes. Use the [abyss-lang skill](.agents/skills/abyss-lang/SKILL.md) when reading or changing Abyss sources, and the [abyss-standards skill](.agents/skills/abyss-standards/SKILL.md) for releases and public project documentation.

## Repository map

- [`compiler/`](compiler/) contains the self-hosted compiler, including the bytecode VM and C99 backend. See the [architecture overview](docs/01-overview/architecture.md).
- [`pods/core/`](pods/core/) and [`pods/std/`](pods/std/) contain shared primitives and standard library APIs. The [formatter](pods/fmt/) and [Sonar package manager](pods/sonar/) are separate pods.
- [`tests/`](tests/) contains compiler and runtime fixtures. [`scripts/`](scripts/) contains the test and bootstrap runners. Use the root [`abyss`](abyss) wrapper for routine work.

## Code and design

- Write idiomatic Abyss with clear names and types. Leave comments and docstrings out of code unless explicitly requested.
- Keep compiler passes focused. Put general-purpose operations in `core`, reusable library APIs in `std`, and platform bindings behind `std/sys`. Prefer Abyss `extern` declarations for platform calls over handwritten C shims. See [C interop](docs/02-quickstart/c-interop.md).
- Reuse a module binding at call sites when several names come from the same `@import`. Use compile-time features when they simplify the API or remove runtime work.
- When changing language behavior, a standard library API, or an architectural invariant, update the relevant tests, documentation, and `abyss-lang` skill. Migrate affected compiler and library call sites in the same change.

## Verification

Run commands from the repository root. Choose the checks that cover the change:

| Command | Use |
| --- | --- |
| `./abyss fmt <paths...>` | Format changed `.a` files. After editing the formatter, run `./abyss b-fmt` first and check that a second formatting pass leaves the output unchanged. |
| `./abyss test [filter]` | Run compiler tests, optionally narrowed to a relevant fixture or suite. |
| `./abyss test-all` | Run the full compiler suite for changes that affect parsing, typing, lowering, or code generation. |
| `./abyss test-pods` | Check library and formatter changes. |
| `./abyss sonar-test` | Check package manager changes. |
| `./abyss bootstrap [n]` | Verify across compiler generations when changing self-hosting or determinism. |

Cover edge cases and invalid inputs for behavior changes. Pair rejected syntax or type cases in [`tests/errors/`](tests/errors/) with an expected `.err` file. Exercise both VM and native execution when the behavior is shared; use [`tests/native/`](tests/native/) for native-only behavior.

## Git

Preserve unrelated work and stage only the files for the task. Keep generated artifacts out of commits unless explicitly needed. Commit at logical checkpoints with short, single-line English messages.

# Pods & Testing

A **pod** is an Abyss package: a directory with a `pod.json` manifest and one or more `.a` files. The `sonar` tool resolves, vendors, builds, and tests pods. Alongside `core` and `std`, the toolchain ships the `test`, `json`, and `simd` pods.

```sh
sonar init my-app
cd my-app
sonar run
```

---

## 1. The `pod.json` Manifest

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

| Field | Meaning |
| :--- | :--- |
| `name` | Pod name; the key other pods use in `dependencies`. |
| `version` | Semantic version. |
| `entry` | Source file built by default. |
| `dependencies` | Map of dependency name to `version`/`git`/`subdir`, or `path`. |
| `c_build` | Native sources, include dirs, C flags, and linker flags. |

`name`, `version`, and `entry` have defaults (`unnamed`, `0.1.0`, `main.a`), so a minimal manifest can list only `dependencies`. A dependency may also be written as a bare version string, `"json": "^0.1.0"`. `sonar init` writes a manifest with an empty `dependencies` object and an empty `c_build` block.

A dependency may be remote or local:

```json
{
  "dependencies": {
    "json": {
      "version": "^0.1.0",
      "git": "https://github.com/jhosein58/abyss.git",
      "subdir": "pods/json"
    },
    "math": {
      "version": "^1.2.0",
      "path": "../math"
    }
  }
}
```

## 2. Sonar Commands

| Command | Effect |
| :--- | :--- |
| `sonar init [name]` | Write a starter `pod.json`. |
| `sonar add <pod> [ver]` | Add a dependency from the central index and vendor it. |
| `sonar update` | Refresh the local package index. |
| `sonar vendor` | Resolve dependencies and vendor them into `.vendor/`. |
| `sonar build [src] [out]` | Compile the pod (and native sources) into a binary. |
| `sonar run [src]` | Build and run. |
| `sonar test [target]` | Discover and run unit suites under `tests/`. |

Resolution walks the dependency graph, keeps one entry per pod name, and prefers the highest version seen as long as every requirement is satisfied. A requirement that cannot be satisfied is reported as a version mismatch, and two different majors for the same pod are rejected instead of silently unified. A dependency cycle is detected during traversal and resolved once, so mutual dependencies do not loop. Pods that wrap C libraries declare their sources and flags under `c_build`; cached objects go in `.vendor/.cache/` and are linked into the final binary.

## 3. The `test` Pod

`@import("test")` provides assertions, a per-test context, and a suite runner.

### Fatal Assertions

The standalone assertions halt the program on failure, printing a colored diff and then falling with the current source location:

| Function | Signature |
| :--- | :--- |
| `assert` | `fn(cond bool, hint Str)` |
| `assert_true` / `assert_false` | `fn(cond bool, hint Str)` |
| `assert_eq` / `assert_ne` | `fn(T type, actual T, expected T, hint Str)` |
| `assert_gt` / `assert_ge` / `assert_lt` / `assert_le` | `fn(T type, actual T, expected T, hint Str)` |
| `assert_str_eq` / `assert_str_ne` | `fn(actual Str, expected Str, hint Str)` |
| `assert_null` / `assert_not_null` | `fn(T type, ptr &T, hint Str)` |

The type argument comes first, so the generic `T` is known even when the values could be ambiguous.

### The `Test` Context

A `Test` collects failures instead of stopping, so one test case can run every assertion:

| Member | Signature |
| :--- | :--- |
| `assert` | `fn(self &Self, cond bool, hint Str)` |
| `assert_true` / `assert_false` | `fn(self &Self, cond bool, hint Str)` |
| `assert_eq` / `assert_ne` | `fn(self &Self, T type, actual T, expected T, hint Str)` |
| `assert_gt` / `assert_ge` / `assert_lt` / `assert_le` | `fn(self &Self, T type, actual T, expected T, hint Str)` |
| `assert_str_eq` / `assert_str_ne` | `fn(self &Self, actual Str, expected Str, hint Str)` |
| `assert_null` / `assert_not_null` | `fn(self &Self, T type, ptr &T, hint Str)` |
| `fail` | `fn(self &Self, msg Str)` |

Each case receives a `&Test` from the suite. A `TestFunc` is `fn(t &Test)`.

### The `Suite` Runner

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `new` | `fn(arena &Arena, name Str) Self` | Create a suite. |
| `add` | `fn(self &Self, name Str, func TestFunc)` | Register a case. |
| `run` | `fn(self &Self) bool` | Run all cases; `true` if all passed. |
| `run_and_exit` | `fn(self &Self)` | Run and fall if any case failed. |

```abyss
Arena :: @import("std/allocator").Arena
Suite :: @import("test").Suite
Test :: @import("test").Test

test_math :: fn(t &Test) {
    t.assert_eq(i32, 2 + 2, 4, "addition")
    t.assert_true(10 > 5, "ordering")
}

test_strings :: fn(t &Test) {
    t.assert_str_eq("abyss", "abyss", "equality")
}

main :: fn() {
    arena := Arena.new(4096)
    suite := Suite.new(&arena, "Example")
    suite.add("math", test_math)
    suite.add("strings", test_strings)
    suite.run_and_exit()
    arena.destroy()
}
```

`Color` in the `test` pod exposes the ANSI helpers used by the reporters.

## 4. The `json` Pod

`@import("json")` is a zero-dependency JSON parser.

```abyss
Arena :: @import("std/allocator").Arena
parse_json :: @import("json").parse_json
JsonKind :: @import("json").JsonKind

main :: fn() {
    arena := Arena.new(4096)
    document := parse_json(&arena, "{\"name\": \"abyss\", \"version\": 1}")
    if document.is_some() {
        value := document.unwrap()
        if value.kind == JsonKind.obj_val {
            print(value.get_str("name").unwrap_or("?"))
        }
    }
    arena.destroy()
}
```

`JsonKind` is `enum u8 { null_val, bool_val, num_val, str_val, arr_val, obj_val }`.

`JsonVal` holds `kind`, `str_val`, `bool_val`, `int_val`, `keys`, and `vals`. Build values with `null`, `from_bool`, `from_num`, `from_str`, `from_arr`, and `from_obj`, and read them with:

| Member | Result |
| :--- | :--- |
| `get(key)` | `Maybe(JsonVal)` |
| `get_str(key)` | `Maybe(Str)` |
| `get_obj(key)` | `Maybe(JsonVal)` |
| `get_arr(key)` | `Maybe(Vec(JsonVal))` |

`JsonParser` exposes `new(arena, src)`, `peek`, `bump`, `skip_ws`, and the `parse_*` steps for streaming; `parse_json(arena, src)` parses a whole document.

## 5. The `simd` Pod

`@import("simd")` provides fixed-width vectors and lane operations. `Simd(T, N)` is a generic vector with `N` compile-time lanes. The lane operations lower to native vector instructions, so emit C with `abyssc b` and link with `-lm`; the bytecode VM does not execute them:

```abyss
simd :: @import("simd")

main :: fn() {
    a := simd.f32x4.splat(1.5)
    b := simd.f32x4.splat(2.0)
    c := a.fma(b, simd.f32x4.splat(0.5))
    print(c.sum())

    mask := a.cmp_lt(b)
    print(simd.f32x4.select(mask, a, b).get(0))
}
```

| Group | Members |
| :--- | :--- |
| Construction | `splat`, `zero`, `from_array`, `load`, `store` |
| Lanes | `get`, `set`, `extract`, `insert`, `reverse` |
| Arithmetic | `add`, `sub`, `mul`, `div`, `neg`, `abs`, `min`, `max`, `clamp`, `fma` |
| Bitwise (integer) | `bit_and`/`and_`, `bit_or`/`or_`, `bit_xor`/`xor_`, `bit_not`/`not_` |
| Reductions | `sum`, `product`, `reduce_min`, `reduce_max`, `dot` |
| Comparison | `cmp_eq`/`cmpeq`, `cmp_ne`/`cmpne`, `cmp_lt`/`cmplt`, `cmp_le`/`cmple`, `cmp_gt`/`cmpgt`, `cmp_ge`/`cmpge` |
| Selection | `select(mask, on_true, on_false)` |
| Transcendentals | `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `exp`, `exp2`, `ln`, `log2`, `log10`, `sqrt`, plus `*_fast` approximations |

`SimdMask(N)` supports `all()`, `any()`, `none()`, `count_ones()`, `get(idx)`, and `set(idx, val)`. Type aliases include `f32x4`, `f32x8`, `f64x2`, `f64x4`, `i32x4`, `i32x8`, `u32x4`, `u32x8`, `i64x2`, `i64x4`, `i16x8`, `i8x16`, and their unsigned variants, plus the mask aliases `m2`, `m4`, `m8`, and `m16`.

`abyss_simd_cpu_features()` reports the baseline and portable feature bits for the target.

---

[Previous: Language Intrinsics](07-language-intrinsics.md) | [Back to Table of Contents →](../README.md)

# Core Primitives

The `core` pod is the foundation of the standard library: allocation-free string views, optional and result containers, slices, ranges, iterators, and the records used by reflection. Every symbol here is injected by `core/prelude` and `std/prelude`, so **no `@import` is needed**.

```abyss
main :: fn() {
    text: Str = "the deep"
    print(text.len)

    value := Maybe(i32).some(42)
    if value.is_some() {
        print(value.unwrap())
    }
}
```

---

## 1. The Zero-Import Prelude

`core/prelude` and `std/prelude` are loaded into every file. These names are always in scope:

| Symbol | Purpose |
| :--- | :--- |
| `Str`, `CharIter` | UTF-8 string view and its code-point iterator. |
| `Maybe(T)` | Optional value. |
| `Choice(T, E)` | Success-or-failure value. |
| `Slice(T)` | Non-owning contiguous view. |
| `Range` | Half-open integer range iterator. |
| `Iterator(T)`, `RefIterator(T)` | Structural iteration protocols. |
| `SourceLocation` | Record for `@source_location()`. |
| `TypeInfo`, `FieldInfo`, `TypeKind` | Reflection records. |
| `Vec`, `HashMap`, `HashSet`, `Worklist` | Core collections. |
| `print`, `printf` | Formatted output. |

Importing a module does not re-export these names; they are already visible, and a module you import is not required to declare them.

## 2. `Str`

`Str` is a pointer and a length. It is not null-terminated, it may contain NUL bytes, and its length is `O(1)`:

```abyss
Str :: struct {
    ptr &u8
    len u64
}
```

```abyss
main :: fn() {
    message := "hello, Abyss"
    print(message.len)
    print(message.starts_with("hello"))
    print(message.ends_with("Abyss"))
    print(message.sub(7, 5))
    print(message.eq("hello, Abyss"))
}
```

### Full `Str` API

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `size` | `fn() u64` | Size of `Str` in bytes (`16`). |
| `new` | `fn(ptr &u8, len u64) Str` | Build from a pointer and length. |
| `empty` | `fn() Str` | The null/zero-length view. |
| `of` | `fn(s &u8 or Str) Self` | From a C string (`&u8`) or identity on a `Str`. |
| `sub` | `fn(self &Self, start u64, len u64) Str` | A view `len` bytes from `start`. |
| `eq` | `fn(self &Self, b Str) bool` | Byte-wise equality. |
| `starts_with` | `fn(self &Self, prefix Str) bool` | Prefix test. |
| `ends_with` | `fn(self &Self, suffix Str) bool` | Suffix test. |
| `trim_quotes` | `fn(self &Self) Str` | Strips a surrounding `"` or `` ` `` pair. |
| `iter`, `chars` | `fn(self &Self) CharIter` | Code-point iteration. |
| `char_count` | `fn(self &Self) u64` | Number of code points. |
| `char_at` | `fn(self &Self, n u64) Maybe(u32)` | The `n`-th code point, or `none`. |

There is no `slice`, `contains`, or `find` method. Use `sub`, `starts_with`, `ends_with`, `eq`, and `CharIter` for everything else.

### `CharIter`

`CharIter` walks UTF-8 code points:

```abyss
main :: fn() {
    it := "abя".chars()
    while it.has_next() {
        point := it.next()
        if point.is_some() {
            print(point.unwrap())
        }
    }
}
```

| Member | Signature |
| :--- | :--- |
| `new` | `fn(ptr &u8, len u64) Self` |
| `next` | `fn(self &Self) Maybe(u32)` |
| `has_next` | `fn(self &Self) bool` |

## 3. `Maybe(T)`

`Maybe(T)` is the type-safe replacement for null pointers and sentinel codes:

```abyss
divide :: fn(a i32, b i32) Maybe(i32) {
    if b == 0 {
        ret Maybe(i32).none()
    }
    Maybe(i32).some(a / b)
}

main :: fn() {
    print(divide(10, 2).unwrap_or(0))
    print(divide(10, 0).unwrap_or(0))
}
```

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `some` | `fn(value T) Self` | Wrap a value. |
| `none` | `fn() Self` | No value. |
| `is_some` | `fn(self &Self) bool` | Is a value present? |
| `is_none` | `fn(self &Self) bool` | Is the container empty? |
| `unwrap` | `fn(self &Self) T` | The inner value. Unchecked. |
| `unwrap_or` | `fn(self &Self, fallback T) T` | The value, or `fallback`. |

The record fields are `present bool` and `value T`. `unwrap` does not check `present`, so guard with `is_some` first or use `unwrap_or`.

## 4. `Choice(T, E)`

`Choice(T, E)` carries either a success of type `T` or a failure of type `E`:

```abyss
parse_port :: fn(port_str Str) Choice(u16, Str) {
    if port_str.len == 0 {
        ret Choice(u16, Str).err("empty")
    }
    Choice(u16, Str).ok(8080)
}

main :: fn() {
    result := parse_port("")
    if result.is_error() {
        print(result.unwrap_or(0))
    }
}
```

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `ok` | `fn(v T) Self` | Success value. |
| `err` | `fn(e E) Self` | Failure value. |
| `is_success` | `fn(self &Self) bool` | Success? |
| `is_error` | `fn(self &Self) bool` | Failure? |
| `unwrap_or` | `fn(self &Self, fallback T) T` | Success value, or `fallback`. |

The fields are `is_ok bool` and `val T | E`. There is no checking `unwrap`/`unwrap_err`: read the payload through a `match` or `@is` when you need the value itself.

## 5. `Slice(T)`

`Slice(T)` is a pointer-plus-length view over memory someone else owns. It is the same type as `[]T`:

```abyss
main :: fn() {
    data: [5]i32 = .[10, 20, 30, 40, 50]
    view := Slice(i32).new(&data[1], 3)
    print(view.get(0))
    print(view.contains(30))
    print(view.position(40).unwrap_or(0))
    print(view.sub(1, 2).get(0))
}
```

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `new` | `fn(ptr &T, len u64) Self` | Build a view. |
| `empty` | `fn() Self` | Null, zero-length view. |
| `get` | `fn(self &Self, idx u64) T` | Read one element. |
| `sub` | `fn(self &Self, start u64, len u64) Self` | Narrow the window. |
| `chunks` | `fn(self &Self, width u64) Chunks(T)` | Fixed-width chunk iterator. |
| `equals` | `fn(self &Self, other Self) bool` | Element-wise equality. |
| `position` | `fn(self &Self, value T) Maybe(u64)` | Index of the first match. |
| `contains` | `fn(self &Self, value T) bool` | Membership test. |
| `dedup` | `fn(self &Self) Self` | Compacts equal neighbors in place and returns the shortened view. |
| `iter` | `fn(self &Self) Iterator(T)` | Value iterator. |
| `iter_ref` | `fn(self &Self) RefIterator(T)` | Pointer iterator. |

`Chunks(T)` exposes `ptr`, `len`, `width`, `index`, and `next()` returning `Maybe(Slice(T))`.

## 6. `Range`

`Range` is a half-open iterator over `i32`, useful with `for`:

```abyss
main :: fn() {
    for i in Range.new(0, 5) {
        print(i)
    }
}
```

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `new` | `fn(start i32, end i32) Self` | Half-open `[start, end)`. |
| `next` | `fn(self &Self) Maybe(i32)` | Next integer. |

Fields are `current i32` and `end i32`.

## 7. Iterators

`Iterator(T)` yields values and `RefIterator(T)` yields pointers. Any type with `next(self &Self) Maybe(T)` can be iterated with `for`:

```abyss
main :: fn() {
    values: [3]i32 = .[1, 2, 3]
    it := values.iter()
    print(it.peek().unwrap_or(0))
    it.skip(1)
    print(it.remaining())
    print(it.next().unwrap_or(0))
}
```

Both types share the same members:

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `new` | `fn(ptr &T, len u64) Self` | Over a raw buffer. |
| `next` | `fn(self &Self) Maybe(T)` (`Maybe(&T)` for `RefIterator`) | Advance. |
| `has_next` | `fn(self &Self) bool` | Anything left? |
| `is_done` | `fn(self &Self) bool` | Exhausted? |
| `peek` | `fn(self &Self) Maybe(T)` (`Maybe(&T)`) | Look without advancing. |
| `skip` | `fn(self &Self, n u64)` | Advance up to `n`. |
| `reset` | `fn(self &Self)` | Restart. |
| `remaining` | `fn(self &Self) u64` | Count left. |

## 8. Reflection Records

`@type_info(T)` returns `&TypeInfo()`; `FieldInfo` describes one field or variant:

```abyss
TypeKind :: enum u8 {
    unknown, infer, untyped_int, untyped_float, int, uint, float, bool,
    ptr, type_, unit, func, never, struct_, array, error, nominal,
    enum_, union_, tuple, string, c_type
}

TypeInfo :: fn() type {
    struct {
        id           u32
        name         Str
        kind         TypeKind
        bits         u32
        length       u64
        fields       &&FieldInfo()
        field_count  u64
        element      &TypeInfo()
        members      &&TypeInfo()
        member_count u64
        params       &&TypeInfo()
        param_count  u64
        result       &TypeInfo()
        is_extern    bool
    }
}

FieldInfo :: fn() type {
    struct {
        name      Str
        type_info &TypeInfo()
        value     u64
    }
}
```

Use `id` to compare types, `name` for display, `bits`/`length` for widths, and `value` for enum variant values. See [Comptime & Metaprogramming](../03-the-guide/07-comptime-and-metaprogramming.md) for how to drive code generation from these records.

## 9. `SourceLocation` and Target Info

```abyss
SourceLocation :: struct {
    file   Str
    line   u32
    column u32
}
```

`@source_location()` produces one at compile time. `core/target` reports the build target:

| Symbol | Value |
| :--- | :--- |
| `Os` | `enum u8 { linux, darwin, windows, wasi, freestanding }` |
| `Arch` | `enum u8 { x86_64, aarch64, wasm32 }` |
| `Target` | `struct { os Os, arch Arch, ptr_bits u8 }` |
| `target` | Compile-time `Target` constant. |

```abyss
target :: @import("core/target")

main :: fn() {
    if target.target.os == target.Os.linux {
        print("linux")
    }
    print(target.target.ptr_bits)
}
```

---

[Previous: C Interoperability](../03-the-guide/09-c-interop.md) | [Next: Collections →](02-collections.md)

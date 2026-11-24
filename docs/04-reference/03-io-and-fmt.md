# I/O & Formatting

Output has two layers: `print`, `write`, and `printf` for console text, and `std/fmt` for building strings. Both specialize the format template at compile time, so a format string never costs a runtime parse.

```abyss
write :: @import("std/io").write

main :: fn() {
    print("Welcome to Abyss")
    write("[")
    write("OK")
    print("]")
    printf("position: ({}, {})\n", .{10, 20})
}
```

---

## 1. Console Output

| Function | Source | Newline | Notes |
| :--- | :--- | :--- | :--- |
| `print(value)` | `std/io`, prelude | Yes | Formats `value` and appends `\n`. |
| `write(value)` | `std/io` | No | Formats `value` with no newline. |
| `printf(pattern, args)` | `std/io`, prelude | No | Compile-time `pattern` and a tuple of arguments. |

`print` behaves like `println` elsewhere. Do not add `\n` to its argument:

```abyss
print("done")          -- prints "done" plus one newline
```

`write` is the inline form, and `printf` writes a formatted template:

```abyss
write :: @import("std/io").write

main :: fn() {
    write("loading")
    write(".")
    write(".")
    print(" done")

    x := 100
    y := 200
    printf("x={}, y={}\n", .{x, y})
}
```

`print` and `write` accept any value: integers, floats, `bool`, `Str`, enums, structs, unions, and arrays. A `Str` prints as its bytes at the top level; nested strings inside a struct are quoted.

### Low-Level Writers

`std/io` also exposes the primitives the high-level functions are built on:

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `write_str` | `fn(value Str)` | Write raw bytes to standard output. |
| `write_byte` | `fn(value u8)` | Write one byte. |
| `print_codepoint` | `fn(cp u32)` | UTF-8 encode one code point and write it. |

## 2. Format Templates

A format template is a compile-time `Str` with `{}` placeholders and `{{`/`}}` escapes. It is checked against the argument tuple before code is generated:

- Each `{}` consumes the next tuple element.
- Too few or too many arguments, an unclosed `{`, an unmatched `}`, or a non-tuple argument list is a compile error.
- The pattern must be a compile-time `Str`; a runtime pattern is rejected.

```abyss
fmt :: @import("std/fmt").fmt
Arena :: @import("std/allocator").Arena

main :: fn() {
    arena := Arena.new(64)
    print(fmt(&arena, "hello {}", .{"Abyss"}).as_str())
    arena.destroy()
}
```

## 3. Building Strings with `std/fmt`

`fmt` allocates a fresh `String`; `fmt_into` appends to an existing buffer without an intermediate allocation:

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `fmt` | `fn(arena &Arena, cmpt pattern Str, args T) String` | New buffer in `arena`. |
| `fmt_into` | `fn(out &String, cmpt pattern Str, args T)` | Append into `out`. |

```abyss
fmt :: @import("std/fmt").fmt
fmt_into :: @import("std/fmt").fmt_into
Arena :: @import("std/allocator").Arena
write :: @import("std/io").write

main :: fn() {
    arena := Arena.new(4096)
    report := fmt(&arena, "header: {}\n", .{"start"})
    fmt_into(&report, "body: {}\n", .{"data"})
    fmt_into(&report, "footer: {}\n", .{"end"})
    write(report.as_str())
    arena.destroy()
}
```

### `Fmt`, the Chaining Builder

`Fmt` assembles a fragment from runtime pieces with a fluent API, which is handy when the shape depends on the values:

```abyss
fmt :: @import("std/fmt")
Arena :: @import("std/allocator").Arena

main :: fn() {
    arena := Arena.new(256)
    text := fmt.Fmt.new(&arena).str("point(").uint32(3).comma().uint32(4).str(")").as_str()
    print(text)
    arena.destroy()
}
```

The builder exposes `str`, `cstr`, `char`, `uint32`, `uint64`, `int32`, `boolean`, `space`, `newline`, `semi`, `comma`, `paren`, `wrap`, `sym`, `binary`, `indent`, `as_str`, and `print`.

## 4. `String`

`std/string.String` is a growable UTF-8 buffer backed by an arena. Prefer `fmt` for templates and `String` for building byte-by-byte:

```abyss
String :: @import("std/string").String
Arena :: @import("std/allocator").Arena

main :: fn() {
    arena := Arena.new(256)
    s := String.new(&arena)
    s.push_str("Hello")
    s.push_char(' ')
    s.push_str("World")
    s.push_char('!')
    print(s.as_str())
    arena.destroy()
}
```

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `new` | `fn(a &Arena) String` | Empty buffer. |
| `of` | `fn(T type, arena &Arena, value T) Self` | Format a value into a new buffer. |
| `push_str` | `fn(self &Self, s Str)` | Append bytes. |
| `push_char` | `fn(self &Self, c u8)` | Append one byte. |
| `push_codepoint` | `fn(self &Self, cp u32)` | Append a code point as UTF-8. |
| `push_u32` | `fn(self &Self, val u32)` | Append a decimal integer. |
| `append` | `fn(self &Self, value Str) &Self` | Append and return `self` for chaining. |
| `append_u32` | `fn(self &Self, value u32) &Self` | Append an integer and return `self`. |
| `reserve` | `fn(self &Self, needed u64)` | Ensure capacity. |
| `as_str` | `fn(self &Self) Str` | Borrow the bytes. |
| `len` | `fn(self &Self) u64` | Current length. |
| `mark` / `reset` | `fn(self &Self) u64` / `fn(self &Self, mark u64)` | Save and restore length. |
| `ptr_at` | `fn(self &Self, offset u64) &u8` | Pointer to a byte. |

Module-level helpers: `parse_u32(s Str) Maybe(u32)` parses decimal, `0x`, `0b`, and `0o` forms (with optional `_` separators), and `to_cstr(arena &Arena, s Str) &u8` returns a null-terminated copy.

## 5. `Convert`

`std/convert.Convert` holds the scalar-to-text routines that `fmt`, `String.of`, and `print` use. Reach for them when you are emitting source or want explicit control:

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `unsigned64` | `fn(out &String, value u64)` | Decimal unsigned. |
| `signed64` | `fn(out &String, value i64)` | Decimal signed. |
| `unsigned128` / `signed128` | `fn(out &String, value u128)` / `i128` | Decimal wide integers. |
| `float64` | `fn(out &String, value f64)` | Float text. |
| `boolean` | `fn(out &String, value bool)` | `true`/`false`. |
| `quoted` | `fn(out &String, value Str)` | Wrap in quotes and escape. |
| `literal` | `fn(out &String, text Str)` | Emit a C string literal. |

`value_code(info, expr)` is the reflection entry point that returns generated code to format a value of type `info` at `expr`; `conversion_error(message)` reports a formatting failure with the current source location.

## 6. ANSI Colors

`std/fmt.escape()` returns an `Escape` record of ANSI sequences. Each field is a `&u8` that prints as its escape text:

```abyss
fmt :: @import("std/fmt")
write :: @import("std/io").write

main :: fn() {
    esc := fmt.escape()
    write(esc.fg_green)
    write("ok")
    write(esc.reset)
    print("")

    printf("{}{}warning{}{}\n", .{esc.fg_yellow, esc.bold, esc.reset, esc.dim})
}
```

Fields cover `reset`, `bold`, `dim`, `italic`, `underline`, `blink`, `reverse`, `hidden`, `strike`, foreground colors `fg_*`, and background colors `bg_*`, including bright variants.

## 7. `std/ascii`

`std/ascii` provides single-byte character predicates. Each is available both as a method on `Ascii` and as a free function:

```abyss
Ascii :: @import("std/ascii").Ascii

main :: fn() {
    print(Ascii.is_digit('7'))
    print(Ascii.to_upper('a'))
    print(Ascii.is_whitespace(' '))
}
```

| Function | Result |
| :--- | :--- |
| `is_digit`, `is_hex_digit`, `is_bin_digit`, `is_oct_digit` | Byte class tests. |
| `hex_digit_value` | Value of a hex digit as `u32`. |
| `is_alpha`, `is_alphanumeric` | Letter tests (`_` counts as a letter). |
| `is_whitespace`, `is_newline` | Space/tab and CR/LF tests. |
| `to_lower`, `to_upper` | ASCII case fold. |

---

[Previous: Collections](02-collections.md) | [Next: Filesystem & Paths →](04-fs-and-path.md)

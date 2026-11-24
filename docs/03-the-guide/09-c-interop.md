# C Interoperability

Abyss speaks the platform C ABI in both directions. Declaring a foreign function needs no wrapper, no header generation, and no `unsafe` block, and an Abyss function can be exported with an unmangled C symbol that external code can call.

```abyss
puts :: extern fn(message &u8) i32
c_abs :: extern "abs" fn(n i32) i32

main :: fn() {
    puts(c"Hello from the C runtime!")
    print(c_abs(-42))
}
```

---

## 1. Declaring Foreign Functions

An `extern fn` has a signature and no body. By default the Abyss binding name becomes the C linker symbol:

```abyss
malloc :: extern fn(size u64) &u8
free :: extern fn(ptr &u8)
```

When the Abyss name should differ from the C symbol, put the C name in a string after `extern`:

```abyss
c_cos :: extern "cos" fn(x f64) f64
c_sqrt :: extern "sqrt" fn(x f64) f64
CAbs :: extern "abs" fn(n i32) i32
```

Parameters may be named, grouped, or left anonymous. Mixing styles on one line is allowed and matches how C declarations often read:

```abyss
mix :: extern "C_ABI_Mixed_widths" fn(
    i8, a, b u16
    named i32
    value f32
    is_valid bool
) f64
```

### Function Type Aliases

A top-level declaration with a signature and no `extern`, no body, is a function type alias. It is the idiomatic way to name a callback signature:

```abyss
Unary :: fn(i32) i32
Compare :: fn(i32, i32) i32
Select :: fn()

c_invoke :: extern fn(value i32, apply Unary) i32
c_call_select :: extern fn(select Select)
```

Aliases are also usable as ordinary Abyss function values, so one signature serves both sides of the boundary.

## 2. Strings Across the Boundary

`"..."` is an Abyss `Str` (a pointer and a length). C APIs expect a null-terminated `&u8`, so use the `c"..."` literal or allocate a terminator:

```abyss
Arena :: @import("std/allocator").Arena
to_cstr :: @import("std/string").to_cstr

puts :: extern fn(message &u8) i32

main :: fn() {
    puts(c"a literal C string")

    arena := Arena.new(256)
    message: Str = "hello from Abyss"
    puts(to_cstr(&arena, message))
    arena.destroy()
}
```

`Str.of(cstr)` converts the other way, computing the length. Keep `c"..."` and `&u8` at the boundary and use `Str` everywhere inside the program.

## 3. Exporting Abyss Functions to C

An `extern fn` **with a body** is an exported function. The C backend emits a plain C function definition with the binding name as its linker symbol:

```abyss
abyss_add :: extern fn(a, b i32) i32 {
    a + b
}

compute :: extern "AbyssCustomExport_42" fn(a f64, b i32) f64 {
    a * 2.0 + (b as f64)
}
```

External C code links against `abyss_add` and `AbyssCustomExport_42` just like any other symbol. Inside Abyss the same function is callable directly:

```abyss
abyss_add :: extern fn(a, b i32) i32 {
    a + b
}

main :: fn() {
    print(abyss_add(2, 3))
}
```

Only `extern` definitions are public in the emitted object. A regular `fn` is private to the translation unit.

## 4. C-Compatible Records (`extern struct`)

An `extern struct` shares the C layout, in declaration order, with the field names the target C compiler expects:

```abyss
Point :: extern struct {
    fraction f32
    distance f64
}

Packet :: extern struct {
    tag    u8
    pos    Point
    delta  i16
    active bool
    serial u64
}
```

Such a value can cross the boundary by value or by pointer, including nested records:

```abyss
c_packet :: extern fn(packet Packet) Packet

bump :: fn(packet Packet) Packet {
    packet.serial = packet.serial + 1
    packet
}
```

For anything shared with C — records, callbacks in struct fields, and pointers — prefer `extern struct` so the emitted C matches the declaration exactly.

## 5. Binding to Native Headers

On hosted native targets you can bind directly to a C header with `extern ["header.h"]`. The compiler includes the header and uses its declarations, so you do not restate sizes or layouts by hand.

### Functions

```abyss
fputc  :: extern ["stdio.h"] fn(byte i32, stream &File) i32
fclose :: extern ["stdio.h"] fn(stream &File) i32
rewind :: extern ["stdio.h"] fn(stream &File)
```

Omit the symbol string when the C name matches the binding, or spell it out when it does not.

### Types

A named native type uses the header's identifier. An empty body keeps the type opaque, which is how you hold a `FILE *` without exposing its internals:

```abyss
Void :: @typeof({})
File :: extern ["stdio.h"] "FILE" struct {}
tmpfile :: extern ["stdio.h"] fn() &File
```

Declare fields when you need them; they keep their C names and the header supplies the real layout:

```abyss
Division :: extern ["stdlib.h"] "div_t" struct {
    quot i32
    rem  i32
}

divide :: extern ["stdlib.h"] "div" fn(i32, i32) Division
```

`@type_info(Division).kind` is `TypeKind.c_type`. Use `&Void` for a C `void *` — for example when comparing the result of `tmpfile()` against `0 as &Void`.

### Header Values

`@c_value("header.h", "NAME", T)` reads a macro, enum constant, or declared value as a fixed-width integer:

```abyss
main :: fn() {
    print(@c_value("limits.h", "CHAR_BIT", i32))
    print(@c_value("stdio.h", "EOF", i32))
}
```

Header paths are relative, the name is a C identifier, and `T` must be a fixed-width integer type.

## 6. Constraints and Diagnostics

The boundary is checked hard so mistakes surface at compile time:

- **No generics or `cmpt` parameters.** `external functions cannot be generic` and `external functions cannot have compile-time parameters`.
- **No variadics.** `...` is rejected: `variadic parameters are not supported; use tuples for type-safe formatting` (formatting uses compile-time tuples instead).
- **Fixed-width types only.** `int`, `char`, `long`, `double`, and friends are rejected with a suggestion: `unknown type 'int'; did you mean 'i32'?`.
- **Symbol rules.** `extern ""` and symbols with spaces are rejected, a duplicate export symbol is an error, and `extern "main"` is reserved for the program entry point.
- **Header rules.** Header paths must be relative to a search root, header imports cannot have a body, and header declarations must be top-level with a native name.
- **Hosted native only.** `@c_value` and `@sizeof` of a header type cannot be evaluated by `cmpt`, because their values come from the target C toolchain: `C headers require a hosted native target`.

## 7. Running and Building

### Native

Emit a translation unit and link it with your C compiler, adding the libraries you use:

```sh
abyssc b main.a out.c
gcc -std=gnu99 -D_POSIX_C_SOURCE=200809L -O3 out.c -lm -o my_program
./my_program
```

### Bytes and Pointers

When a value must be reinterpreted as ABI storage of the same size, copy the bits with `@memcpy` instead of casting, which would reinterpret the value:

```abyss
Void :: @typeof({})
Work :: fn(&u8)

run :: fn(job &Void) {
    work: Work
    @memcpy(&work as &u8, job as &u8, @sizeof(Work))
    work(job as &u8)
}
```

`@memcpy` copies `@sizeof(Work)` bytes between equal-size storage, so a `fn(&u8)` recovered from an opaque `&Void` keeps its exact bit pattern. Use it wherever a numeric cast would change the value.

### VM

The bytecode VM dispatches foreign calls through `libffi` at runtime, so `abyssc r` can call C functions in a linked shared library for supported scalar, pointer, and record types. Compiler builds never include the `libffi` headers; the bridge is requested only by the VM.

## Idiomatic Summary

| FFI task | Idiomatic Abyss | Avoid |
| :--- | :--- | :--- |
| **Import a function** | `puts :: extern fn(&u8) i32` | Hand-written wrappers |
| **Rename a binding** | `sin :: extern "sin" fn(f64) f64` | Re-exporting C names verbatim |
| **Export to C** | `add :: extern fn(a, b i32) i32 { a + b }` | Name mangling tricks |
| **Shared records** | `Point :: extern struct { x, y f64 }` | Manual offsets and sizes |
| **Header binding** | `extern ["stdio.h"] ...` | Restating prototypes |
| **C text** | `c"..."`, `to_cstr` | Casting `Str` to `&u8` |

---

[Previous: Modules & Imports](08-modules-and-imports.md) | [Next: Core Primitives →](../04-reference/01-core.md)

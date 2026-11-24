# Basics: Variables, Types, and Expressions

Abyss is expression-oriented: blocks produce values, `if` produces values, and a function's last expression is its result. Types are inferred when the context is unambiguous and written down at boundaries.

```abyss
main :: fn() {
    name := "the deep"
    depth: i32 = 800

    print(name)
    print(depth)
}
```

Save this as `basics.a` and run it:

```sh
abyssc r basics.a
```

---

## 1. Bindings

`:=` introduces a binding and infers its type from the value. `:` with `=` writes the type explicitly:

```abyss
count := 10
ratio := 0.75
is_ready := true
message := "ready"

small_id: u8 = 255
big_counter: u64 = 4_000_000_000
precise: f32 = 1.4142135
```

Bindings are mutable; assign with `=`:

```abyss
score := 100
score = score + 50
```

There is no `var`, `let`, or `const` keyword, and there are no compound assignment operators. Write `score = score + 1`, not `score += 1`.

### Declaring Without a Value

A scalar binding without an initializer starts at zero:

```abyss
main :: fn() {
    count: i32
    ratio: f64
    print(count)
    print(ratio)
}
```

Give struct-typed locals an explicit value. The VM does not guarantee zeroed struct locals, so initialize every field before reading:

```abyss
Point :: struct { x i32, y i32 }

main :: fn() {
    p: Point = .{ x: 0, y: 0 }
    text := Str.empty()
    print(p.x)
    print(text.len)
}
```

Module-level storage, including globals of struct type, is zero-initialized.

### Scope

Braces introduce a scope. A binding declared in an inner scope shadows an outer one and disappears when the scope ends:

```abyss
main :: fn() {
    value := 1
    {
        value := 2
        print(value)
    }
    print(value)
}
```

## 2. Compile-Time Constants

`::` declares a compile-time constant. Constants have no runtime storage and can be used wherever the compiler needs a value known ahead of time, such as an array length or a module alias:

```abyss
MAX_BUFFER :: 4096
PI :: 3.141592653589793
APP_NAME :: "Abyss"
DOUBLE_MAX :: MAX_BUFFER * 2
```

Constants are also used to alias types:

```abyss
Distance :: f64
Ids :: Vec(u64)
```

## 3. Module-Level State

At module scope, `::` creates a constant and `:=` creates a mutable global. A mutable global's initializer must be a compile-time constant:

```abyss
LIMIT :: 100
base :: 21
requests := base * 2
failures: u64

record_failure :: fn() {
    failures = failures + 1
}
```

Each module has exactly one instance of its mutable globals. Functions can read and update them, and other modules reach them as members of the imported namespace. Taking the address of a global is allowed in an initializer because its storage is fixed:

```abyss
counter: i32
saved := &counter
```

Function calls and other globals' runtime values are not compile-time constants, so they cannot initialize a mutable global. That is what constants are for.

## 4. Literals

```abyss
decimal := 42
grouped := 1_000_000
hex := 0xFF_00
binary := 0b1010_0110
octal := 0o755

real := 1.5
exponent := 2.5e10
whole_float := 3.0

flag := true
greeting := "hello"
letter := 'A'
c_string := c"null terminated"
raw := `line one
line two`
```

Integer literals may be decimal, hexadecimal (`0x`/`0X`), binary (`0b`/`0B`), or octal (`0o`/`0O`), with `_` allowed between digits. Float literals accept fractional parts and exponents.

> **Literal width limit.** Integer literals are parsed into 32 bits, so a literal such as `10000000000` wraps before it is used even when the target type is `u64`. Build large constants from smaller pieces:
>
> ```abyss
> BILLION :: cmpt { (1000000 as u64) * (1000 as u64) }
> ```
>
> Arithmetic on `u64`/`i64` values is full width; only the literal itself is limited.

## 5. Primitive Types

Integers and floats are fixed width:

| Type | Width | Notes |
| :--- | :--- | :--- |
| `i8`, `i16`, `i32`, `i64`, `i128` | 8/16/32/64/128 bits | Signed integers. |
| `u8`, `u16`, `u32`, `u64`, `u128` | 8/16/32/64/128 bits | Unsigned integers. |
| `f32`, `f64` | 32/64 bits | IEEE 754 floats. |
| `bool` | 1 byte | `true` or `false`, with no implicit integer conversion. |
| `&T` | pointer-sized | Raw pointer. |
| `fn(...) T` | pointer-sized | Function value. |
| `[N]T` | `N` elements | Fixed-size array. |
| `[]T` / `Slice(T)` | pointer plus length | Non-owning slice. |
| `A | B` | tagged | Tagged union. |

Integer and float literals start untyped and adopt a concrete type from context; when nothing constrains them, integers default to `i32` and floats to `f64`. `@type_name(@typeof(42))` reports the untyped kind `UtInt`, while `x: i32 = 42` fixes the type at `i32`.

`u128` and `i128` are 16 bytes in native builds. The bytecode VM currently models them as 64-bit, so run 128-bit arithmetic through a compiled binary.

## 6. Characters

There is no `char` type. A character literal such as `'A'` is a compile-time untyped integer and coerces to any integer type. To use one as a float, cast it explicitly (`'A' as f64`):

```abyss
newline := '\n'
ascii_code: u8 = 'A'
offset: i32 = '0'
letter_ratio := 'A' as f64
```

Escape sequences may be written in character and string literals: `\n`, `\t`, `\r`, `\0`, `\\`, `\"`, and `\'`. The lexer also accepts `\xNN` and `\u{...}`; native builds decode them, while the VM currently decodes only the common escapes listed above.

## 7. Operators

### Arithmetic

```abyss
sum := 10 + 5
difference := 20 - 4
product := 6 * 7
quotient := 40 / 8
remainder := 14 % 3
negated := -value
```

Integer division truncates toward zero: `7 / 2` is `3`.

### Bitwise and Shifts

```abyss
a := 0b1100
b := 0b1010

and_bits := a & b
or_bits := a | b
xor_bits := a ^ b
shifted_left := a << 2
shifted_right := a >> 1
inverted := ~a
```

### Comparison

`==`, `!=`, `<`, `<=`, `>`, and `>=` produce `bool`.

### Logical

Boolean logic uses the keywords `and`, `or`, and `not`. `and` and `or` short-circuit; the right operand is only evaluated when it can affect the result:

```abyss
if has_permission and is_admin {
    print("granted")
}

if not is_connected {
    print("offline")
}

if cached or load_from_disk() {
    print("available")
}
```

Conditions accept blocks, which is useful when the check has setup work:

```abyss
if {
    probe := read_sensor()
    probe > threshold
} {
    print("over threshold")
}
```

## 8. Casts

`as` converts between scalar types and between union members and their payload types:

```abyss
truncated := 300 as u8
widened := truncated as u32
ratio := 3 as f64
whole := 3.9 as i32
```

Numeric casts do not implicitly happen elsewhere; mixing `i32` and `f64` in one expression requires an explicit cast.

## 9. Expressions and Sequencing

A block evaluates to its final expression:

```abyss
result := {
    doubled := 10 * 2
    doubled + 5
}
print(result)
```

Statements are separated by newlines. A comma also separates them when you want several on one line:

```abyss
print(1), print(2), print(3)
```

No semicolons: `;` is a syntax error. Trailing commas are allowed in lists and after a final statement.

## 10. Comments

Comments are single-line and start with `--`:

```abyss
-- a comment on its own line
value := 100 -- a trailing comment
```

`//` and `/* */` are not Abyss syntax.

## 11. Strings

`"..."` produces a `Str`, an allocation-free view with a pointer and an explicit length:

```abyss
Str :: struct {
    ptr &u8
    len u64
}
```

Because the length is stored, `len` is `O(1)`, and strings may contain null bytes:

```abyss
message := "hello, Abyss"
print(message.len)
print(message.starts_with("hello"))
print(message.sub(7, 5))
```

See [Core Primitives](../04-reference/01-core.md) for the full `Str` API.

### C Strings

`c"..."` produces a null-terminated `&u8` for C APIs:

```abyss
Arena :: @import("std/allocator").Arena
to_cstr :: @import("std/string").to_cstr

main :: fn() {
    c_message := c"for the C runtime"
    view := Str.of(c_message)
    arena := Arena.new(256)
    c_again := to_cstr(&arena, view)
    print(view.len)
    arena.destroy()
}
```

`Str.of` accepts a `&u8` or a `Str` and returns a `Str` view; `to_cstr(arena, s)` allocates a NUL-terminated `&u8` copy in an arena.

## Idiomatic Summary

| Concept | Idiomatic Abyss | Avoid |
| :--- | :--- | :--- |
| **Binding** | `x := 42` | `var x: i32 = 42` |
| **Constant** | `LIMIT :: 100` | Runtime globals for fixed values |
| **Comments** | `-- note` | `// note` |
| **Text** | `name: Str` | `&u8` outside C boundaries |
| **Sequencing** | Newlines or `,` | Semicolons `;` |
| **Increment** | `x = x + 1` | `x += 1` |

---

[Previous: Tooling & Workflow](../02-quickstart/workflow.md) | [Next: Control Flow →](02-control-flow.md)

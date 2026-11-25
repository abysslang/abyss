# Language Intrinsics

This chapter is the complete list of `@builtins`, keywords, operators, and literal forms. Everything here is recognized by the compiler directly rather than declared in a module.

```abyss
main :: fn() {
    data: [2]i32 = .[1, 2]
    value: i32 | bool = true
    print(@sizeof(i32))
    print(@type_name(@element_type(@typeof(data))))
    print(@is(value, i32))
    print(@tag(value))
}
```

---

## 1. Builtins

| Builtin | Arguments | Result | Notes |
| :--- | :--- | :--- | :--- |
| `@import(path)` | compile-time `Str` | module value | Load a `.a` file and return its namespace. |
| `@source_location()` | none | `SourceLocation` | Compile-time `file`, `line`, `column` (1-based). |
| `@sizeof(T)` | one type | `u64` | Size in bytes. Header types need native output. |
| `@typeof(expr)` | one expression | `type` | Static type of `expr`. |
| `@type_name(T)` | one type | `Str` | Canonical name of `T`. |
| `@type_info(T)` | one type | `&TypeInfo()` | Reflection record for `T`. |
| `@type_from_id(n)` | compile-time integer | `type` | Type with id `n`. |
| `@field_type(S, name)` | struct or tuple, name or index | `type` | Field type by name or tuple index. |
| `@element_type(X)` | array or pointer type | `type` | Element type of `[N]T` or `&T`. |
| `@is(value, T)` | value, type | `bool` | Does the tagged union hold `T`? |
| `@tag(value)` | tagged union value | `u32` | Discriminant index. |
| `@memcpy(dest, src, bytes)` | two `&u8`, `u64` | none | Bit copy between equal-size storage. |
| `@c_value("h.h", "NAME", T)` | header, name, integer type | `T` | Read a C header value (hosted native). |
| `@trap()` | none | none | Emit an unconditional trap (`__builtin_trap()` natively). |

Arity is checked. `@sizeof`, `@typeof`, `@type_name`, `@type_info`, `@type_from_id`, `@element_type`, `@tag`, and `@import` take exactly one argument; `@field_type` and `@is` take two; `@memcpy` and `@c_value` take three; `@source_location` and `@trap` take none. Wrong counts are compile errors, and the reflection builtins report `invalid number of reflection builtin arguments` (or `@type_from_id expects exactly 1 argument`).

```abyss
main :: fn() {
    flag: i32 | bool = true
    print(@type_name(@typeof(flag)))   -- name of the union type

    destination: [4]u8
    source: [4]u8 = .[1, 2, 3, 4]
    @memcpy(&destination[0], &source[0], 4)
    print(destination[3])
}
```

## 2. Keywords and Built-in Names

| Keyword | Role |
| :--- | :--- |
| `fn` | Function or function type. |
| `struct` | Struct type (`struct { ... }`) or nominal tuple (`struct(...)`). |
| `enum` | Enum type. |
| `extern` | Foreign function, export, or C-layout struct or header binding. |
| `if`, `else` | Conditional expression. |
| `while` | Loop. |
| `for`, `in` | Iteration over an iterator or array. |
| `match` | Pattern matching over an enum or tagged union. |
| `as` | Cast or union-member conversion. |
| `ret` | Early return. |
| `break`, `cont` | Loop control (`cont` is skip-to-next; there is no `continue`). |
| `cmpt` | Compile-time evaluation of an expression or parameter. |
| `and`, `or`, `not` | Boolean logic. |
| `true`, `false` | Boolean literals. |

The list above is the full set of reserved words. Several other names are resolved by the type checker as built-ins instead of being reserved in the lexer:

| Built-in name | Role |
| :--- | :--- |
| `bool` | The boolean type. |
| `i8` … `i128`, `u8` … `u128` | Fixed-width signed and unsigned integers (8, 16, 32, 64, 128 bits). |
| `f32`, `f64` | Floating-point types. |
| `type` | The type of a type, used in parameters and return types. |
| `Self` | The enclosing struct or enum type, inside a type body. |
| `self` | A first parameter with exactly this name makes the function a method. |

There is no `union`, `void`, `let`, `var`, `const`, `null`, `return`, or `continue` keyword. A null pointer is `0 as &T`; the tagged union is written with `|`; "no return value" is an omitted return type; and early exit uses `ret`.

## 3. Operators

### Precedence

From lowest to highest binding:

1. Assignment: `=`
2. `or`
3. `and`
4. Comparison: `==`, `!=`, `<`, `<=`, `>`, `>=`
5. Bitwise or: `|`
6. Bitwise xor: `^`
7. Bitwise and: `&`
8. Shift: `<<`, `>>`
9. Term: `+`, `-`
10. Factor: `*`, `/`, `%`
11. Cast: `as`
12. Unary: `-`, `not`, `~`, `&`, `*`
13. Call: `(...)`, `[...]`
14. Member: `.`

### Arithmetic

`+`, `-`, `*`, `/`, `%`, unary `-`. Integer division truncates toward zero, so `7 / 2` is `3`.

### Bitwise

`&` (and), `|` (or), `^` (xor), `~` (unary complement), `<<` (left shift), `>>` (right shift).

### Comparison

`==`, `!=`, `<`, `<=`, `>`, `>=` produce `bool`.

### Boolean

`and`, `or`, and `not` are the boolean operators. `and` and `or` short-circuit.

### Assignment

`=` assigns. `:=` declares a mutable binding, `:` with `=` declares with an explicit type, and `::` declares a compile-time constant.

`+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, and `>>=` are tokenized but not supported: the parser rejects them with `unsupported binary operator`. Write `x = x + 1`.

### Cast and Access

`as` casts between scalars and reads a union payload. `.` is member access with automatic deep pointer dereference. `&x` takes an address, `*p` dereferences, and `p[i]` indexes a pointer or array.

## 4. Literals

```abyss
decimal := 42
grouped := 1_000_000
hex := 0xFF_00
binary := 0b1010_0110
octal := 0o755

ratio := 1.5
exponent := 2.5e10
whole := 3.0

flag := true
letter := 'A'
text := "a string"
c_text := c"a C string"
raw := `raw
multi-line`
```

| Literal | Type | Notes |
| :--- | :--- | :--- |
| Decimal, `0x`, `0b`, `0o` | untyped int | `_` separators allowed. Parsed to 32 bits. |
| Float, exponent | untyped float | `1.5`, `1e6`, `2.5e-4`. |
| `true`, `false` | `bool` | |
| `'A'` | untyped int | There is no `char` type. |
| `"..."` | `Str` | Escapes decoded by the target. |
| `` `...` `` | `Str` | Raw multi-line; no escape processing. |
| `c"..."` | `&u8` | Null-terminated C string. |
| `.{ name: val }` | struct | Contextual struct literal. |
| `.(v1, v2)`, `.()` | tuple | Structural or contextual nominal tuple literal. |
| `.[v1, v2]` | array | Contextual fixed-size array literal. |

A null pointer has no literal; write `0 as &T`.

Integer literals are limited to 32 bits at parse time, so a value like `10000000000` wraps before it is used. Build large constants from smaller pieces at compile time:

```abyss
BILLION :: cmpt { (1000000 as u64) * (1000 as u64) }
```

String and character escapes cover `\n`, `\t`, `\r`, `\0`, `\\`, `\"`, and `\'`. `\xNN` and `\u{...}` are accepted by the lexer; native builds decode them, and the VM decodes the common set above.

## 5. Separators and Comments

Statements and list items are separated by newlines or commas. A comma groups names in a shared declaration and separates several statements on one line:

```abyss
add :: fn(a, b i32) i32 { a + b }

main :: fn() {
    print(1), print(2)
    values := .[
        10
        20
    ]
    print(values[1])
}
```

Semicolons are a syntax error everywhere. A trailing comma is allowed in a list or after a statement. Comments are single-line and begin with `--`; `//` and `/* */` are not Abyss syntax, and there are no doc-comment forms.

---

[Previous: System & Threading](06-sys-and-threading.md) | [Next: Pods & Testing →](08-pods-and-testing.md)

# Comptime & Metaprogramming

Metaprogramming in Abyss is ordinary Abyss code. The compiler contains a bytecode VM that runs `cmpt` expressions while type-checking, and a `#` operator that turns a compile-time `Str` into code at the exact point it appears.

```abyss
SUM_TO_100 :: cmpt {
    total := 0
    i := 1
    while i <= 100 {
        total = total + i
        i = i + 1
    }
    total
}

triple_code :: fn() Str {
    "fn(x i32) i32 { x * 3 }"
}

triple :: #triple_code()

main :: fn() {
    print(SUM_TO_100)
    print(triple(5))
}
```

---

## 1. Compile-Time Evaluation with `cmpt`

`cmpt` forces its operand to be evaluated before code generation. It can decorate a constant, a block, a function call, or a single expression:

```abyss
FACTORIAL_10 :: cmpt {
    fact :: fn(n u64) u64 {
        if n <= 1 { 1 } else { n * fact(n - 1) }
    }
    fact(10)
}

main :: fn() {
    print(FACTORIAL_10)
}
```

The VM runs the block once, and the emitted code contains only the resulting literal. Loops, functions, and control flow are all available; anything the VM can compute is fair game.

`cmpt` also marks call sites, which is handy when an argument must be a value rather than a runtime expression:

```abyss
main :: fn() {
    print(cmpt 2 + 2)
}
```

### What Comptime Can and Cannot Do

Compile-time code runs in a sandbox separate from runtime state:

- Compile-time evaluation cannot read or write a mutable global (`mutable global cannot be accessed at compile time`).
- A mutable global's initializer must itself be a compile-time constant (`mutable global initializer must be a compile-time constant`).
- A pointer produced inside `cmpt` cannot be stored in runtime storage (`compile-time pointers cannot escape into runtime code`).

Arena allocation, loops, and reflection all work at compile time, which is what makes generated code practical.

## 2. String Splices with `#`

`#` takes an expression that evaluates to a compile-time `Str`, parses that string as Abyss source, and inlines the result where the `#` appears. It is a mixin, so the generated code sees the surrounding names:

```abyss
main :: fn() {
    x := 5
    result := #("x + 100")
    print(result)

    values := #"40 + 2"
    print(values)
}
```

The expression after `#` may be a string literal, a parenthesized expression, or a call that returns a `Str`:

```abyss
make_expr :: fn() Str {
    "40 + 2"
}

choose :: fn(add bool) Str {
    if add { "100 + 50" } else { "100 - 50" }
}

main :: fn() {
    print(#make_expr())
    print(#(choose(true)))
}
```

A splice can stand in for a whole declaration. The `name :: #splice()` form binds the generated source to `name`: when the splice yields a `struct`, `enum`, or `fn`, `name` becomes that type or function. Backtick raw strings keep newlines intact and are the natural template form:

```abyss
Helpers :: struct {
    tag i32

    #`
    inc :: fn(x i32) i32 { x + 1 }
    dec :: fn(x i32) i32 { x - 1 }
    `
}

main :: fn() {
    print(Helpers.inc(10))
    print(Helpers.dec(10))
}
```

Use `fmt` from `std/fmt` to build parameterized templates instead of concatenating by hand:

```abyss
fmt :: @import("std/fmt").fmt
Arena :: @import("std/allocator").Arena

gen_scale :: fn(factor i32) Str {
    arena := Arena.new(256)
    fmt(&arena, "fn(v i32) i32 {{ v * {} }}", .(factor)).as_str()
}

scaled :: #gen_scale(4)

main :: fn() {
    print(scaled(5))
}
```

A generator that returns `""` contributes no code, so a splice can stay silent on purpose.

## 3. Multi-Level Splices

`##expr` is exactly `#(#expr)`: the inner splice runs first and its result is spliced again. Each extra `#` adds one expansion round, so `###expr` is `#(#(#expr))`.

```abyss
make_inner :: fn() Str {
    "\"100 + 200\""
}

main :: fn() {
    value := ##make_inner()
    print(value)
}
```

One `#` would have produced the string literal `"100 + 200"`; the second round parses that literal and evaluates it to `300`. This staging lets a generator emit another generator without hand-escaping the inner source.

## 4. Macro Templates

A function whose body is a single splice is a macro template. Writing `#name(args)` at a call site inlines the template with `args` bound, and the template's own `cmpt` parameters and reflection run at that call site:

```abyss
double_code :: fn() Str {
    "*target = *target + *target"
}

double :: fn(T type, target &T) {
    #double_code()
}

main :: fn() {
    value := 10
    #double(&value)
    print(value)
}
```

The body is pasted directly at the site instead of being a runtime call, and `#` parameters can appear wherever the generated code needs them, including type positions:

```abyss
choose_type :: fn(big bool) Str {
    if big { "i64" } else { "i32" }
}

main :: fn() {
    wide: #choose_type(true) = 111111
    print(wide)
}
```

Macro templates are what let `print` and `write` format arbitrary values. Both are ordinary functions in `std/io` whose bodies splice reflection-driven code specialized to the argument type.

## 5. Reflection

`@type_info(T)` returns a `&TypeInfo()` describing a type, available at compile time and at runtime:

```abyss
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
```

Read it directly for a concrete type. Inside `cmpt`, it produces values you can compute with:

```abyss
Record :: struct {
    pair   (i32, bool)
    values [3]u16
}

main :: fn() {
    print(cmpt { info := @type_info(Record), info.name })
    print(cmpt { info := @type_info(Record), info.field_count })
    print(cmpt { info := @type_info(Record), info.fields[0].name })
}
```

- `name` is the canonical type name; `kind` is a `TypeKind` such as `struct_`, `enum_`, `union_`, `ptr`, or `func`.
- `fields` and `field_count` list fields or enum variants; each `FieldInfo` has `name`, `type_info`, and a `value` for enum members.
- `element` and `length` describe arrays and pointers; `members` and `member_count` list tagged-union alternatives.
- `params`, `param_count`, `result`, and `is_extern` describe function types.

Companion builtins extract single pieces without walking the record:

```abyss
User :: struct {
    id      u64
    address struct { city Str }
}

main :: fn() {
    print(@type_name(&[2]i32))
    print(@type_name(@field_type(User, "id")))
    print(@type_name(@element_type([4]u16)))
    print(@sizeof(User))
}
```

| Builtin | Result |
| :--- | :--- |
| `@type_name(T)` | Canonical name of `T` as `Str`. |
| `@typeof(expr)` | The static type of `expr`. |
| `@sizeof(T)` | Size of `T` in bytes (`u64`). |
| `@field_type(S, name)` | Field type of struct `S` by name, or tuple by index. |
| `@element_type(X)` | Element type of `[N]T` or `&T`. |
| `@type_from_id(n)` | The type with compile-time id `n`. |

### Formatting by Reflection

`print` and `write` are themselves macro templates that splice reflection-driven code, so `#print(x)` and `#write(x)` generate a printer specialized to the argument's type at compile time. `print` is in the prelude; import `write` before splicing it. No reflection metadata is bundled into the binary; the calls expand to straight-line field walks:

```abyss
Record :: struct {
    pair   (i32, bool)
    values [3]u16
}

main :: fn() {
    record: Record = .{ pair: .(42, true), values: .[1, 2, 3] }
    #print(record)
}
```

## 6. Compile-Time Failures and Source Locations

`#fall` aborts compilation with a message, and the standard library's `fall` splice reports the current `@source_location()` before exiting with status 1:

```abyss
fall :: @import("std/sys").fall

Record :: struct { value i32 }

main :: fn() {
    size := cmpt @sizeof(Record)
    if size > 64 {
        #fall
    }
    print(size)
}
```

The usual pattern is to check the invariant inside `cmpt` and fall only when it fails. `fall_at(location)` does the same for a location you already hold.

`@source_location()` is a compile-time `SourceLocation` with `file`, `line`, and `column`, all 1-based:

```abyss
where :: fn() {
    location := @source_location()
    print(location.file)
    print(location.line)
}

main :: fn() {
    where()
}
```

Code produced by a splice reports the location of the splice invocation, including through nested splices, so diagnostics always point at real source.

## Idiomatic Summary

| Metaprogramming | Idiomatic Abyss | Avoid |
| :--- | :--- | :--- |
| **Compile-time math** | `cmpt { ... }` | External generator scripts |
| **Code injection** | `#` over a `Str` template | Copy-pasted declarations |
| **Type inspection** | `@type_info(T)` inside `cmpt` | Runtime vtables |
| **Printing values** | `print(x)` or `#print(x)` | Hand-written per-type formatters |
| **Static checks** | `cmpt { if bad { #fall } }` | Runtime asserts for build invariants |

---

[Previous: Generics & Types](06-generics-and-types.md) | [Next: Modules & Imports →](08-modules-and-imports.md)

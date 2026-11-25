# Structs & Data Types

Structs, tuples, enums, and tagged unions are the four ways an Abyss program describes data. Each is a plain value with an explicit layout, and each maps directly onto a C99 type in the backend.

```abyss
Point :: struct {
    x i32
    y i32
}

Shape :: enum { circle, square, triangle }

main :: fn() {
    origin: Point = .{ x: 0, y: 0 }
    print(origin.x)

    shape := Shape.square
    print(shape as u32)
}
```

Everything here is a value: it is copied when assigned, passed, or returned, and the compiler lays it out with natural alignment and no hidden bookkeeping.

---

## 1. Structs

A struct lists its fields with `name Type` pairs. Fields sharing a type may be grouped:

```abyss
User :: struct {
    id        u64
    name      Str
    is_active bool
}

Rect :: struct {
    x, y, w, h i32
}
```

There are no colons between a field name and its type, and fields are separated by newlines or commas. `x: i32` and `x i32;` are both errors.

Functions declared inside the braces are namespaced to the struct and become methods or constructors. See [Functions & Methods](03-functions-and-methods.md) for the `self` receiver rules and `Self`.

```abyss
Circle :: struct {
    radius f64

    new :: fn(radius f64) Self {
        .{ radius: radius }
    }

    area :: fn(self &Self) f64 {
        3.141592653589793 * self.radius * self.radius
    }
}

main :: fn() {
    c := Circle.new(2.0)
    print(c.area())
}
```

### Layout

A struct contains exactly the fields you declare, in the order you declare them, with the target's natural alignment and padding. There is no vtable, no reference count, and no padding beyond what alignment requires. An empty struct becomes a single dummy byte in the emitted C so that it has a non-zero size, as C requires.

## 2. Constructing Structs

Struct values use an anonymous literal `.{ field: value, ... }`. The type comes from the context: an explicit annotation, a parameter type, or a return type.

```abyss
User :: struct {
    id        u64
    name      Str
    is_active bool
}

main :: fn() {
    user: User = .{
        id: 101
        name: "Alex"
        is_active: true
    }
    print(user.name)
}
```

A struct literal must supply **every** field. A missing field is a compile error, which keeps values fully initialized and removes the classic C footgun of partially filled structs:

```abyss
-- ERROR: struct literal has wrong number of fields
partial: User = .{ id: 1 }
```

Fields can be listed on one line or one per line; newlines replace commas, so a vertical layout needs no trailing commas.

### Anonymous Structs

When no named type is needed, an unannotated literal infers a fresh anonymous struct type:

```abyss
main :: fn() {
    config := .{
        host: "127.0.0.1"
        port: 8080
    }
    print(config.host)
    print(config.port)
}
```

The literal is a value like any other, so it can be copied, returned, and stored:

```abyss
main :: fn() {
    a := .{ x: 1, y: 2 }
    b := a
    print(b.x + b.y)
}
```

## 3. Tuples

A structural tuple type is an ordered list of element types, such as `(i32, Str)`. Two structural tuples have the same type when their element types match in order. Naming one with a binding creates an alias. Use `struct(i32, Str)` to declare a distinct nominal tuple whose name comes from the binding.

```abyss
Pair :: struct(i32, Str)
IntPair :: (i32, i32)

min_max :: fn(a i32, b i32) IntPair {
    if a < b { .(a, b) } else { .(b, a) }
}

main :: fn() {
    (low, high) := min_max(7, 3)
    print(low)
    print(high)

    pair: Pair = .(100, "text")
    print(pair.0)

    ((number, _), label) := .(pair, "result")
    print(number)
    print(label)
}
```

- Use `.(values)` for tuple literals, `.[values]` for arrays, and `.{ name: value }` for structs.
- Use `(T,)` for a one-element structural type (`(T)` is ordinary grouping), and `()` for the empty tuple type (literal `.()`). Nominal tuples use `struct(T)` and `struct()` directly without a trailing comma.
- Access elements by zero-based position: `.0`, `.1`, and so on. Reflection reports both tuple forms as `TypeKind.tuple`, with element types in position order.
- Destructuring declares local variables and evaluates the source once. Patterns can nest and use `_` to discard an element. Each pattern must have the same arity as the corresponding tuple, and names must be unique within the pattern. Use `(value,)` for a one-element pattern and `()` for the empty tuple.
- A tuple literal can initialize a nominal tuple where the expected type is known. Once created, a nominal tuple value cannot be assigned to a structural tuple or a different nominal tuple with the same elements.

## 4. Enums

An enum is a closed set of named integral constants. The backing integer type defaults to `u32` and can be chosen explicitly:

```abyss
Color :: enum { red, green, blue }

HttpStatus :: enum u16 {
    ok = 200
    not_found = 404
}

main :: fn() {
    print(Color.green as u32)
    print(HttpStatus.ok as u32)
}
```

- Variants are referenced as `EnumName.variant`.
- A variant without an explicit value takes the next integer; an explicit value sets the sequence from that point.
- Convert between an enum and its backing integer with `as` in either direction. Matching on an enum value is covered in [Control Flow](02-control-flow.md).

Enums can hold methods, which is how to attach behavior to a variant:

```abyss
Color :: enum {
    red, green, blue

    label :: fn(self &Self) Str {
        match *self {
            red { "red" }
            green { "green" }
            blue { "blue" }
        }
    }
}

main :: fn() {
    print(Color.blue.label())
}
```

## 5. Tagged Unions

A tagged union is written as the set of types it may hold, joined with `|`. The value carries a hidden `u32` tag alongside the payload:

```abyss
Number :: i32 | bool

describe :: fn(value i32 | bool) Str {
    if @is(value, i32) { "int" } else { "bool" }
}

main :: fn() {
    n: Number = 42
    print(describe(n))
    print(describe(true))
}
```

There is no `union` keyword; the `|` type form is the tagged union. An unannotated value coerces into the union automatically, and every payload shares the same aligned storage.

Introspect a union value with three builtins:

| Builtin | Returns | Use |
| :--- | :--- | :--- |
| `@is(value, T)` | `bool` | Does this value currently hold `T`? |
| `@tag(value)` | `u32` | Numeric discriminant (the member index). |
| `value as T` | `T` | Read the payload as `T` after a successful check. |

```abyss
main :: fn() {
    value: i32 | bool = true
    print(@is(value, i32))
    print(@is(value, bool))
    print(@tag(value))
    print(value as bool)
}
```

`match` reads a union more directly, optionally binding the unwrapped payload. See [Control Flow](02-control-flow.md) for the full pattern syntax:

```abyss
print_value :: fn(value i32 | bool) {
    match inner in value {
        i32  { print(inner) }
        bool { print(inner) }
    }
}

main :: fn() {
    print_value(7)
    print_value(true)
}
```

## 6. Type Introspection

Two builtins report types without running anything:

```abyss
main :: fn() {
    value := 42
    print(@type_name(@typeof(value)))   -- "i32"
    print(@sizeof(u64))                 -- 8
}
```

`@typeof(expr)` is the static type of `expr`, and `@type_name(T)` is its canonical name as a compile-time `Str`. Both are zero-cost. The full reflection surface — `@type_info`, `@field_type`, `@element_type`, and the `TypeInfo` record — is covered in [Comptime & Metaprogramming](07-comptime-and-metaprogramming.md).

## Idiomatic Summary

| Concept | Idiomatic Abyss | Avoid |
| :--- | :--- | :--- |
| **Fields** | `x i32` | `x: i32;` |
| **Struct literals** | `.{ x: 1, y: 2 }` | Named-argument constructors |
| **Tuple types & literals** | `(i32, Str)`, `struct(i32, Str)`, `.(1, "a")` | Mixing positional fields into `.{...}` |
| **Tuple destructuring** | `(a, (b, _)) := pair` | `a, b := pair` |
| **Enclosing type** | `Self` | Repeating the struct name |
| **Optional variants** | Tagged unions with `@is`/`match` | Untagged `void *` payloads |
| **Type name** | `@type_name(T)` | Hand-written name strings |

---

[Previous: Functions & Methods](03-functions-and-methods.md) | [Next: Pointers, Arrays & Memory →](05-pointers-and-memory.md)

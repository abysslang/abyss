# Generics & Types

Types are ordinary values in Abyss. A function can take a type as a parameter and return a type, and the compiler builds a separate concrete copy of the code for each set of arguments it sees. There are no interfaces, vtables, or runtime type dispatch.

```abyss
identity :: fn(T type, value T) T {
    value
}

main :: fn() {
    print(identity(42))
    print(identity("Abyss"))
}
```

`T` is a parameter of type `type`. The two calls instantiate `identity` twice: once for `i32` and once for `Str`. Each instantiation is a normal, fully typed function.

---

## 1. Type Parameters

A parameter with the `type` type is a compile-time type argument. A function can take any number of them, in any position:

```abyss
add :: fn(T type, a, b T) T {
    a + b
}

main :: fn() {
    print(add(1, 2))
    print(add(1.5, 2.5))
}
```

Consecutive type parameters may be grouped:

```abyss
swap :: fn(T, U type, t struct { T, U }) struct { U, T } {
    .{ t.1, t.0 }
}

main :: fn() {
    a, b := swap(.{ 1, "one" })
    print(a)
    print(b)
}
```

Type arguments are checked when the function is instantiated. Using an operation that the concrete type does not support is a type error at that instantiation:

```abyss
-- ERROR when instantiated with a type that lacks '*':
square :: fn(T type, value T) T {
    value * value
}
```

There are no declared bounds; a generic function simply states the operations it needs through its body, and each instantiation is verified against the concrete type.

## 2. Deferred Inference

The type argument can usually be left out and inferred from the surrounding arguments or from later use:

```abyss
main :: fn() {
    numbers := Vec().new()
    numbers.push(7 as u32)        -- infers Vec(u32)
    print(numbers.len)

    names := Vec().with_cap(8)
    names.push("Ada")             -- infers Vec(Str)
}
```

Pass the type explicitly only when nothing else determines it:

```abyss
main :: fn() {
    zeroed := zero(u64)
    print(zeroed)
}

zero :: fn(T type) T {
    value: T
    value
}
```

When an argument cannot be inferred, the compiler says `cannot infer generic type argument; pass the type explicitly`, which is a prompt to write it down rather than a limitation.

## 3. Value Parameters

A parameter can carry a compile-time value, not just a type. Mark it with `cmpt` inside the parameter list:

```abyss
repeat :: fn(T type, cmpt count u64, value T) struct { T, u64 } {
    .{ value, count }
}
```

The value must be computable at compile time, and it may be used where a constant is required, such as an array length:

```abyss
Buffer :: fn(T type, cmpt N u64) type {
    struct {
        items [N]T
    }
}

main :: fn() {
    b: Buffer(i32, 4) = .{ items: .[1, 2, 3, 4] }
    print(b.items[3])
}
```

A plain integer parameter used as an array length is also accepted and folded at compile time, so both spellings are common:

```abyss
Grid :: fn(N u64) type {
    struct { cells [N]i32 }
}
```

Compile-time parameters are limited to integer, `bool`, and `Str` types. A `cmpt` parameter must stand on its own — grouping it into a shared declaration such as `a, cmpt b u32` is rejected — and it cannot appear in an `extern` declaration.

## 4. Type Functions

A type function is any function whose return type is `type`. It runs at compile time and produces a struct, union, enum, or alias:

```abyss
Box :: fn(T type) type {
    struct {
        value T

        new :: fn(value T) Self { .{ value: value } }
        get :: fn(self &Self) T { self.value }
    }
}

Pair :: fn(T, U type) type {
    struct {
        first  T
        second U
    }
}

main :: fn() {
    b := Box().new(42 as u32)
    print(b.get())
}
```

Type functions can branch on their arguments, which makes helper types like `int_by_size` possible:

```abyss
int_by_size :: fn(sz u32) type {
    if sz == 1 {
        u8
    } else if sz == 2 {
        u16
    } else if sz == 4 {
        u32
    } else {
        u64
    }
}

Alias :: int_by_size(2)

main :: fn() {
    small: Alias = 1000 as u16
    print(small as u32)
}
```

A type function is a value, so it can be stored in a binding and called later:

```abyss
main :: fn() {
    V := Vec()
    v := V.new()
    v.push(1)
    print(v.len)
    v.destroy()
}
```

Type names flow through the whole language. `@typeof(expr)` yields a `type`, and `@type_from_id(n)` reconstructs a type from a compile-time integer id:

```abyss
main :: fn() {
    Item :: @type_from_id(cmpt { info := @type_info(u32), info.id })
    x: Item = 99
    print(x)
}
```

## 5. Function Types and Aliases

A function type is written `fn(T1, T2) R`. Name one at top level to create a reusable alias:

```abyss
Compare :: fn(i32, i32) i32

ascending :: fn(a i32, b i32) i32 { a - b }
doubled :: fn(value i32) i32 { value * 2 }

main :: fn() {
    cmp: Compare = ascending
    print(cmp(3, 5))

    fn_ptr: fn(i32) i32 = doubled
    print(fn_ptr(21))
}
```

When a generic function is used as a value, the surrounding context fixes its type arguments:

```abyss
main :: fn() {
    callbacks := Vec().new()
    callbacks.push(double)
    cb := callbacks.get(0)
    print(cb(4))
}

double :: fn(value i32) i32 { value * 2 }
```

Function values are ordinary code pointers. There are no closures in this release: pass captured state as an explicit argument, or store it in a struct next to the function.

## 6. Monomorphization

Each distinct set of type and value arguments produces exactly one specialized copy of the generic function or type, and it is shared by every call site that uses the same arguments. Two calls with different arguments get different copies; two calls with identical arguments reuse one.

```abyss
main :: fn() {
    a := Vec().new()
    b := Vec().new()
    a.push(1 as u32)
    b.push(2 as u32)      -- same instantiation as 'a'
    print(a.len + b.len)
    a.destroy()
    b.destroy()
}
```

The consequences are the usual zero-cost guarantees:

- The emitted C contains only the instantiations your program actually uses.
- Generic calls compile to direct, specialized code with no dynamic dispatch.
- `@sizeof(Vec(u32))` is resolved at compile time.

A generic struct that refers to itself only through a pointer is fine; a value cycle, such as a struct containing itself by value, is an error (`recursive value type has infinite size`). A type function whose expansion never bottoms out is also rejected (`generic type specialization exceeded recursion limit`) instead of hanging the compiler.

## Idiomatic Summary

| Concept | Idiomatic Abyss | Avoid |
| :--- | :--- | :--- |
| **Type parameter** | `fn(T type, x T) T` | Special-cased overloads |
| **Inference** | `Vec().new()` then `push(x)` | Repeating type arguments at every call |
| **Compile-time value** | `fn(T type, cmpt N u64) type` | Runtime length checks |
| **Branching on a type** | `fn(c bool) type { ... }` | Duplicated declarations |
| **Function value** | `fn(i32) i32` alias | Manual `&u8` casts |

---

[Previous: Pointers, Arrays & Memory](05-pointers-and-memory.md) | [Next: Comptime & Metaprogramming →](07-comptime-and-metaprogramming.md)

# Functions & Methods

Functions are declared with `fn`, a parameter list, an optional return type, and a body. There is no `return` keyword; the last expression in a block is the value, and `ret` exits early.

```abyss
add :: fn(a, b i32) i32 {
    a + b
}

Rectangle :: struct {
    width  i32
    height i32

    new :: fn(width i32, height i32) Self {
        .{ width: width, height: height }
    }

    area :: fn(self &Self) i32 {
        self.width * self.height
    }
}

main :: fn() {
    print(add(2, 3))
    print(Rectangle.new(5, 10).area())
}
```

---

## 1. Signatures

```abyss
compute_tax :: fn(amount f64, rate f64) f64 {
    amount * rate
}
```

Consecutive parameters may share a type:

```abyss
multiply :: fn(a, b i32) i32 {
    a * b
}
```

Omit the return type when the function returns nothing. There is no `void` or `unit` keyword:

```abyss
log_event :: fn(name Str) {
    print(name)
}
```

Parameters are usually named, but a function type may list only types. Definitions accept type-only parameters too; the values are simply unreachable, so named parameters are the practical choice.

## 2. Returns

The last expression of a function block is its return value:

```abyss
clamp :: fn(value i32, low i32, high i32) i32 {
    if value < low {
        low
    } else if value > high {
        high
    } else {
        value
    }
}
```

Use `ret` for early exit:

```abyss
find_user_id :: fn(username Str) i32 {
    if username.len == 0 {
        ret -1
    }
    username.len as i32
}
```

`ret` with no value returns from a function that has no return type:

```abyss
dump :: fn(label Str) {
    if label.len == 0 { ret }
    print(label)
}
```

A function that calls `#fall` produces the `Never` type, so it type-checks in any branch.

## 3. Methods

Functions declared inside a struct or enum are namespaced. A function whose first parameter is named `self` is a method:

```abyss
Vector2 :: struct {
    x f64
    y f64

    new :: fn(x f64, y f64) Self {
        .{ x: x, y: y }
    }

    zero :: fn() Self {
        .{ x: 0.0, y: 0.0 }
    }

    length_sq :: fn(self &Self) f64 {
        self.x * self.x + self.y * self.y
    }
}

main :: fn() {
    v := Vector2.new(3.0, 4.0)
    print(v.length_sq())
    print(Vector2.zero().x)
}
```

- `new` and `zero` have no `self` parameter, so they are static and called as `Vector2.new(...)`.
- `length_sq` takes `self &Self`, so it is a method and is called as `v.length_sq()`. The compiler takes the address of `v` for you.
- The receiver must be named exactly `self`. A first parameter with any other name is treated as a static function, so it has to be called through the type with the value passed explicitly.

`Self` is available inside a named struct or enum. It refers to the enclosing type, so constructors can return `Self` without repeating the name. Pointers work the same way: a method on `self &Self` can be called through a value, a pointer, or a longer auto-dereferenced chain.

### Returning `self` for Chaining

Return `&Self` to keep mutating the same instance:

```abyss
Counter :: struct {
    value i32

    new :: fn() Self {
        .{ value: 0 }
    }

    add :: fn(self &Self, amount i32) &Self {
        self.value = self.value + amount
        self
    }

    get :: fn(self &Self) i32 {
        self.value
    }
}

main :: fn() {
    counter := Counter.new()
    print(counter.add(2).add(3).get())
}
```

## 4. Function Values

`fn(T) R` is a function type and can be written anywhere a type is expected:

```abyss
double :: fn(value i32) i32 { value * 2 }

apply :: fn(work fn(i32) i32, value i32) i32 {
    work(value)
}

main :: fn() {
    print(apply(double, 21))

    inline := fn(value i32) i32 { value + 1 }
    print(inline(1))

    pointer: fn(i32) i32 = double
    print(pointer(4))
}
```

A top-level declaration with no body and no `extern` is a function type alias:

```abyss
Callback :: fn(i32) bool

is_big :: fn(value i32) bool {
    value > 10
}

main :: fn() {
    cb: Callback = is_big
    print(cb(20))
}
```

Function values may be stored in struct fields, returned from functions, and passed across module boundaries:

```abyss
Ops :: struct {
    op fn(i32, i32) i32
}

add :: fn(a, b i32) i32 { a + b }

make_ops :: fn() Ops {
    .{ op: add }
}

main :: fn() {
    print(make_ops().op(10, 5))
}
```

Function values are ordinary pointers to code. There are no closures in this release: capture the environment by passing it as an explicit argument or by storing it in a struct that also holds the function.

## 5. Generic Parameters

Generics are ordinary parameters with the `type` type (or `cmpt` value parameters). The compiler instantiates a specialized function for each concrete argument set:

```abyss
identity :: fn(T type, value T) T {
    value
}

main :: fn() {
    number := identity(42)
    text := identity("Abyss")
    print(number)
    print(text)
}
```

Type and value parameters may be placed wherever they read best:

```abyss
add :: fn(T type, a, b T) T {
    a + b
}

zeroed :: fn(T type) T {
    value: T
    value
}

main :: fn() {
    print(add(1, 2))
    print(add(1.5, 2.5))
    print(zeroed(u32))
}
```

Arguments are inferred from the other parameters whenever possible, so `add(1, 2)` needs no explicit type. Provide them explicitly when nothing else determines the type: `zeroed(u32)`.

Value parameters let a type or function depend on an integer:

```abyss
Container :: fn(T type, N u64) type {
    struct {
        items [N]T
    }
}

main :: fn() {
    c: Container(i32, 2) = .{ items: .[1, 2] }
    print(c.items[0] + c.items[1])
}
```

See [Generics & Types](06-generics-and-types.md) for monomorphization details.

## 6. Recursion

Functions may call themselves directly. Top-level names are visible before their declaration, so mutual recursion needs no forward declaration:

```abyss
is_even :: fn(n i32) bool {
    if n == 0 { ret true }
    is_odd(n - 1)
}

is_odd :: fn(n i32) bool {
    if n == 0 { ret false }
    is_even(n - 1)
}

main :: fn() {
    print(is_even(10))
}
```

## Idiomatic Summary

| Concept | Idiomatic Abyss | Avoid |
| :--- | :--- | :--- |
| **No return value** | `log :: fn(msg Str) { ... }` | `fn(msg Str) void` |
| **Tail value** | `a + b` | `ret a + b` as the last line |
| **Early exit** | `ret 0` | `return 0` |
| **Receiver** | `self &Self` | Explicit address at every call site |
| **Chaining** | `obj.add(1).add(2)` | Addressing the object again |

---

[Previous: Control Flow](02-control-flow.md) | [Next: Structs & Data Types →](04-structs-and-types.md)

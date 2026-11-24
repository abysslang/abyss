# Whirlwind Tour

This tour gets you comfortable with Abyss syntax in about ten minutes. Every snippet is a complete program: save it as `tour.a` and run `abyssc r tour.a`, or build a native binary with `abyssc b tour.a out.c` followed by your C compiler.

---

## 1. Hello, World!

```abyss
main :: fn() {
    print("Hello from the deep!")
}
```

There is no `void` keyword and no `return` keyword. A function without a return type returns nothing, and the last expression in a block is its value.

`print` writes its formatted argument followed by a newline. `printf` writes a template with no automatic newline. Both come from the prelude, so no import is needed.

## 2. Bindings and Comments

Comments start with `--` and run to the end of the line. `:=` introduces a binding and infers its type. `::` declares a compile-time constant:

```abyss
-- this is a comment
x := 42
pi: f32 = 3.14159
name := "Abyss"
active := true

LIMIT :: 4096

main :: fn() {
    x = x + 10
    print(name)
    print(active)
    print(pi)
    print(LIMIT)
}
```

Values bound with `:=` are mutable; assign to them with `=`. Constants bound with `::` are compile-time values and cannot be assigned. Statements are separated by newlines; a comma also works when you want several on one line:

```abyss
main :: fn() {
    a := 1, b := 2
    print(a + b)
}
```

There are no semicolons. A `;` is a syntax error.

## 3. Control Flow

Parentheses around conditions are optional; braces are required:

```abyss
depth :: fn(meters i32) Str {
    if meters > 1000 {
        "crushing pressure"
    } else if meters > 200 {
        "twilight zone"
    } else {
        "near the surface"
    }
}

main :: fn() {
    print(depth(500))

    i := 0
    while i < 5 {
        i = i + 1
        if i == 2 { cont }
        if i > 4 { break }
        print(i)
    }
}
```

`if` is an expression, so it can produce a value directly. `while` loops can also take a block condition, which lets you run code before testing:

```abyss
main :: fn() {
    n := 0
    while {
        n = n + 1
        n < 4
    } {
        print(n)
    }
}
```

`for` iterates anything with a `next()` method or an `iter()` method, and arrays and slices are iterable directly:

```abyss
main :: fn() {
    for n in Range.new(0, 3) {
        print(n)
    }

    values: [3]i32 = .[10, 20, 30]
    for v in values {
        print(v)
    }

    for a, b in Range.new(0, 2), Range.new(10, 12) {
        print(a + b)
    }
}
```

`match` works on enums and tagged unions, must be exhaustive unless it has an `else` arm, and uses no arrow:

```abyss
Color :: enum { red, green, blue }

main :: fn() {
    c := Color.green
    match c {
        red { print("warm") }
        green, blue { print("cool") }
    }
}
```

## 4. Functions and Methods

Parameters are written `name Type`, and consecutive parameters can share a type:

```abyss
add :: fn(a, b i32) i32 {
    a + b
}

Rectangle :: struct {
    width i32
    height i32

    new :: fn(width i32, height i32) Self {
        .{ width: width, height: height }
    }

    area :: fn(self &Self) i32 {
        self.width * self.height
    }
}

main :: fn() {
    rect := Rectangle.new(5, 10)
    print(add(2, 3))
    print(rect.area())
}
```

The last expression in a block is the return value. Use `ret` to leave early:

```abyss
clamp :: fn(value i32, low i32, high i32) i32 {
    if value < low { ret low }
    if value > high { ret high }
    value
}
```

## 5. Structs, Tuples, Enums, and Unions

Struct fields use `name Type` with no colon. Instances are built with `.{}`:

```abyss
Point :: struct {
    x i32
    y i32
}

main :: fn() {
    p: Point = .{ x: 3, y: 4 }
    print(p.x)

    pair := .{ 10, "ten" }
    first, second := pair
    print(first)
    print(second)
}
```

Enums can carry methods and an explicit backing type. Tagged unions are written `A | B`, and you check, tag, match, or cast them:

```abyss
Status :: enum u8 { ok = 200, not_found = 404 }

describe :: fn(value i32 | bool) Str {
    match payload in value {
        i32 { "an integer" }
        bool { "a boolean" }
    }
}

main :: fn() {
    print(Status.ok as u32)
    print(describe(7))
    print(describe(true))
}
```

## 6. Pointers, Arrays, and Memory

`&T` is a pointer, `&value` takes an address, and `.` dereferences pointers automatically, however deep the chain:

```abyss
Arena :: @import("std/allocator").Arena

Node :: struct {
    value i32
    next &Node
}

main :: fn() {
    arena := Arena.new(4096)

    first := arena.alloc(@sizeof(Node)) as &Node
    first.value = 1
    second := arena.alloc(@sizeof(Node)) as &Node
    second.value = 2
    first.next = second

    print(first.next.value)
    arena.destroy()
}
```

`Arena` is not in the prelude, so the import at the top is required. Arrays use `[N]T` and `.[ ... ]`, and slices use `[]T` or `Slice(T)`:

```abyss
main :: fn() {
    values: [4]i32 = .[10, 20, 30, 40]
    print(values[0])
    values[1] = 99

    view: []i32 = Slice(i32).new(&values[0], 4)
    print(view.len)
}
```

## 7. Compile-Time Execution

`cmpt` evaluates an expression on the compiler's VM before the program runs:

```abyss
TABLE :: cmpt {
    base := 64
    factor := 4
    base * factor + 12
}

main :: fn() {
    print(TABLE)
}
```

`#` splices compile-time text into the program. A splice can supply a type, or generate members inside a struct or enum body:

```abyss
make_point_type :: fn() Str {
    "struct { x i32, y i32 }"
}

Point :: #make_point_type()

main :: fn() {
    p: Point = .{ x: 3, y: 4 }
    print(p.x + p.y)
}
```

## 8. Types Are Values

A function can return a type, and bindings, parameters, and return types can all use it:

```abyss
precision :: fn(wide bool) type {
    if wide { f64 } else { f32 }
}

main :: fn() {
    coordinate: precision(true) = 142.857
    print(coordinate)
    print(@type_name(precision(false)))
}
```

## 9. Modules

`@import` is an expression that produces a namespace value. Bind it once and reach everything through it:

```abyss
std :: @import("std")
Arena :: @import("std/allocator").Arena

main :: fn() {
    print(std.ascii.is_digit('7'))
    print(@type_name(Arena))
}
```

Paths without a leading `./` or `../` resolve against the working directory and configured import directories. An extensionless path tries `name.a` first, then `name/name.a`. See [Modules & Imports](../03-the-guide/08-modules-and-imports.md) for cycles, caching, and re-exports.

## 10. Running It

```sh
# run instantly on the bytecode VM
abyssc r tour.a

# emit C99 and build a native binary
abyssc b tour.a tour.c
gcc -std=gnu99 -D_POSIX_C_SOURCE=200809L -O3 tour.c -o tour
./tour
```

That is enough to read most Abyss code. The rest of the book fills in each area in depth.

---

[Previous: Architecture](../01-overview/architecture.md) | [Next: Tooling & Workflow →](workflow.md)

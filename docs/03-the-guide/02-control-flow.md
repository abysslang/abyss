# Control Flow: Branching, Loops, and Matching

Abyss has three control-flow forms: `if`, `while`, and `for`, plus `match` for exhaustive decomposition of enums and tagged unions. All of them are expressions, so they can produce values where a value is expected.

```abyss
Color :: enum { red, green, blue }

main :: fn() {
    i := 0
    while i < 3 {
        i = i + 1
        print(if i == 2 { "two" } else { "other" })
    }

    for n in Range.new(0, 3) {
        print(n)
    }

    match Color.green {
        red { print("red") }
        green, blue { print("cool") }
    }
}
```

---

## 1. `if` and `else`

Conditions do not need parentheses, and the body must be a block:

```abyss
main :: fn() {
    temperature := 85
    if temperature > 100 {
        print("boiling")
    } else if temperature > 60 {
        print("warm")
    } else {
        print("cool")
    }
}
```

### Using `if` as an Expression

When an `if` produces a value, both branches must have compatible types:

```abyss
main :: fn() {
    threshold := 10
    priority := if threshold > 5 { "high" } else { "normal" }
    print(priority)
}
```

An `if` without an `else` produces no value and can only be used as a statement.

### Block Conditions

A condition may be a block. Its last expression is the boolean test, and the block runs before the branch:

```abyss
main :: fn() {
    probe := 42
    threshold := 10
    if {
        reading := probe
        reading > threshold
    } {
        print("over threshold")
    }
}
```

## 2. `while` Loops

```abyss
main :: fn() {
    i := 0
    while i < 5 {
        print(i)
        i = i + 1
    }
}
```

The condition can be a block, which lets a loop compute its test before deciding whether to continue:

```abyss
main :: fn() {
    checked := 0
    limit := 3

    while {
        checked = checked + 1
        checked < limit
    } {
        print(checked)
    }
}
```

### `break` and `cont`

`break` exits the nearest loop, and `cont` starts its next iteration. Both work inside a block condition as well, where they apply to the loop being tested:

```abyss
main :: fn() {
    n := 0
    while n < 10 {
        n = n + 1
        if n % 2 == 0 { cont }
        if n > 7 { break }
        print(n)
    }
}
```

There is no `continue` keyword. Use `cont`.

## 3. `for` Loops

`for` iterates any value that provides a `next()` method or an `iter()` method. Arrays, slices, `Range`, and the standard collections all work:

```abyss
main :: fn() {
    values: [3]i32 = .[10, 20, 30]
    for value in values {
        print(value)
    }

    for n in Range.new(0, 4) {
        print(n)
    }

    names := Vec(Str).new()
    names.push("alice")
    names.push("bob")
    for name in names {
        print(name)
    }
    names.destroy()
}
```

### Iteration Protocol

A type is iterable directly when it has a `next()` method returning `Maybe(T)`:

```abyss
Countdown :: struct {
    current i32

    next :: fn(self &Self) Maybe(i32) {
        if self.current == 0 { ret Maybe(i32).none() }
        value := self.current
        self.current = self.current - 1
        Maybe(i32).some(value)
    }
}

main :: fn() {
    counter: Countdown = .{ current: 3 }
    for value in counter {
        print(value)
    }
}
```

Alternatively, a type may expose `iter()` returning an iterator. Arrays provide `iter()` and `iter_ref()` automatically:

```abyss
main :: fn() {
    values: [3]i32 = .[7, 8, 9]

    for value in values.iter() {
        print(value)
    }

    for pointer in values.iter_ref() {
        *pointer = *pointer * 2
    }
}
```

Iterating `&value` uses `iter_ref()` and yields pointers, which is the compact form:

```abyss
main :: fn() {
    values: [3]i32 = .[7, 8, 9]
    for pointer in &values {
        *pointer = *pointer + 1
    }
    print(values[0] + values[1] + values[2])
}
```

### Several Iterators at Once

One `for` can drive several iterators. Each loop variable pairs with one source, and the counts must match:

```abyss
main :: fn() {
    for a, b in Range.new(0, 3), Range.new(10, 13) {
        print(a + b)
    }
}
```

The loop ends when any iterator is exhausted. It does not rely on `len()`; the iterator protocol decides when iteration is complete.

## 4. `match`

`match` is exhaustive pattern matching over **enums and tagged unions**. It is not a C-style switch: integers, floats, and strings cannot be matched.

```abyss
Color :: enum { red, green, blue }

describe :: fn(color Color) Str {
    match color {
        red { "red" }
        green, blue { "cool" }
    }
}

main :: fn() {
    print(describe(Color.red))
    print(describe(Color.blue))
}
```

Patterns are variants and may be qualified:

```abyss
Color :: enum { red, green, blue }

label :: fn(color Color) Str {
    match color {
        Color.red { "stop" }
        Color.green, Color.blue { "go" }
    }
}

main :: fn() {
    print(label(Color.green))
}
```

Every variant must be covered, or the match needs an `else` arm:

```abyss
Color :: enum { red, green, blue }

label :: fn(color Color) Str {
    match color {
        red { "stop" }
        else { "go" }
    }
}

main :: fn() {
    print(label(Color.blue))
}
```

### Matching Tagged Unions

Union patterns are types. The arm body runs when the value currently holds that member:

```abyss
area :: fn(shape i32 | f64) f64 {
    match shape {
        i32 { 0.0 }
        f64 { 1.0 }
    }
}

main :: fn() {
    print(area(7))
    print(area(1.5))
}
```

Use `match name in value` to bind the payload to `name`. The pattern determines the binding's type, so no cast is needed:

```abyss
describe :: fn(value i32 | bool) Str {
    match payload in value {
        i32 { "an integer" }
        bool { "a boolean" }
    }
}

main :: fn() {
    print(describe(7))
    print(describe(true))
}
```

A binding arm may name only one pattern, because two patterns would have different payload types. Use `else` for a catch-all:

```abyss
kind :: fn(value i32 | bool | Str) Str {
    match payload in value {
        i32 { "number" }
        else { "text or flag" }
    }
}

main :: fn() {
    print(kind(1))
    print(kind("s"))
}
```

### Match Result Types

All arms must produce compatible values when the match is used as an expression. An `else` arm is optional once the patterns cover every variant; omitting a variant without `else` is a compile error:

```
[type error] non-exhaustive match; add the missing cases or else
```

## 5. Early Return

`ret` leaves the enclosing function immediately. With a value it returns that value; bare `ret` returns nothing:

```abyss
find_first_negative :: fn(values []i32) Maybe(i32) {
    for value in values {
        if value < 0 { ret Maybe(i32).some(value) }
    }
    Maybe(i32).none()
}

dump :: fn(label Str) {
    if label.len == 0 { ret }
    print(label)
}

main :: fn() {
    values: [3]i32 = .[4, -2, 9]
    print(find_first_negative(Slice(i32).new(&values[0], 3)).unwrap())
    dump("")
    dump("done")
}
```

## 6. Source Locations and Fatal Errors

`@source_location()` is a compile-time `SourceLocation` with the current file, line, and one-based byte column:

```abyss
main :: fn() {
    location := @source_location()
    print(location.file.ends_with(".a"))
    print(location.line)
    print(location.column)
}
```

`std/sys` exports a `fall` splice and a `fall_at` function. Splice `#fall` to abort at the call site:

```abyss
fall :: @import("std/sys").fall

check_depth :: fn(depth i32) {
    if depth < 0 { #fall }
}

main :: fn() {
    check_depth(10)
    print("inside range")
}
```

`#fall` writes to standard error and exits with status 1. `fall_at(location)` performs the same abort when you already hold a `SourceLocation`.

## Idiomatic Summary

| Control Flow | Idiomatic Abyss | Avoid |
| :--- | :--- | :--- |
| **Choice as value** | `val := if cond { a } else { b }` | Predeclaring and assigning in branches |
| **Loop continuation** | `cont` | `continue` |
| **Iteration** | `for item in collection` | Manual index loops |
| **Matching** | `match` on enums and unions | `match` on integers or strings |
| **Catch-all arm** | `else { ... }` | `_` or `default` |

---

[Previous: Basics](01-basics.md) | [Next: Functions & Methods →](03-functions-and-methods.md)

# Pointers, Arrays & Memory

Abyss gives you raw addresses, fixed arrays, slices, and a scoped arena allocator. There is no garbage collector and no hidden allocation: every byte is either on the stack, in an array, in an arena, or freed by you.

```abyss
Arena :: @import("std/allocator").Arena

Node :: struct {
    value i32
    next  &Node
}

main :: fn() {
    arena := Arena.new(4096)

    first := arena.alloc(@sizeof(Node)) as &Node
    first.value = 100

    second := arena.alloc(@sizeof(Node)) as &Node
    second.value = 200
    first.next = second

    print(first.next.value)
    arena.destroy()
}
```

---

## 1. Pointers

A pointer is written `&T` and holds a machine address. Take an address with `&` and read through it with `*`:

```abyss
main :: fn() {
    x := 42
    ptr: &i32 = &x
    print(*ptr)
    *ptr = 7
    print(x)
}
```

Abyss has no `null` keyword. A null pointer is the integer `0` cast to a pointer type, `0 as &T`:

```abyss
main :: fn() {
    empty: &i32 = 0 as &i32
    print(empty == (0 as &i32))
    print(empty != (0 as &i32))
}
```

Pointers support arithmetic and indexing over contiguous memory:

```abyss
main :: fn() {
    data: [3]i32 = .[10, 20, 30]
    head := &data[0]
    print(*(head + 1))   -- 20
    print(head[2])       -- 30
}
```

### Automatic Dereference

Field access through a pointer needs no `*` and no parenthesized dereference. The compiler follows as many pointer levels as the type requires:

```abyss
User :: struct {
    id   u64
    name Str
}

rename :: fn(u &User, name Str) {
    u.name = name
    print(u.id)
}
```

Write `node.next.value`, never `(*(*node).next).value`. Taking the address of a field or a nested value is just as direct:

```abyss
User :: struct {
    id   u64
    name Str
}

main :: fn() {
    user: User = .{ id: 1, name: "Ada" }
    id_ptr := &user.id
    *id_ptr = 2
    print(user.id)
}
```

## 2. Value vs. Reference Parameters

Parameters are passed by value; a struct argument is copied onto the call path. Passing a pointer avoids the copy and lets the callee mutate the caller's data:

```abyss
Point :: struct {
    x i32
    y i32

    translate :: fn(self &Self, dx i32, dy i32) {
        self.x = self.x + dx
        self.y = self.y + dy
    }
}

main :: fn() {
    p: Point = .{ x: 0, y: 0 }
    p.translate(3, 4)
    print(p.x)
    print(p.y)
}
```

Use a value parameter for small structs and pure computations; use `&T` when a struct is large or when the function mutates it.

## 3. Arrays

A fixed array is `[N]T`, where `N` is a compile-time constant. Literals use `.[ ... ]`:

```abyss
main :: fn() {
    primes: [5]i32 = .[2, 3, 5, 7, 11]
    print(primes.len)
    print(primes[0])
    primes[4] = 13

    grid: [2][2]i32 = .[ .[1, 2], .[3, 4] ]
    print(grid[1][0])
}
```

The length can come from a constant or from a `u64` parameter, which the compiler evaluates at compile time. A literal must match the length exactly, so fill a parameter-length array element by element:

```abyss
N :: 2 + 3

make :: fn(n u64) [n]i32 {
    res: [n]i32
    i: u64 = 0
    while i < n {
        res[i] = (i as i32) * 10
        i = i + 1
    }
    res
}

main :: fn() {
    fixed: [N]i32 = .[1, 2, 3, 4, 5]
    print(fixed[4])

    built := make(3)
    print(built[2])
}
```

Arrays expose `.len`, `.iter()`, and `.iter_ref()`. A bare `for` over an array yields values; iterate `&array` or call `.iter_ref()` to get pointers and mutate in place:

```abyss
main :: fn() {
    values: [3]i32 = .[1, 2, 3]

    for v in values {
        print(v)
    }

    for ref in &values {
        *ref = *ref * 10
    }
    print(values[2])
}
```

## 4. Slices

A slice `[]T` is a pointer-plus-length view: a non-owning window over memory that someone else owns. The builtin `Slice(T)` is the same type:

```abyss
main :: fn() {
    data: [6]i32 = .[0, 1, 2, 3, 4, 5]
    window: []i32 = Slice(i32).new(&data[1], 4)

    print(window.len)
    print(window.get(0))
    window.sub(1, 2)[0] = 99
    print(data[2])
}
```

- `Slice(T).new(ptr, len)` makes a view.
- `.get(idx)` reads an element; indexing `window[idx]` is equivalent.
- `.sub(start, len)` returns a narrower view over the same memory.
- `.iter()`, `.iter_ref()`, `.contains(value)`, `.position(value)`, `.equals(other)`, `.dedup()`, and `.chunks(width)` are available.

Writing through a slice writes to the underlying array. A slice never copies and never frees.

## 5. Arena Allocation

The `Arena` in `std/allocator` hands out memory by bumping a pointer inside a chain of chunks. Allocation and deallocation are both near-constant time, and everything you allocate from one arena lives next to everything else, which keeps the cache warm.

```abyss
Arena :: @import("std/allocator").Arena

sum_ints :: fn(arena &Arena, count u64) i64 {
    buffer := arena.alloc(count * @sizeof(i64)) as &i64
    i: u64 = 0
    while i < count {
        buffer[i] = (i as i64) + 1
        i = i + 1
    }
    total: i64 = 0
    i = 0
    while i < count {
        total = total + buffer[i]
        i = i + 1
    }
    total
}

main :: fn() {
    arena := Arena.new(65536)
    print(sum_ints(&arena, 100))
    arena.destroy()
}
```

- `Arena.new(chunk_size)` starts an arena; chunks grow automatically when a bump does not fit.
- `arena.alloc(bytes)` returns `&u8` with 8-byte alignment. Cast it to `&T` for typed storage.
- `arena.realloc(old_ptr, old_size, new_size)` grows the most recent allocation in place when possible.
- `arena.reset()` rewinds every chunk to zero for reuse, without returning memory to the OS.
- `arena.destroy()` frees every chunk in one pass.

Pass `&arena` to functions that build dynamic values. A single `destroy` at the end of a phase reclaims all of it, no matter how many allocations happened.

## 6. Heap Collections

`Vec(T)`, `HashMap(K, V)`, and `HashSet(T)` allocate their backing storage from the system heap and own it. Free that storage with `.destroy()` when the value's lifetime ends:

```abyss
main :: fn() {
    numbers := Vec(i32).new()
    numbers.push(10)
    numbers.push(20)
    print(numbers.len)
    print(numbers.get(1))
    numbers.destroy()
}
```

The collections are covered in full in the [Collections reference](../04-reference/02-collections.md).

## Idiomatic Summary

| Operation | Idiomatic Abyss | Avoid |
| :--- | :--- | :--- |
| **Field access** | `ptr.field` | `(*ptr).field` or `ptr->field` |
| **Deep access** | `a.b.c.d` | Nested `(*(*a).b).c` |
| **Null test** | `ptr == (0 as &T)` | Sentinel integers |
| **Phase memory** | One `arena.destroy()` | Scattered `free()` calls |
| **Owned collections** | `vec.destroy()` | Leaking backing storage |

---

[Previous: Structs & Data Types](04-structs-and-types.md) | [Next: Generics & Types →](06-generics-and-types.md)

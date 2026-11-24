# Allocators & Memory

Abyss manages memory in two layers: the scoped `Arena` for phase-oriented allocation, and the raw `std/mem` primitives it is built on. Both are explicit, so you always know when memory is reserved and when it is released.

```abyss
Arena :: @import("std/allocator").Arena

Point :: struct {
    x i32
    y i32
}

main :: fn() {
    arena := Arena.new(32768)

    point := arena.alloc(@sizeof(Point)) as &Point
    point.x = 100
    point.y = 200
    print(point.x + point.y)

    arena.destroy()
}
```

---

## 1. `Arena`

`Arena` hands out memory by advancing an offset inside a chain of chunks. A bump allocation is a pointer add; freeing the whole arena walks the chunk list once. Everything allocated from one arena is contiguous, which keeps caches warm.

```abyss
Arena :: @import("std/allocator").Arena

main :: fn() {
    arena := Arena.new(4096)
    bytes := arena.alloc(64)
    bytes[0] = 7
    print(bytes[0])
    arena.destroy()
}
```

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `new` | `fn(default_chunk_size u64) Arena` | Start with one chunk of the given size. |
| `alloc` | `fn(self &Self, s u64) &u8` | Bump-allocate `s` bytes, 8-byte aligned. |
| `realloc` | `fn(self &Self, old_ptr &u8, old_size u64, new_size u64) &u8` | Grow the most recent allocation in place when possible, otherwise allocate and copy. |
| `reset` | `fn(self &Self)` | Rewind every chunk to zero for reuse; keeps the memory. |
| `destroy` | `fn(self &Self)` | Free every chunk back to the system. |

Fields are `current &ArenaChunk` and `default_chunk_size u64`. A chunk carries `next_chunk`, `memory`, `offset`, and `cap`; `ArenaChunk.size()` is `32` bytes.

`alloc` returns uninitialized bytes. Cast to `&T` for typed storage, and initialize before reading — the arena does not zero memory for you:

```abyss
Arena :: @import("std/allocator").Arena

main :: fn() {
    arena := Arena.new(4096)
    count := 100
    buffer := arena.alloc(count * @sizeof(i64)) as &i64

    i: u64 = 0
    while i < count {
        buffer[i] = i as i64
        i = i + 1
    }
    print(buffer[99])
    arena.destroy()
}
```

There is no `alloc_type` or `alloc_slice`; multiply the element size and cast. `realloc` knows how to extend the last allocation in place, which is the pattern behind `Vec` growth.

### Scoped Lifecycle

```abyss
Arena :: @import("std/allocator").Arena

handle_request :: fn() {
    scratch := Arena.new(65536)
    -- allocate strings, buffers, and parsed values
    scratch.destroy()
}

main :: fn() {
    handle_request()
}
```

One `destroy` releases everything the request allocated, regardless of how many allocations were made. For a long-lived loop, `reset()` reclaims the space each iteration without returning it to the OS:

```abyss
Arena :: @import("std/allocator").Arena

main :: fn() {
    frame_arena := Arena.new(1 << 20)
    frame := 0
    while frame < 100 {
        scratch := frame_arena.alloc(4096)
        scratch[0] = frame as u8
        frame_arena.reset()
        frame = frame + 1
    }
    frame_arena.destroy()
}
```

## 2. Raw Memory (`std/mem`)

`std/mem` is the thin layer over the platform heap. The collections and `Arena` use it internally; call it directly only when you need a specific allocation lifetime.

```abyss
mem :: @import("std/mem")

main :: fn() {
    buffer := mem.malloc(1024)
    mem.mem_set(buffer, 0, 1024)
    buffer[0] = 42
    print(buffer[0])
    mem.free(buffer)
}
```

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `malloc` | `extern fn(size u64) &u8` | Reserve uninitialized bytes. |
| `free` | `extern fn(ptr &u8)` | Release a previous allocation. |
| `realloc` | `extern fn(ptr &u8, size u64) &u8` | Resize an existing allocation. |
| `mem_copy` | `fn(dest &u8, src &u8, count u64)` | Byte copy. |
| `mem_set` | `fn(dest &u8, val u8, count u64)` | Fill with a byte. |

`free` and `realloc` come from the C runtime; `mem_copy` and `mem_set` are implemented in Abyss. There is no `mem_zero` or `mem_eq`: use `mem_set(ptr, 0, count)` to zero memory and compare bytes in a loop or with `Str.eq`.

## 3. Choosing a Strategy

| Use case | Choice | Why |
| :--- | :--- | :--- |
| Phase, request, or pass | `Arena` | Near-constant allocation, single-point cleanup. |
| Per-frame work | `Arena` with `reset()` | No new allocations after warmup. |
| A growing list or map | `Vec` / `HashMap` / `HashSet` | They reuse `realloc` and own their storage. |
| One long-lived object | `malloc` / a dedicated `Arena` | Match the object's lifetime. |
| Text building | `String` over an arena | Reuses one arena for many fragments. |

## 4. Ownership Discipline

Abyss has no garbage collector and no hidden ownership. Adopt these rules and leaks disappear:

- Every `Arena.new`, `String`, `Vec`, `HashMap`, and `HashSet` has an owner, and the owner calls `destroy`.
- Slices and `Worklist` are views; they are never freed.
- Free in reverse order of creation when lifetimes are nested.
- Prefer one arena per phase over many small allocations, then destroy it once.
- Keep heap allocations behind a struct that frees them in its own `destroy`.

```abyss
Arena :: @import("std/allocator").Arena

Report :: struct {
    rows Vec(Str)

    destroy :: fn(self &Self) {
        self.rows.destroy()
    }
}

main :: fn() {
    arena := Arena.new(8192)
    report: Report = .{ rows: Vec(Str).new() }
    report.rows.push("first")
    report.rows.push("second")
    print(report.rows.len)
    report.destroy()
    arena.destroy()
}
```

---

[Previous: Filesystem & Paths](04-fs-and-path.md) | [Next: System & Threading →](06-sys-and-threading.md)

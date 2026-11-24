# Collections

The collections in `std/collections` are flat and cache-friendly: contiguous storage, no node chaining, and explicit ownership. `Vec`, `HashMap`, `HashSet`, and `Worklist` are injected by `std/prelude` and need no import.

```abyss
main :: fn() {
    scores := Vec(i32).new()
    scores.push(95)
    scores.push(100)
    print(scores.get(0))

    lookup := HashMap(i32, i32).new()
    lookup.insert(7, 8080)
    print(*(lookup.get(7)))

    scores.destroy()
    lookup.destroy()
}
```

---

## 1. `Vec(T)`

`Vec(T)` is a dynamically growing contiguous array. It allocates its backing storage from the system heap and doubles capacity as needed.

```abyss
main :: fn() {
    numbers := Vec(i32).new()
    numbers.push(10)
    numbers.push(20)
    numbers.set(1, 25)
    print(numbers.len)
    print(numbers.last())
    numbers.destroy()
}
```

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `new` | `fn() Self` | Capacity 4. |
| `with_cap` | `fn(initial_cap u64) Self` | Pre-reserve (minimum 4). |
| `destroy` | `fn(self &Self)` | Free backing storage. |
| `push` | `fn(self &Self, val T)` | Append. |
| `pop` | `fn(self &Self) T` | Remove and return the last element. The vector must be non-empty. |
| `get` | `fn(self &Self, idx u64) T` | Read by index. |
| `set` | `fn(self &Self, idx u64, val T)` | Write by index. |
| `last` | `fn(self &Self) T` | The final element. |
| `is_empty` | `fn(self &Self) bool` | Length is zero. |
| `contains` | `fn(self &Self, val T) bool` | Linear membership. |
| `dedup` | `fn(self &Self)` | Remove repeated neighbors in place. |
| `extend` | `fn(self &Self, src &T, count u64)` | Bulk-append `count` elements from `src`. |
| `clear` | `fn(self &Self)` | Set length to zero, keep capacity. |
| `mark` / `reset` | `fn(self &Self) u64` / `fn(self &Self, mark u64)` | Save and restore length for scoped growth. |
| `reserve` | `fn(self &Self, additional u64)` | Ensure room for `additional` more. |
| `swap_remove` | `fn(self &Self, idx u64) T` | Remove `idx` by swapping in the last element. |
| `ptr_at` | `fn(self &Self, offset u64) &T` | Pointer to an element. |
| `as_slice` | `fn(self &Self) Slice(T)` | Borrow as a slice. |
| `iter` / `iter_ref` | `fn(self &Self) Iterator(T)` / `RefIterator(T)` | Value and pointer iteration. |
| `collect` | `fn(iter Iterator(T)) Self` | Drain an iterator into a new vector. |

Fields are `ptr &T`, `len u64`, `cap u64`. Iterate values with `for item in v`, or pointers with `for ref in &v`.

## 2. `HashMap(K, V)`

`HashMap(K, V)` is an open-addressing, linear-probing table with parallel key, value, and occupancy arrays. Keys are hashed with FNV-1a over `@sizeof(K)` raw bytes and compared byte-for-byte.

```abyss
main :: fn() {
    ages := HashMap(i32, u32).new()
    ages.insert(1, 36)
    ages.insert(2, 41)

    if ages.contains_key(1) {
        print(*(ages.get(1)))
    }

    ages.remove(2)
    print(ages.len)
    ages.destroy()
}
```

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `new` | `fn() Self` | Capacity 16. |
| `with_cap` | `fn(initial_cap u64) Self` | Minimum 16. |
| `destroy` | `fn(self &Self)` | Free all three arrays. |
| `insert` | `fn(self &Self, key K, val V) bool` | `true` if the key was new, `false` if it updated. |
| `get` | `fn(self &Self, key K) &V` | Pointer to the value, or a null pointer if absent. |
| `contains_key` | `fn(self &Self, key K) bool` | Membership. |
| `remove` | `fn(self &Self, key K) bool` | `true` if the key was present. |
| `is_empty` | `fn(self &Self) bool` | No entries. |
| `clear` | `fn(self &Self)` | Drop all entries, keep capacity. |

`get` returns `&V` so you can read or mutate the stored value in place; a missing key yields `0 as &V`. Check with `contains_key`, or compare the pointer against `0 as &V` before dereferencing. Fields are `keys`, `values`, `occupied`, `len`, and `cap`.

Use scalar key types. Each key is written into the key array with a whole-value assignment, which currently round-trips only for register-sized scalars, so `i32`, `u32`, `u64`, `f64`, and similar keys work while struct and pointer keys — including `Str` — do not. Map an interned id for string keys:

```abyss
Interner :: @import("std/interner").Interner

main :: fn() {
    names := Interner.new()
    ports := HashMap(u32, i32).new()
    ports.insert(names.intern("http"), 80)
    ports.insert(names.intern("https"), 443)
    print(*(ports.get(names.intern("https"))))
    ports.destroy()
    names.destroy()
}
```

## 3. `HashSet(T)`

`HashSet(T)` stores unique elements with the same open-addressing design and a single key array.

```abyss
main :: fn() {
    seen := HashSet(i32).new()
    print(seen.insert(42))
    print(seen.insert(42))
    print(seen.contains(42))
    seen.remove(42)
    print(seen.len)
    seen.destroy()
}
```

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `new` / `with_cap` | `fn() Self` / `fn(initial_cap u64) Self` | Capacity 16 minimum. |
| `insert` | `fn(self &Self, val T) bool` | `true` if newly added. |
| `contains` | `fn(self &Self, val T) bool` | Membership. |
| `remove` | `fn(self &Self, val T) bool` | `true` if present. |
| `is_empty` / `clear` | — | Length checks and reset. |
| `destroy` | `fn(self &Self)` | Free backing storage. |

Fields are `keys &T`, `occupied &bool`, `len u64`, `cap u64`.

## 4. `Worklist(T)`

`Worklist(T)` is a cursor over a `Vec(T)` for graph traversals and work queues. It does not own the vector; it holds a pointer and advances an index:

```abyss
main :: fn() {
    queue := Vec(u32).new()
    queue.push(1)
    queue.push(2)
    queue.push(3)

    for item in Worklist(u32).new(&queue) {
        print(item)
    }

    queue.destroy()
}
```

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `new` | `fn(vec &Vec(T)) Self` | Borrow a vector. |
| `next` | `fn(self &Self) Maybe(T)` | Next item, or `none` at the end. |
| `has_next` | `fn(self &Self) bool` | Anything left. |
| `remaining` | `fn(self &Self) u64` | Count left. |

Because `next` satisfies the iterator protocol, `for item in Worklist(T).new(&v)` works directly.

## 5. `Interner`

`Interner` maps a `Str` to a stable `u32` id: identical strings intern to the same id, and ids index back to their strings in insertion order.

```abyss
Interner :: @import("std/interner").Interner

main :: fn() {
    table := Interner.new()
    a := table.intern("identifier")
    b := table.intern("identifier")
    print(a == b)
    print(table.get(a))
    print(table.len())
    table.destroy()
}
```

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `new` / `with_cap` | `fn() Self` / `fn(initial_cap u64) Self` | Minimum 64 buckets. |
| `intern` | `fn(self &Self, s Str) u32` | Deduplicating insert; returns the id. |
| `get` | `fn(self &Self, id u32) Str` | The string for an id. |
| `len` | `fn(self &Self) u64` | Number of distinct strings. |
| `destroy` | `fn(self &Self)` | Free the table and its strings. |

## 6. `sort` and `hash`

`std/sort` provides an in-place heapsort over a slice:

```abyss
sort :: @import("std/sort").sort

main :: fn() {
    values := Vec(i32).new()
    values.push(3)
    values.push(1)
    values.push(2)
    sort(values.as_slice())
    print(values.get(0))
    values.destroy()
}
```

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `sort` | `fn(T type, values Slice(T))` | Sorts using `<` on the elements. |

`std/hash` exposes the mixing primitives used by the collections:

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `hash_combine` | `fn(seed u32, value u32) u32` | Fold one 32-bit value into a seed. |
| `hash_words` | `fn(values Slice(u32), seed u32) u32` | Fold a slice of words. |

## 7. Ownership and Cleanup

Every collection allocates from the system heap and owns its storage. Free it with `.destroy()` when its lifetime ends; nothing frees it for you:

```abyss
process :: fn() {
    scratch := Vec(Str).new()
    scratch.push("a")
    scratch.push("b")
    scratch.destroy()
}
```

Slices (`Slice(T)`, `[]T`) and `Worklist(T)` are views: they never allocate and never need cleanup.

---

[Previous: Core Primitives](01-core.md) | [Next: I/O & Formatting →](03-io-and-fmt.md)

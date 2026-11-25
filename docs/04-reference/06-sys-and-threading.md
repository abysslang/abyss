# System & Threading

`std/sys` exposes host process and stream primitives, and `std/thread` layers native 1:1 threads on top. There is no scheduler, green-thread runtime, or hidden thread pool: a spawn maps directly onto an OS thread through the target's threading API.

Every example in this chapter targets a **native build**. The bytecode VM has no thread, mutex, or host-stream runtime, so emit C with `abyssc b` and link the result with `-pthread`; `abyssc r` cannot run them.

```abyss
thread :: @import("std/thread")

Bounds :: struct {
    low  i32
    high i32
}

width :: fn(bounds Bounds) i32 {
    bounds.high - bounds.low
}

main :: fn() {
    bounds: Bounds = .{ low: 2, high: 44 }
    worker := thread.spawn_with(width, bounds).unwrap()
    print(worker.join().unwrap())
}
```

---

## 1. Process and Streams (`std/sys`)

| Symbol | Notes |
| :--- | :--- |
| `STDIN`, `STDOUT`, `STDERR` | `0`, `1`, `2`. |
| `write_console(text Str)` | Write to standard output. |
| `write_stderr(text Str)` | Write to standard error. |
| `write_all(handle i64, buf &u8, count u64) u64` | Write all bytes, looping on partial writes. |
| `exit_process(code i32)` | Terminate with a status. |
| `last_error()` | The platform's last error code. |
| `environment(name &u8) &u8` | Environment variable lookup. |
| `host_call(...)` | Opaque host dispatch used by bindings. |
| `format_float(buf &u8, cap u64, value f64) u64` | Float text used by `Convert`. |
| `open_handle`, `read_handle`, `write_handle`, `seek_handle`, `close_handle` | Raw handle I/O. |
| `make_directory(path &u8) bool`, `Directory` | Directory creation and listing. |
| `OpenMode` | Parsed file mode (`read`, `write`, `create`, `truncate`, `append`). |

### `fall` and `fall_at`

`sys.fall` is a splice that reports the current `@source_location()` to standard error and exits with status `1`; `fall_at(location)` does the same for a location you hold. Use them for invariants that cannot be recovered from:

```abyss
sys :: @import("std/sys")

expect :: fn(ok bool) {
    if not ok {
        sys.fall_at(@source_location())
    }
}

main :: fn() {
    expect(2 + 2 == 4)
    print("invariant held")
}
```

Write `#sys.fall` on its own line to report the current location and exit `1` from anywhere in a block.

## 2. Native Threads

Import `std/thread` directly, or reach it through `@import("std").thread`.

### Capabilities

| Symbol | Notes |
| :--- | :--- |
| `supported` | Compile-time `bool`. `true` on native Linux, macOS, and Windows. |
| `Unit` | `struct {}`, the empty result of a task. |
| `yield()` | Offer the current thread's turn to the scheduler. |
| `sleep(milliseconds u64) Result(Unit)` | Pause without busy waiting. |

```abyss
thread :: @import("std/thread")

main :: fn() {
    thread.sleep(250).unwrap()
    thread.yield()
}
```

### Spawning

Worker callbacks are ordinary typed functions, and the capture is passed as a value so the compiler can check its type.

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `spawn` | `fn(work fn() R) Result(Thread(R))` | No capture. |
| `spawn_with` | `fn(work fn(C) R, capture C) Result(Thread(R))` | Copy a pointer-free capture into the job. |
| `spawn_shared` | `fn(work fn(C) R, capture C) Result(Thread(R))` | Allow borrowed state; the caller keeps it alive. |
| `spawn_task` | `fn(work fn(C), capture C) Result(Thread(Unit))` | Fire a function with no result. |
| `spawn_shared_task` | `fn(work fn(C), capture C) Result(Thread(Unit))` | Task with borrowed state. |
| `spawn_detached` | `fn(work fn(C), capture C) Result(Unit)` | Start and forget; the worker frees its own job. |

`spawn_with` and `spawn_detached` require a **pointer-free** capture and result: scalars, arrays, and value structs. Pointers, `Str`, slices, native header types, and anything containing them are rejected at compile time with `captures must be pointer-free; use spawn_shared for borrowed state`. `spawn_shared` and `spawn_shared_task` waive that check so you can pass a `&T`, with the responsibility of keeping the memory alive and synchronized falling on you.

```abyss
thread :: @import("std/thread")

Capture :: struct {
    nums [3]i32
    pair (i32, i32)
}

sum :: fn(capture Capture) i32 {
    capture.nums[0] + capture.nums[2] + capture.pair.0
}

main :: fn() {
    capture: Capture = .{ nums: .[10, 90, 12], pair: .(20, 0) }
    worker := thread.spawn_with(sum, capture).unwrap()
    print(worker.join().unwrap())
}
```

### Results and Joining

`Result(T)` carries either a value or an `Error`:

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `ok(value T)` / `err(error Error)` | constructors | Build a result. |
| `is_success()` / `is_error()` | `bool` | Which side is present. |
| `unwrap()` | `T` | The value, or fail with a thread error. |
| `unwrap_error()` | `Error` | The error, or fail if there was none. |

`Error` has `kind ErrorKind` and `code i32`; kinds are `allocation`, `system`, and `closed`.

A `Thread(R)` is a single-owner handle. One job allocation holds the callback, the capture, and the result:

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `join` | `fn(self &Self) Result(R)` | Wait, read the result, and free the job. |

```abyss
thread :: @import("std/thread")

answer :: fn() i32 { 42 }

main :: fn() {
    worker := thread.spawn(answer).unwrap()
    print(worker.join().unwrap())
    print(worker.join().unwrap_error().kind == thread.ErrorKind.closed)
}
```

Joining twice is an error, not undefined behavior: the second `join` returns `ErrorKind.closed`. A failed OS join leaves the handle available to retry.

### Detached Work

```abyss
thread :: @import("std/thread")

Lock :: thread.Mutex(u64)

completions: Lock

finish :: fn(amount u64) {
    count := completions.lock()
    *count = *count + amount
    completions.unlock()
}

main :: fn() {
    completions = Lock.new(0 as u64).unwrap()
    thread.spawn_detached(finish, 1 as u64).unwrap()
    while true {
        count := *completions.lock()
        completions.unlock()
        if count == 1 { break }
        thread.yield()
    }
    completions.destroy().unwrap()
}
```

## 3. `Mutex(T)`

`Mutex(T)` protects a value with a native lock. It owns a separate native lock, so keep it at a stable address and do not copy it once shared.

| Member | Signature | Notes |
| :--- | :--- | :--- |
| `new` | `fn(value T) Result(Self)` | Create the lock and store the value. |
| `lock` | `fn(self &Self) &T` | Block until locked; returns a mutable pointer. |
| `try_lock` | `fn(self &Self) Maybe(&T)` | Non-blocking attempt. |
| `unlock` | `fn(self &Self)` | Release. |
| `with_lock` | `fn(self &Self, work fn(&T) R) R` | Lock, call, unlock; `R` must be pointer-free. |
| `destroy` | `fn(self &Self) Result(Unit)` | Release the native lock. |

```abyss
thread :: @import("std/thread")

Lock :: thread.Mutex(u64)

increment :: fn(lock &Lock) u64 {
    value := lock.lock()
    *value = *value + 1
    lock.unlock()
    *value
}

read_and_clear :: fn(value &u64) u64 {
    count := *value
    *value = 0
    count
}

main :: fn() {
    lock := Lock.new(0 as u64).unwrap()

    worker := thread.spawn_shared(increment, &lock).unwrap()
    print(worker.join().unwrap())
    print(lock.with_lock(read_and_clear))

    lock.destroy().unwrap()
}
```

`Mutex.new` and `destroy` return `Result`, so unwrap them. `try_lock` returns `Maybe(&T)`; only unlock when it succeeds. `with_lock` releases the mutex even though the callback returns a value.

## 4. Platform Support and Linking

`thread.supported` is a compile-time constant. Threads run on native Linux, macOS, and Windows builds. The VM, WASI, and freestanding targets do not run them, so guard thread-using code with `if thread.supported` or keep it in a native-only target.

When linking generated C yourself on POSIX, pass `-pthread`:

```sh
abyssc b main.a out.c
gcc -pthread -std=gnu99 -O3 out.c -o app
```

With `sonar build`, `-pthread` is added automatically on supported platforms.

The runtime lives in `std/sys`: thread creation, locking, and `sleep` call the platform through `extern` declarations, and using `sleep` alone does not pull in thread creation or mutex bindings.

---

[Previous: Allocators & Memory](05-allocators-and-mem.md) | [Next: Language Intrinsics →](07-language-intrinsics.md)

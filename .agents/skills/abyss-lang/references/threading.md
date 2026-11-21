# Native Threads

Import `std/thread` directly or use `@import("std").thread`. Worker callbacks are ordinary typed functions. Pass their environment as a value so the compiler can check its type.

```abyss
thread :: @import("std/thread")

Bounds :: struct {
    low i32
    high i32
}

width :: fn(bounds Bounds) i32 { bounds.high - bounds.low }

main :: fn() {
    bounds: Bounds = .{ low: 2, high: 44 }
    worker := thread.spawn_with(width, bounds).unwrap()
    print(worker.join().unwrap())
}
```

- `spawn(work)` runs a function with no arguments and returns a `Thread(R)` on success.
- `spawn_with(work, value)` copies the capture into the job. Captures and return values are checked recursively at compile time. Use scalars, arrays, and structs of values. Pointers, slices, `Str`, and any type that contains them are rejected by value.
- `spawn_shared(work, state)` explicitly permits borrowed state. Keep the memory alive until `join()` succeeds and synchronize access if it can be modified concurrently. Results still have to be pointer-free.
- `spawn_task(work, value)` and `spawn_shared_task(work, state)` accept functions with no return type. Their handles join with a `Unit` result. Use `thread.Unit` and `.{}` for a task without any state.
- `spawn_detached(work, value)` accepts a pointer-free capture and a function with no return type. It returns once the OS starts the thread. The worker releases its own job, and there is no handle to join. Arrange completion separately if the program must wait for it.
- `yield()` offers the current thread's turn to the scheduler. Use synchronization to coordinate access to shared state.
- `sleep(milliseconds)` pauses the calling thread without busy waiting. For example, `thread.sleep(250).unwrap()` waits for about a quarter of a second. Zero returns immediately. The result reports system errors; the platform timer and scheduler determine the actual wake-up time.

Treat each `Thread(R)` as a single-owner handle. Keep it in one variable and join it once. A second join on that variable returns `ErrorKind.closed`. A failed OS join leaves the handle available for a retry. The type system checks callback, capture, and result types; it does not enforce handle ownership or the lifetime of borrowed memory.

Operations that can fail return `thread.Result(T)`. Check `is_success()` or `is_error()`, then read `unwrap()` or `unwrap_error()`. `Error.kind` identifies allocation failure, a system failure, or a closed resource. For system failures, `Error.code` preserves the native status.

`Mutex(T).new(value)` creates a mutex with typed data. The mutex owns a separate native lock. Once shared, keep the mutex at a stable address and do not copy it. Pass pointers such as `&counter` to `spawn_shared`.

- `lock()` acquires the mutex and returns `&T`; call `unlock()` and stop using that reference.
- `try_lock()` returns `Maybe(&T)`. Unlock only when it succeeds.
- `with_lock(work)` passes `&T` to a callback, releases the mutex when the callback returns, and returns its pointer-free result.
- `destroy()` releases the native lock. Use it after all workers have stopped using the mutex and the lock is free.

A spawn uses one job allocation for its typed callback, capture, and result. Joining or completing a detached worker frees the job. There is no separate capture object or thread pool. Reflection checks run at compile time. Programs that do not use threads do not include the native thread bridge.

`thread.supported` is a compile-time constant. Threads are available on native Linux, macOS, and Windows builds. The VM, WASI, and freestanding targets do not run them. When linking generated C yourself on POSIX, pass `-pthread`.

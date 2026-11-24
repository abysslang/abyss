# Filesystem & Paths

`std/fs` and `std/path` read, write, and inspect files and directories with `Str` paths and arena-scoped reads. Path handling is portable across Linux, macOS, and Windows.

```abyss
File :: @import("std/fs").File
Path :: @import("std/path").Path
Arena :: @import("std/allocator").Arena

main :: fn() {
    arena := Arena.new(65536)
    log_path := Path.join(&arena, "logs", "app.log")

    File.write_string(log_path, "application started\n")
    if File.exists(log_path) {
        print(File.size(log_path))
    }

    arena.destroy()
}
```

---

## 1. `File`

`File` is a namespace of static helpers for whole-file operations. Paths are `Str`.

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `open` | `fn(path Str, mode &u8) Maybe(FileStream)` | Open with a C mode string such as `c"rb"`. |
| `open_read` | `fn(path Str) Maybe(FileStream)` | Read-only. |
| `create` | `fn(path Str) Maybe(FileStream)` | Create or truncate for writing. |
| `open_append` | `fn(path Str) Maybe(FileStream)` | Open for appending. |
| `read_to_string` | `fn(a &Arena, path Str) Maybe(Str)` | Read the whole file into `a`. |
| `write_string` | `fn(path Str, content Str) bool` | Create or overwrite. |
| `append_string` | `fn(path Str, content Str) bool` | Append, creating if needed. |
| `exists` | `fn(path Str) bool` | Existence test. |
| `size` | `fn(path Str) u64` | Length in bytes (`0` if unreadable). |

```abyss
File :: @import("std/fs").File
Arena :: @import("std/allocator").Arena

main :: fn() {
    arena := Arena.new(65536)
    content := File.read_to_string(&arena, "config.json")
    if content.is_some() {
        print(content.unwrap())
    }
    arena.destroy()
}
```

Module-level conveniences wrap the same operations with `&u8` paths and a fatal error path:

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `read_file` | `fn(a &Arena, path &u8) Str` | Read or `#fall` with a message. |
| `try_read_file` | `fn(a &Arena, path &u8) Str` | Read or return an empty `Str`. |
| `write_file` | `fn(path &u8, content Str) bool` | Write or `#fall`. |
| `append_file` | `fn(path &u8, content Str) bool` | Append or `#fall`. |
| `file_exists` | `fn(path &u8) bool` | Existence test. |

## 2. `FileStream`

`FileStream` is an open handle for streaming reads and writes. It carries a `handle i64` and an `opened bool`.

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `open` | `fn(path &u8, mode &u8) Maybe(Self)` | Mode strings such as `c"rb"`. |
| `open_read` / `create` / `open_append` | `fn(path &u8) Maybe(Self)` | Convenience modes. |
| `is_open` | `fn(self &Self) bool` | Handle state. |
| `close` | `fn(self &Self) bool` | Close the handle. |
| `read` | `fn(self &Self, buf &u8, count u64) u64` | Read up to `count` bytes. |
| `read_all` | `fn(self &Self, a &Arena) Str` | Read the whole file into `a`. |
| `write` | `fn(self &Self, buf &u8, count u64) u64` | Write bytes. |
| `write_str` | `fn(self &Self, s Str) bool` | Write a `Str`. |
| `seek` | `fn(self &Self, offset i64, whence i32) bool` | Reposition. |
| `seek_to_start` / `seek_to_end` | `fn(self &Self) bool` | Jump to a boundary. |
| `tell` | `fn(self &Self) i64` | Current offset. |
| `size` | `fn(self &Self) u64` | File length. |

`SEEK_SET()`, `SEEK_CUR()`, and `SEEK_END()` name the `whence` values.

```abyss
File :: @import("std/fs").File

main :: fn() {
    stream := File.create("out.txt").unwrap()
    stream.write_str("first line\n")
    stream.write_str("second line\n")
    stream.close()
}
```

## 3. `Dir` and `DirStream`

`Dir` lists directories and walks trees; paths are `&u8` at this level.

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `create` | `fn(path &u8) bool` | Make a directory. |
| `open` | `fn(path &u8) Maybe(DirStream)` | Open for iteration. |
| `exists` | `fn(path &u8) bool` | Directory exists. |
| `is_directory` | `fn(path &u8) bool` | Same as `exists`. |
| `walk` | `fn(a &Arena, root Str, ext Str) Vec(Str)` | Recursively collect files with extension `ext` (or all when empty). |

`DirStream` has `open(path &u8) Maybe(Self)`, `close() bool`, and `next() Maybe(DirEntry)`. A `DirEntry` holds `name Str` and `kind DirEntryKind`, with `is_file()` and `is_dir()`; `DirEntryKind` is `enum u8 { unknown, file, directory }`. `.` and `..` are skipped for you.

```abyss
Dir :: @import("std/fs").Dir
Arena :: @import("std/allocator").Arena

main :: fn() {
    arena := Arena.new(65536)
    for path in Dir.walk(&arena, "src", ".a") {
        print(path)
    }
    arena.destroy()
}
```

`Dir.walk` returns a `Vec(Str)` whose backing storage you still own; `for path in ...` iterates it directly.

## 4. `Path`

`Path` joins, splits, and normalizes paths. There is no `dirname`, `basename`, or `extension`; use `dir` and `base`, and test with `ends_with`.

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `join` | `fn(arena &Arena, base Str, rel Str) Str` | Join with a separator. |
| `dir` | `fn(path Str) Str` | Everything before the last separator. |
| `base` | `fn(path Str) Str` | Everything after the last separator. |
| `is_absolute` | `fn(path Str) bool` | POSIX or drive-letter absolute. |
| `normalize` | `fn(arena &Arena, path Str) Str` | Collapse `.`, `..`, and separators. |
| `resolve` | `fn(arena &Arena, base Str, rel Str) Str` | Resolve `rel` against `base`. |
| `ensure_ext` | `fn(arena &Arena, path Str, ext Str) Str` | Append `ext` unless already present. |
| `to_cstr` | `fn(arena &Arena, path Str) &u8` | Null-terminated copy. |

```abyss
Path :: @import("std/path").Path
Arena :: @import("std/allocator").Arena

main :: fn() {
    arena := Arena.new(4096)
    full := Path.join(&arena, "src", "compiler/main.a")
    print(Path.dir(full))
    print(Path.base(full))
    print(Path.is_absolute(full))
    print(Path.normalize(&arena, "./a/../b"))
    arena.destroy()
}
```

## 5. Environment and Arguments

`std/env.Env` exposes process arguments and environment variables:

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `args_len` | `fn() i32` | Argument count. |
| `arg` | `fn(idx i32) &u8` | Argument at `idx`, or null. |
| `get` | `fn(name &u8) &u8` | Environment value, or null. |
| `get_or` | `fn(name &u8, default_val &u8) &u8` | Value or a fallback. |
| `has` | `fn(name &u8) bool` | Variable is set. |
| `shift_args` | `fn(index i32)` | Drop the first `index` arguments. |
| `home_dir` | `fn(arena &Arena) Str` | User home directory. |
| `abyss_home` | `fn(arena &Arena) Str` | Abyss install/data directory. |

```abyss
Env :: @import("std/env").Env

main :: fn() {
    print(Env.args_len())
    print(Env.get_or(c"PATH", c""))
}
```

## 6. Embedding Files at Compile Time

`std/fs.Embed` produces source strings that bake file contents into the program:

| Function | Signature | Notes |
| :--- | :--- | :--- |
| `file` | `fn(a &Arena, path Str) Str` | Code that returns one file's `Str`. |
| `tree` | `fn(a &Arena, root Str, ext Str) Str` | Code that returns the content for a path under `root`. |
| `sources` | `fn(a &Arena) Str` | Code embedding the core and std pods. |

The result is fed into a splice (`#Embed.file(...)`), so the file bytes become a compile-time constant and incur no runtime file access.

---

[Previous: I/O & Formatting](03-io-and-fmt.md) | [Next: Allocators & Memory →](05-allocators-and-mem.md)

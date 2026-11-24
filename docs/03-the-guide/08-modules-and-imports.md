# Modules & Imports

`@import` loads another `.a` file and hands back its top-level declarations as a namespace value. A module is a normal value: you can bind it, pass it, return it, and name its type, all with no import lists and no header files.

Snippets in this chapter reference sibling files such as `./math` and `./counter`, which stand for `.a` files next to the importing file. Pods such as `json` need their search root mounted with `--map`; see [Remapping with `--map`](#remapping-with---map).

```abyss
string :: @import("std/string")
Math :: @import("./math")

main :: fn() {
    arena := @import("std/allocator").Arena.new(1024)
    buffer := string.String.new(&arena)
    buffer.push_str("modules")
    print(buffer.as_str())
    arena.destroy()
    print(Math.pi)
}
```

`@import` is an expression, so it works anywhere: at the top of a file, inside a function, inside a block, or in the middle of a larger expression.

---

## 1. Binding a Module

The most common form binds the whole module to a name and reaches members through it:

```abyss
std :: @import("std")
Json :: @import("json")

main :: fn() {
    arena := std.allocator.Arena.new(4096)
    parser := Json.JsonParser.new(&arena, "{}")
    print(parser.cursor)
    arena.destroy()
}
```

You can also bind a single member directly, which keeps a call site short:

```abyss
Arena :: @import("std/allocator").Arena
Vec :: @import("std/collections/vec").Vec

main :: fn() {
    v := Vec(i32).new()
    v.push(1)
    arena := Arena.new(1024)
    print(v.len)
    v.destroy()
    arena.destroy()
}
```

Every top-level declaration in the imported file is a member: constants, mutable globals, functions, structs, enums, and unions. Importing a file does **not** re-export the zero-import prelude, so `Maybe`, `Str`, and `print` are not members of a module you import — they are already in scope everywhere.

### Import in Place

Because `@import` is an expression, a module can be used without a file-level binding:

```abyss
main :: fn() {
    print(@import("./math").pi)
    print(@import("./math").square(6))
}
```

This is the key to incremental, order-independent code: a module is loaded when its value is first needed, so declarations may appear in any order within a file and modules may refer to each other freely.

## 2. Module Values Are First-Class

A module resolves to a nominal struct value whose members are its declarations. That makes a module ordinary data:

```abyss
-- counter.a
count := 0
step :: fn(n i32) i32 {
    count = count + n
    count
}
```

```abyss
counter :: @import("./counter")

Measured :: @typeof(counter)

read :: fn(module &Measured) i32 {
    module.count
}

main :: fn() {
    same: Measured = counter
    print(read(&same))
    print(counter.step(5))
    print(read(&same))
}
```

Pass a module as an argument, return one from a function, or store one in a variable. A member type is reachable through the module value too, so a declaration you already hold gives access to its types:

```abyss
geometry :: @import("./geometry")

Module :: @typeof(geometry)

make :: fn() Module {
    geometry
}

main :: fn() {
    origin: make().Point = .{ x: 0, y: 0 }
    print(@sizeof(origin))
}
```

## 3. Path Resolution

An import path is a compile-time `Str`. Resolution works like this:

1. A path starting with `./` or `../` is relative to the importing file.
2. Any other path is resolved against the search roots: the working directory plus every directory added with `-I`.
3. An extensionless path first tries `name.a`, then `name/name.a`.
4. A path ending in `.a` selects that exact file.

```abyss
local    :: @import("./sibling")        -- ../ or ./ for files next to you
library  :: @import("std/allocator")    -- search roots
explicit :: @import("./pkg/entry.a")    -- pick a file directly
```

The path must be known before the program runs; a runtime value is rejected with `@import path must be a compile-time Str`. A `cmpt` parameter satisfies this and is the idiomatic way to forward a path:

```abyss
load_value :: fn(cmpt module_path Str) i32 {
    @import(module_path).value
}

main :: fn() {
    print(load_value("./config"))
}
```

### Remapping with `--map`

`--map prefix=path` rewrites a module prefix before resolution, which is how tools mount packages without editing sources:

```sh
abyssc r main.a --map json=/opt/pods/json
```

An import of `json` or `json/...` then resolves under `/opt/pods/json`.

## 4. One Module, One Instance

A resolved file has exactly one module identity per compilation. The compiler caches it, so importing the same path twice — directly, through `@import` in an expression, or through a variable — returns the same module:

```abyss
counter :: @import("./counter")

main :: fn() {
    counter.step(3)
    print(@import(path).count)
    print(counter.count)
}

path :: "./counter"
```

Both reads observe the same mutable global, and the module's code is emitted once no matter how many aliases point at it. That is what keeps incremental builds fast and output small: an import is a reference, never a copy of the file's contents.

## 5. Re-exports

A module can forward another module's members by binding them at its own top level. This builds a facade without duplicating declarations:

```abyss
-- aliases.a
Point :: @import("./geometry").Point
answer :: @import("./core_math").answer
text :: "re-exported"
```

```abyss
-- facade.a
Forwarded :: @import("./aliases").Point
forwarded_value :: @import("./aliases").answer
text :: @import("./aliases").text
```

```abyss
main :: fn() {
    p: @import("./facade").Forwarded = .{ x: 1, y: 2 }
    print(p.x + p.y)
    print(@import("./facade").forwarded_value())
    print(@import("./facade").text)
}
```

## 6. Circular Imports

Two modules may import each other as long as the declarations they reference can be resolved independently. A constant in `circ_a` may read a constant in `circ_b`, and `circ_b` may read a constant in `circ_a`:

```abyss
-- circ_a.a
circ_b :: @import("./circ_b")
A_CONST :: 100
get_from_b :: fn() i32 { circ_b.B_CONST + 1 }
```

```abyss
-- circ_b.a
circ_a :: @import("./circ_a")
B_CONST :: 200
get_from_a :: fn() i32 { circ_a.A_CONST + 2 }
```

```abyss
main :: fn() {
    a :: @import("./circ_a")
    b :: @import("./circ_b")
    print(a.get_from_b())
    print(b.get_from_a())
}
```

Functions and types resolve lazily, so a cycle of function references is fine. What is rejected is a cycle in *value initialization* — for example, two mutable globals that each compute their initializer from the other. The compiler reports `circular reference in module binding` instead of looping.

## 7. Program Entry

The file named on the command line is the entry module, and its `main` is the program entry point. `main` takes no parameters and may return a value, which becomes the process exit status:

```abyss
main :: fn() i32 {
    if not @import("./config").valid {
        ret 1
    }
    0
}
```

An entry can also alias an imported function directly:

```abyss
main :: @import("./app").run
```

## Idiomatic Summary

| Concept | Idiomatic Abyss | Avoid |
| :--- | :--- | :--- |
| **Whole module** | `std :: @import("std")` | Importing each symbol on its own line |
| **Single member** | `Arena :: @import("std/allocator").Arena` | `arena_mod.Arena` at every call |
| **Reaching a type** | `@import("./pkg").Widget` | A second import path |
| **Runtime path** | A `cmpt` `Str` parameter | Building a path at runtime |
| **Text** | `Str` paths | Null-terminated `&u8` paths |

---

[Previous: Comptime & Metaprogramming](07-comptime-and-metaprogramming.md) | [Next: C Interoperability →](09-c-interop.md)

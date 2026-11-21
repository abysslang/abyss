# Calling C from Abyss

Use a top-level `extern fn` declaration to import a C symbol. Without an explicit name, Abyss uses the binding name as the linker symbol. With a name, the binding and the C identifier can differ.

```abyss
puts :: extern fn(message &u8) i32
c_abs :: extern "abs" fn(i32) i32

main :: fn() {
    puts(c"Hello from Abyss")
    print(c_abs(-42))
}
```

Parameter names are optional, and consecutive names can share a type (`a, b i32`). Use a newline after an anonymous named type when it precedes a group of named parameters. A declaration without a return type returns no value. Generic, compile-time, and variadic parameters are invalid on external functions. Use a fixed-signature C wrapper for a variadic API.

A body turns the declaration into an export. The native backend emits the function under its C linker name, including exports that Abyss code never calls. In a VM run, the body executes as bytecode. Pass the function as a callback to share it with C. Exported names are linker symbols only in native builds.

```abyss
Point :: extern struct {
    x f64
    y f64
}

distance_sq :: extern "abyss_distance_sq" fn(p Point) f64 {
    p.x * p.x + p.y * p.y
}

Distance :: fn(Point) f64
```

`extern struct` preserves declaration order and uses C alignment and padding. Match the fields and their types on the C side. A bodyless declaration such as `Distance`, without `extern`, is a function type alias. Use it in declarations that accept or return function pointers.

When a C header provides the declaration, name it in brackets. Abyss uses the header's prototype or type directly in the generated output.

```abyss
File :: extern ["stdio.h"] "FILE" struct {}
tmpfile :: extern ["stdio.h"] fn() &File
fclose :: extern ["stdio.h"] fn(&File) i32

Division :: extern ["stdlib.h"] "div_t" struct {
    quot i32
    rem  i32
}

divide :: extern ["stdlib.h"] "div" fn(i32, i32) Division
end_of_file :: fn() i32 { @c_value("stdio.h", "EOF", i32) }
```

An empty body gives an opaque view of a native type. List any fields Abyss code needs using their C names and types. The C compiler determines layout, including fields you omit. A named type can refer to a typedef or use a tag such as `"struct timespec"`. Use `@c_value(header, name, T)` to read an integer macro, enum constant, or header-declared value as a fixed-width Abyss integer. To declare a C `void *`, define `Void :: @typeof({})` and use `&Void`.

Header bindings are for hosted native code. Headers are included only when a binding is used. Sizes and values supplied by the C toolchain are unavailable to Abyss's VM and `cmpt` evaluator.

For native builds, link the generated C with the objects or libraries that provide the imports. For VM calls, symbols must already be visible to the running process. On Linux, for example, load a shared library with `LD_PRELOAD`:

```sh
cc -shared -fPIC helper.c -o helper.so
LD_PRELOAD="$PWD/helper.so" ./abyss r main.a
```

Typed VM foreign calls load the platform libffi shared library at runtime. Building the compiler does not require libffi headers. The VM bridge supports booleans, 8- to 64-bit integers, `f32`, `f64`, pointers, callbacks, and records made from those types. Keep callbacks on the VM's owning thread and call them only while that VM is alive. WebAssembly does not load native libraries.

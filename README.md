<p align="center">
  <img src=".github/assets/logo.svg" alt="Abyss" width="360" />
</p>

**Built for the deep.**

Carry nothing to the bottom. Abyss is a self-hosted systems language that burns off abstraction at compile time—emitting native x86-64 ELF, C99, and WASI through **Keel** with zero runtime behind your binary.

- **Instant VM, native Keel** — Iterate on an integrated bytecode VM; ship SSA-optimized machine code or standalone C.
- **Compile-time first** — First-class types, layout reflection, `cmpt`, and format checks resolve before execution.
- **Deterministic to the bit** — Bit-identical multi-generation bootstrap with zero external dependencies and direct C ABI interop.

---

## Code at a Glance

A stack-based bytecode virtual machine in Abyss:

```zig
Op :: enum {
    halt
    push
    add
    sub
    mul
    print
}

main :: fn() {
    program := .[
        Op.push
        Op.push
        Op.add
        Op.push
        Op.mul
        Op.print
        Op.halt
    ]

    s := Vec(i32).new()

    for inst in program {
        match inst {
            halt  { break }

            push  { s.push(42) }
            add   { s.push(s.pop() + s.pop()) }
            sub   { s.push(s.pop() - s.pop()) }
            mul   { s.push(s.pop() * s.pop()) }

            print {
                printf("result = {}\n", .(s.pop()))
            }
        }
    }
}
```

---

## Installation

```sh
# Linux (x86_64)
curl -fsSL https://raw.githubusercontent.com/abysslang/abyss/main/scripts/install.sh | bash

# Windows (x86_64 PowerShell)
irm https://raw.githubusercontent.com/abysslang/abyss/main/scripts/install.ps1 | iex
```

---

## Website

Visit the official website at [jhosein58.github.io/abyss](https://jhosein58.github.io/abyss), or read the [Into the Abyss](docs/README.md) book directly in this repository.

---

## License

[MIT](LICENSE)

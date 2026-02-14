# LSL Selfhost (LSL-in-LSL)

This repo contains a self-hosting LSL compiler written in LSL that emits native x86-64 ELF binaries (Linux).

## Quick Start

Compile any LSL file using the selfhost compiler via CLI arguments:
(Not working)
```bash
./compiler_selfhost_stage1.out path/to/input.lsl -o path/to/output.out
# or
./compiler_selfhost_stage1.out path/to/input.lsl path/to/output.out
```

Use `--baremetal` to force LXB output regardless of extension. The legacy
`build/compile_request.txt` fallback is still supported when no CLI args are
provided.

The output is a native ELF. Run it directly:

```bash
./path/to/output.out
```

## Self-Compile

```bash
./compiler_selfhost_stage1.out compiler_selfhost.lsl -o build/compiler_selfhost.out
```

Optional stage-1 refresh:

```bash
./compiler_selfhost.out compiler_selfhost.lsl -o build/compiler_selfhost_stage1.out
```

## Libraries

`use` accepts file paths and bare library names. Bare names resolve to `stdlib/<name>.lsl`.
Stdlib library functions are also injected by default, so `use` is optional for these:

- `use "math"` -> `stdlib/math.lsl`
- `use "string"` -> `stdlib/string.lsl`
- `use "list"` -> `stdlib/list.lsl`
- `use "advanced"` -> `stdlib/advanced.lsl`

You can still do `use "path/to/file.lsl"` as before.

### Desktop stack stdlib modules

The following LSL modules provide a minimal desktop stack (window server/compositor, widgets, rendering, events, and app framework):

- `use "hardware"` -> low-level framebuffer/input helpers and color utilities
- `use "surface"` -> in-memory pixel surfaces
- `use "draw"` -> drawing primitives (lines, rects, circles, text)
- `use "font"` -> bitmap font helpers
- `use "window"` -> window manager/compositor
- `use "widgets"` -> basic widgets (Button, Label, TextInput)
- `use "layout"` -> layout helpers for widget placement
- `use "events"` -> event queue + polling
- `use "app"` -> application framework and main loop
- `use "image"` -> BMP load/save helpers

Example app: `examples/desktop_demo.lsl`.

## Builtins (Selfhost)

Core builtins:

- `print`, `len`, `chr`, `num`, `bytes`
- `str`, `int`, `type`, `is_number`, `is_string`, `is_list`
- `count`, `insert`, `index`, `pop`, `clear`
- `abs`, `min`, `max`, `round`, `floor`, `ceil`
- `sum`, `average`, `reverse`, `join`
- `rand`, `sleep`, `upper`, `lower`, `substring`, `replace`, `trim`, `split`
- `input`, `readnum`, `readline`
- `readfile`, `writefile`, `appendfile`, `createdir`, `listdir`, `deletedir`, `exists`

Low-level OS/GUI builtins:

- `inb`, `outb`, `inw`, `outw`, `inl`, `outl`
- `peek8`, `peek16`, `peek32`, `poke8`, `poke16`, `poke32`
- `phys_read`, `phys_write`, `virt_to_phys`, `mmap`, `alloc_pages`
- `cli`, `sti`, `hlt`, `int`, `rdtsc`, `cpuid`, `rdmsr`, `wrmsr`
- `fb_init`, `fb_pixel`, `fb_rect`, `fb_clear`
- `keyboard_read`, `keyboard_poll`, `mouse_read`, `mouse_poll`

## Notes / Limitations

- The compiler accepts CLI args; when none are provided it falls back to `build/compile_request.txt` with two lines (input path, output path).
- `input()` reads a single line from stdin (no EOF required).
- Numbers are currently integer-only in the selfhost runtime. `math` uses fixed-point approximations.
- `sin`, `cos`, `tan`, `log`, `exp` are approximate and return integers (rounded).
- `map`, `filter`, `reduce` accept a function name string: `map("fn_name", list)`.
- Dictionaries are represented as list-of-pairs; `type()` returns `"list"` for dict values.

## Error Messages

Compiler errors are formatted like:

```
[ ERROR E002 ] Unclosed String
---------------------------------------------------------
File: src/main.lsl:12:25

11 |  int = 100
12 |  print "Hi: + int
   |               ^^^
   |                      Missing closing quote in string literal.

Hint: To fix this error add closing quote.
---------------------------------------------------------
```

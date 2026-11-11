# glassjar's Rust toolchain

The Rust compiler that [glassjar](https://github.com/glassjar-dev/engine) runs in the browser:
this fork of rust-lang/rust built for a `wasm32-wasip1` host.

```bash
glassjar/build.sh     # -> glassjar/dist/rustc.wasm, glassjar/dist/rust-sysroot.tar.gz
```

`rustc.wasm` compiles a crate and links it in one run, with the `wasm-ld` it carries:

```bash
wasmtime run --dir sysroot::/ --dir .::/work rustc.wasm /work/main.rs --edition=2024 \
  --sysroot / --target wasm32-wasip1 -Ccodegen-units=1 -o /work/main.wasm
```

It is a compiler for one job: WebAssembly programs at `-Copt-level=0`. Asking it to optimize
or to use LTO is an error. Everything else (diagnostics, the borrow checker, `--emit=metadata`,
debug info) is rustc as upstream wrote it.

## What differs from upstream

- **Hosted on WASI** (bjorn3's work, plus the debugger-sh project's): no threads, no process
  spawning, code generation runs inline.
- **Links in-process.** `rustc_llvm` carries lld's WebAssembly driver
  (`llvm-wrapper/WasmLdWrapper.cpp`) and `link_natively` calls it instead of spawning a linker.
- **A small LLVM.** The LLVM linked into `rustc.wasm` is built for size, as bitcode that the
  final link optimizes as a whole, with `GLASSJAR_TINY` and `GLASSJAR_O0_ONLY` (see the
  `glassjar-tiny` branch of glassjar-dev/llvm): WebAssembly is the only target and -O0 the only
  pipeline, so the optimizer, the other backends, LTO and the sanitizers never link in.
  `LLVMRustOptimize` has a matching -O0-only body.
- **Binaryen** (`wasm-opt -Os`) runs over the result.
- **The sysroot is built separately** from the std that rustc.wasm itself links: without
  backtrace support (WASI has none, so the symbolizer crates and the `RUST_BACKTRACE` note
  after a panic go away) and without the crates only tests and proc macros use.

| | upstream recipe (2026-05-31) | this build |
| --- | --- | --- |
| `rustc.wasm` | 62.4 MB | 34.1 MB |
| linker | clang's 35 MB module | inside `rustc.wasm` |
| sysroot, unpacked / gzip | 82 MB / 29.0 MB | 62 MB / 21.1 MB |

## Tools

- `corpus.sh` builds and runs the programs in `corpus/` with a toolchain under wasmtime and
  records what a student would see. `diff -r` two recordings to compare toolchains.
- `sizes.py` attributes the code in a named build (`dist/bin/rustc.wasm`) to crates and
  functions; `who.py` says what keeps a function linked.
- `llvm-config.sh` is the `llvm-config` bootstrap uses when rustc's host is WebAssembly.

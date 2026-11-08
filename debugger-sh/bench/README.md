# rustc.wasm benchmarks

Scripts for measuring the browser Rust toolchain (`rustc.wasm` + sysroot + `wasm-ld` from
`llvm.core.wasm`) the way glassjar runs it. They use Node's built-in WASI, so wasm runs on
V8 like it does in Chrome. Nothing needs installing beyond Node 22+.

| script | what it measures |
| --- | --- |
| `bench.mjs` | the full engine pipeline: rustc → wasm-ld → run, per program, cold and warm |
| `wasi-prof.mjs` | where one rustc invocation spends its WASI time, and which files it touches |
| `incr.mjs` | edit-compile loops with and without `-Cincremental` (needs a WASI flock, see the file) |
| `corpus/` | `hello.rs` (6 lines), `medium.rs` (100 lines: traits, generics, collections, fmt), `large.rs` (12 copies of medium in modules, ~1.3k lines) |

```bash
# artifacts as the engine consumes them
curl -LO https://cdn.yousefabuhashem.com/rust/2026-05-31/rustc.wasm
curl -LO https://cdn.yousefabuhashem.com/rust/2026-05-31/rust-sysroot.tar.gz
curl -LO https://cdn.yousefabuhashem.com/clang/2026-05-22/llvm.core.wasm
mkdir sysroot && tar -xzf rust-sysroot.tar.gz -C sysroot

node bench.mjs --rustc rustc.wasm --ld llvm.core.wasm --sysroot sysroot --iters 3 --debug corpus/*.rs
node bench.mjs --rustc rustc.wasm --sysroot sysroot --time-passes corpus/large.rs   # per-pass breakdown
mkdir work && cp corpus/hello.rs work/
node wasi-prof.mjs --files --sysroot sysroot --work work rustc.wasm -- \
  /work/hello.rs --sysroot /sysroot --target wasm32-wasip1 -Cpanic=abort -Zthreads=1 --emit=obj -o /work/hello.o -g
```

Set `BENCH_TMP` to put scratch directories somewhere other than the OS temp dir.

## Findings (2026-11, artifacts dated 2026-05-31, 4-core x86_64, Node 22)

All times are rustc only (wasm-ld adds 45–75 ms), engine flags (`-Cpanic=abort
-Ccodegen-units=1 -Zthreads=1 --emit=obj`). "Warm" is the median of iterations 1–3 reusing
the compiled module with a fresh instance, as the engine's retained worker does. Run-to-run
noise is about ±5%.

### Where the time goes

| | hello | medium | large |
| --- | ---: | ---: | ---: |
| rustc.wasm, debug (`-g`), cold first compile | ~700 ms | | |
| rustc.wasm, debug, warm | 225 ms | 1.6–1.8 s | 4.8 s |
| rustc.wasm, no `-g`, warm | 190 ms | 1.15 s | 3.6 s |
| native rustc (host stable, `-g`), for scale | 39 ms | | 1.2 s |

`-Ztime-passes` on `large.rs` (no `-g`): `codegen_crate` (LLVM) 2.4 s of 3.7 s; type check
0.42 s; borrow check 0.58 s; mono collection 0.46 s. On `hello.rs`, `expand_crate` is
0.10 s of 0.21 s: that is loading std's metadata.

**Every compile reads 61.6 MiB of `.rmeta`** (`wasi-prof.mjs`): `libcore` alone is 40 MiB.
Native rustc mmaps these and touches a fraction, but `rustc_data_structures::memmap` falls
back to reading whole files on wasm32. It's about half of a hello-world compile (native:
7 ms, wasm: 100–150 ms). Only keeping rustc alive between compiles (or snapshotting it after
crate loading) removes this.

### wasm-opt (fixed in build.sh)

The shipped rustc.wasm was never optimized by wasm-opt. The linked module has no
target_features section, so wasm-opt rejected it (`memory.copy operations require bulk
memory`), and `2>/dev/null` hid the error. With explicit features:

| | size | brotli-11 | cold hello | warm medium | warm large |
| --- | ---: | ---: | ---: | ---: | ---: |
| shipped | 59.5 MiB | 12.3 MiB | 703 ms | 1605–1805 ms | 4772–4822 ms |
| wasm-opt -Os | 50.5 MiB | 12.2 MiB | 774 ms | 1511–1640 ms | 4522–4678 ms |
| wasm-opt -O3 | 50.8 MiB | — | 755 ms | 1507–1525 ms | 4445–4763 ms |

A small lever: 15% smaller, 3–6% faster warm, ~10% slower on the very first (cold) compile
because V8 lazily compiles bigger, more inlined functions. Same size over the wire.

### Download size (the biggest cold-start cost)

| artifact | served today | brotli-11 | trimmed + brotli-11 |
| --- | ---: | ---: | ---: |
| rustc.wasm | 19.1 MB (CDN on-the-fly br) | 12.9 MB | |
| rust-sysroot.tar.gz | 29.1 MB (gzip) | 20.2 MB | 14.8 MB (21.2 MB as gzip) |
| llvm.core.wasm (wasm-ld) | 21.7 MB (CDN on-the-fly br) | 14.6 MB | |
| **total** | **69.8 MB** | | **42.3 MB (−39%)** |

- Cloudflare's on-the-fly brotli is a low quality level. Uploading `.br` files built at q11
  and serving them with `Content-Encoding: br` is free speed. build.sh now emits
  `rustc.wasm.br` and `sysroot.tar.br`.
- rustc never opens 11 of the 28 sysroot crates for a `-Cpanic=abort` wasm32-wasip1 build
  (addr2line, getopts, gimli, memchr, object, panic_unwind, proc_macro,
  rustc_literal_escaper, rustc_std_workspace_std, sysroot, test). build.sh now drops them
  (`FULL_SYSROOT=1` keeps them). The corpus plus a std edge-case program build and run
  identically with the trimmed sysroot.

### Things that didn't help (engine-side rustc flags)

`-Zshare-generics=y` and `-Zmir-opt-level=0`: no gain beyond noise on hello/large.

### Incremental compilation

`-Cincremental` fails on WASI: `flock/unsupported.rs` makes `Lock::new` always error.
Natively, on `large.rs` with a one-line edit, incremental saves ~20% per recompile
(1.2 s → 0.95 s) and costs ~10% on the first compile; more codegen units don't help further.
Worth it only alongside a persistent incr dir in the engine's retained worker.

### Next steps that need a compiler rebuild (ordered by expected payoff)

1. Keep one rustc instance alive across runs and keep std's metadata decoded (removes the
   61.6 MiB read: ~50% of small-program latency).
2. Build the hot compiler crates at opt-level=3 instead of `z` (the whole compiler is `z`
   today), and build the compiler with `+simd128` (LLVM's default CPU already gives it bulk
   memory, sign-ext and non-trapping float-to-int).
3. A faster allocator than wasi-libc's dlmalloc (fresh instance per compile makes an
   arena or bump allocator viable).
4. PGO of rustc.wasm and its LLVM, using this corpus as the training set.
5. One shared LLVM for rustc and wasm-ld (today both artifacts carry a copy).

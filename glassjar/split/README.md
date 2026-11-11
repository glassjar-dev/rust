# Hot/cold split (prototype)

Compiling a typical program runs well under half of rustc. `split.sh` uses Binaryen's
`wasm-split` to put the functions that ran while compiling `../corpus` (as Run, Debug and the
IDE's check) into `primary.wasm` and the rest into `secondary.wasm`:

| | size | zstd -19 |
| --- | --- | --- |
| `rustc.wasm` | 34.1 MB | 9.1 MB |
| `primary.wasm` | 17.7 MB | 4.8 MB |
| `secondary.wasm` | 19.8 MB | 4.8 MB |

The primary module runs alone. Its table slots for secondary functions hold imported
placeholders; the first call to one instantiates the secondary module, whose element segments
replace the placeholders, and the call is repeated through the table (`split-run.mjs`, 40
lines, is a complete loader for Node). A program that only uses profiled paths never loads
the secondary module; one that leaves them (checked with const generics, nested closures and
a type error the corpus does not have) loads it in about 40 ms and gives the same output.

Not done: the engine does not load split modules yet. It needs the same loader on wasmer's
JS backend (a host function per placeholder import, and a synchronous instantiate of the
secondary module from bytes fetched in the background after the primary), and the IDE's
check worker needs it too. The profile should also grow beyond ten programs before this
ships, since every miss costs one synchronous load.

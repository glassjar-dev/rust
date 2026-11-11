#!/usr/bin/env bash
# Builds and runs every program in corpus/ with a toolchain, under wasmtime, and records what
# a student would see: the compiler's output, the program's output and both exit codes.
# Two recordings of the same corpus can then be compared with `diff -r`.
#
#   ./corpus.sh <rustc.wasm> <unpacked sysroot> <out dir> [<llvm.core.wasm>]
#
# With a fourth argument the program is linked the way glassjar <= 0.6 did it: rustc emits an
# object and the wasm-ld inside clang's llvm.core.wasm links it. Without it rustc links.
set -eu
cd "$(dirname "$0")"
RUSTC=$1 SYSROOT=$2 OUT=$3 LD=${4:-}
LIB=lib/rustlib/wasm32-wasip1/lib
mkdir -p "$OUT/work"
wasmtime compile "$RUSTC" -o "$OUT/rustc.cwasm"
[ -z "$LD" ] || wasmtime compile "$LD" -o "$OUT/ld.cwasm"
run() { wasmtime run --allow-precompiled --dir "$SYSROOT::/" --dir "$OUT/work::/work" "$@"; }

for src in corpus/*.rs; do
  name=$(basename "$src" .rs)
  cp "$src" "$OUT/work/main.rs"
  rm -f "$OUT/work/main.wasm" "$OUT/work"/*.o
  {
    set +e
    if [ -z "$LD" ]; then
      run "$OUT/rustc.cwasm" /work/main.rs --edition=2024 --sysroot / --target wasm32-wasip1 \
        -Ccodegen-units=1 -Clink-self-contained=yes -Clink-arg=--export=__main_void -o /work/main.wasm 2>&1
      echo "rustc exit $?"
    else
      run "$OUT/rustc.cwasm" /work/main.rs --edition=2024 --sysroot / --target wasm32-wasip1 \
        -Cpanic=abort -Ccodegen-units=1 -Zthreads=1 --emit=obj -o /work/main.o 2>&1
      echo "rustc exit $?"
      if [ -f "$OUT/work/main.o" ]; then
        rlibs=$(for p in panic_abort std wasi cfg_if rustc_demangle std_detect hashbrown rustc_std_workspace_alloc \
          miniz_oxide adler2 unwind libc rustc_std_workspace_core alloc core compiler_builtins; do
          ls "$SYSROOT/$LIB"/lib$p-*.rlib | sed "s|^$SYSROOT||"; done)
        run --argv0 wasm-ld "$OUT/ld.cwasm" --export=__main_void -z stack-size=1048576 --stack-first --no-demangle \
          /$LIB/self-contained/crt1-command.o $(cd "$OUT/work" && ls *.o | sed 's|^|/work/|') $rlibs \
          -L/$LIB/self-contained -lc -o /work/main.wasm --gc-sections -O0 2>&1
      fi
    fi
    if [ -f "$OUT/work/main.wasm" ]; then
      printf '3 4\nfive 6\n\n-10\n' | wasmtime run "$OUT/work/main.wasm" 2>&1 |
        sed '/^Error: failed to run main module/,$d'
      echo "program exit ${PIPESTATUS[1]}"
    fi
    set -e
  } > "$OUT/$name.txt"
  [ ! -f "$OUT/work/main.wasm" ] || wc -c < "$OUT/work/main.wasm" | tr -d ' ' > "$OUT/$name.size"
done
rm -rf "$OUT/work" "$OUT"/*.cwasm

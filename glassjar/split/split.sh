#!/usr/bin/env bash
# Prototype: splits rustc.wasm into a hot module, holding the functions that ran while
# compiling the corpus, and a cold module with everything else, loaded on first use.
#
#   glassjar/split/split.sh <named rustc.wasm (dist/bin/rustc.wasm)> <unpacked sysroot> <out dir>
#
# Writes <out>/primary.wasm and <out>/secondary.wasm. split-run.mjs runs the pair.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
NAMED=$1 SYSROOT=$2 OUT=$3
FEATURES="--enable-bulk-memory --enable-bulk-memory-opt --enable-call-indirect-overlong --enable-multivalue
  --enable-mutable-globals --enable-nontrapping-float-to-int --enable-reference-types --enable-sign-ext"
mkdir -p "$OUT"
# The module to split is the optimized one; it keeps its names so the split can be inspected.
wasm-opt -Os -g --strip-dwarf --strip-producers $FEATURES "$NAMED" -o "$OUT/base.wasm"
# Record which functions run: an instrumented copy compiles the corpus as Run, Debug and the
# IDE's check would.
wasm-split --instrument $FEATURES "$OUT/base.wasm" -o "$OUT/instrumented.wasm"
node "$HERE/profile.mjs" "$OUT/instrumented.wasm" "$SYSROOT" "$HERE/../corpus" "$OUT/profiles" 2>/dev/null
wasm-split --merge-profiles $FEATURES "$OUT"/profiles/*.prof -o "$OUT/merged.prof"
wasm-split --split $FEATURES "$OUT/base.wasm" --profile="$OUT/merged.prof" --strip-debug \
  -o1 "$OUT/primary.wasm" -o2 "$OUT/secondary.wasm"
rm -rf "$OUT/instrumented.wasm" "$OUT/profiles"
ls -l "$OUT"/primary.wasm "$OUT"/secondary.wasm

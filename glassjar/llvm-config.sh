#!/bin/sh
# The llvm-config that bootstrap gives rustc_llvm when rustc itself is built for wasm32-wasip1.
# What to link comes from the WebAssembly LLVM, whose own llvm-config runs under wasmtime; how
# to compile against it comes from the build machine's LLVM, built from the same source.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WASM="$ROOT/build/wasm32-wasip1/llvm"
for arg in "$@"; do
  case "$arg" in
    --components | --libs | --ldflags)
      # The guest sees the WebAssembly LLVM at /llvm; map its answers back to the real place.
      wasmtime run --dir "$WASM::/llvm" --argv0 /llvm/bin/llvm-config "$WASM/bin/llvm-config" "$@" |
        sed "s|/llvm/|$WASM/|g"
      exit
      ;;
  esac
done
exec "$ROOT/build/host/llvm/bin/llvm-config" "$@"

#!/usr/bin/env bash
# Builds the Rust toolchain that glassjar runs in the browser, into glassjar/dist/:
#
#   rustc.wasm            rustc hosted on wasm32-wasip1. It compiles a crate and links it with
#                         the wasm-ld it carries, so one module is the whole compiler.
#   rust-sysroot.tar.gz   the standard library that rustc.wasm compiles programs against.
#
# Runs on macOS and Linux. Needs cmake, ninja, python3, wasmtime and Binaryen's wasm-opt.
# A first build takes about half an hour on a fast laptop; later ones reuse build/.
#
#   glassjar/build.sh          build both
#   glassjar/corpus.sh ...     check a build's behaviour (see that script)
set -euo pipefail
cd "$(dirname "$0")/.."

WASI_VER=32
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) WASI_HOST=arm64-macos ;;
  Darwin-x86_64) WASI_HOST=x86_64-macos ;;
  Linux-x86_64) WASI_HOST=x86_64-linux ;;
  Linux-aarch64) WASI_HOST=arm64-linux ;;
  *) echo "unsupported build machine" >&2; exit 1 ;;
esac
WASI_SDK=wasi-sdk-${WASI_VER}.0-${WASI_HOST}
if ! [ -d "$WASI_SDK" ]; then
  curl -L "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_VER}/${WASI_SDK}.tar.gz" | tar xzf -
fi
# bootstrap.toml names the SDK by this link, so it holds on every build machine.
ln -sfn "$WASI_SDK" wasi-sdk
export WASI_SDK_PATH="$PWD/wasi-sdk"
LIBC="$WASI_SDK_PATH/share/wasi-sysroot/lib/wasm32-wasip1"

git submodule update --init --depth 1 library/backtrace src/llvm-project src/tools/cargo \
  src/tools/enzyme src/tools/rustc-perf src/doc/book src/doc/edition-guide src/doc/embedded-book \
  src/doc/nomicon src/doc/reference src/doc/rust-by-example

# The SDK's libc carries debug info, which would end up in every student program and make
# the debugger step into libc. Rebuild it without.
if ! [ -f build/wasi-libc/done ]; then
  rm -rf build/wasi-libc
  git clone --depth 1 --branch "wasi-sdk-${WASI_VER}" https://github.com/WebAssembly/wasi-libc.git build/wasi-libc/src
  cmake -S build/wasi-libc/src -B build/wasi-libc/build -G Ninja \
    -DCMAKE_C_COMPILER="$WASI_SDK_PATH/bin/clang" -DCMAKE_AR="$WASI_SDK_PATH/bin/llvm-ar" \
    -DCMAKE_RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" -DCMAKE_NM="$WASI_SDK_PATH/bin/llvm-nm" \
    -DTARGET_TRIPLE=wasm32-wasip1 -DBUILD_SHARED=OFF -DBUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS=-g0 -DCMAKE_ASM_FLAGS=-g0 -DWASI_SDK_VERSION="$(head -1 "$WASI_SDK_PATH/VERSION")"
  cmake --build build/wasi-libc/build
  cp build/wasi-libc/build/sysroot/lib/wasm32-wasip1/{libc.a,crt1-command.o,crt1-reactor.o} "$LIBC/"
  touch build/wasi-libc/done
fi

# macOS's ranlib empties WebAssembly archives, so name the SDK's (it must be an absolute path).
x() { ./x.py "$@" --set "target.wasm32-wasip1.ranlib=$WASI_SDK_PATH/bin/llvm-ranlib"; }

# The LLVM that goes into rustc.wasm first, so that it has the WebAssembly backend only; the
# install step then builds this machine's LLVM and rustc, and with those rustc.wasm.
x build llvm --host wasm32-wasip1 --set llvm.targets=WebAssembly
x install compiler/rustc library/std

mkdir -p glassjar/dist
# Binaryen shrinks the module by about a sixth and drops the names bootstrap.toml kept for
# glassjar/sizes.py; the features are the ones LLVM's default WebAssembly CPU uses.
wasm-opt -Os --strip-debug --strip-producers --enable-bulk-memory --enable-bulk-memory-opt \
  --enable-call-indirect-overlong --enable-multivalue --enable-mutable-globals \
  --enable-nontrapping-float-to-int --enable-reference-types --enable-sign-ext \
  dist/bin/rustc.wasm -o glassjar/dist/rustc.wasm

# The std that programs compile against is a product of its own. Built without backtrace
# support, which WASI cannot provide: that drops the symbolizer crates and the panic note
# about RUST_BACKTRACE. Shipped without the crates only `cargo test` and proc macros use.
rm -rf build/host/stage1-std/wasm32-wasip1
x build library --stage 1 --target wasm32-wasip1 --set rust.backtrace=false
STAGE=build/sysroot/lib/rustlib/wasm32-wasip1
rm -rf build/sysroot && mkdir -p "$STAGE"
cp -R build/host/stage1/lib/rustlib/wasm32-wasip1/lib "$STAGE/"
for crate in test proc_macro getopts rustc_literal_escaper sysroot rustc_std_workspace_std panic_unwind; do
  rm "$STAGE"/lib/lib${crate}-*
done
tar -cf - -C build/sysroot lib | gzip -9 > glassjar/dist/rust-sysroot.tar.gz
ls -l glassjar/dist

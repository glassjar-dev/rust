#!/usr/bin/env bash
# Build wasm32-wasip1 rustc.wasm + sysroot.tar.gz for debugger-sh.
#
# Size strategy (bootstrap.toml):
#   - opt-level=z, fat LTO, codegen-units=1, strip=true
#   - debug-assertions/logging/frame-pointers off
# This removes the ~50 MiB WASM "name" section at link time. Post-link wasm-opt
# then runs with the wasm features LLVM enables by default (see WASM_OPT_FEATURES);
# the linked module has no target_features section, so they must be passed explicitly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_OUT="$SCRIPT_DIR/build"
RUST_UPSTREAM="${RUST_UPSTREAM:-https://github.com/rust-lang/rust.git}"

log() { echo "[build] $*"; }

ensure_wasi_sdk() {
  # bootstrap.toml uses repo-relative wasi-sdk paths; Dockerfile installs at /opt/wasi-sdk.
  if [[ ! -x "$ROOT/wasi-sdk-32.0-x86_64-linux/bin/clang++" ]]; then
    if [[ -x /opt/wasi-sdk/bin/clang++ ]]; then
      ln -sfn /opt/wasi-sdk "$ROOT/wasi-sdk-32.0-x86_64-linux"
    else
      echo "error: wasi-sdk not found (expected $ROOT/wasi-sdk-32.0-x86_64-linux or /opt/wasi-sdk)" >&2
      exit 1
    fi
  fi
  export WASI_SDK_PATH="$ROOT/wasi-sdk-32.0-x86_64-linux"
}

ensure_submodules() {
  cd "$ROOT"
  find "$ROOT/.git" "$ROOT/.git/modules" \
    \( -name index.lock -o -name config.lock -o -name shallow.lock \) \
    -delete 2>/dev/null || true
  git config --global --add safe.directory "$ROOT" 2>/dev/null || true
  git config --global --add safe.directory "$ROOT/src/llvm-project" 2>/dev/null || true
  git config --global --add safe.directory "$ROOT/src/tools/enzyme" 2>/dev/null || true
  git config --global --add safe.directory "$ROOT/src/tools/enzyme/enzyme" 2>/dev/null || true
  log "Updating required submodules"
  git submodule sync src/llvm-project src/tools/enzyme
  git -C "$ROOT/src/llvm-project" clean -fdx 2>/dev/null || true
  git submodule update --init --recursive src/tools/enzyme src/llvm-project
  git -C "$ROOT/src/llvm-project" fetch origin main --depth=1
  git -C "$ROOT/src/llvm-project" reset --hard FETCH_HEAD
}

install_wasm_llvm_libs() {
  local llvm_lib="$ROOT/build/wasm32-wasip1/llvm/lib/libLLVMCore.a"
  local llvm_build_lib="$ROOT/build/wasm32-wasip1/llvm/build/lib/libLLVMCore.a"
  [[ -f "$llvm_lib" ]] && return 0
  [[ -f "$llvm_build_lib" ]] || return 1
  log "Installing wasm LLVM static libraries into lib/"
  mkdir -p "$ROOT/build/wasm32-wasip1/llvm/lib"
  cp -a "$ROOT/build/wasm32-wasip1/llvm/build/lib/"*.a "$ROOT/build/wasm32-wasip1/llvm/lib/"
}

ensure_llvm_config() {
  local src="$ROOT/build/wasm32-wasip1/llvm/build/bin/llvm-config"
  local dst="$ROOT/build/wasm32-wasip1/llvm/bin/llvm-config"
  [[ -f "$src" && ! -x "$dst" ]] || return 0
  mkdir -p "$(dirname "$dst")"
  cp -f "$src" "$dst" && chmod +x "$dst"
}

build_llvm_wasm() {
  cd "$ROOT"
  local llvm_lib="$ROOT/build/wasm32-wasip1/llvm/lib/libLLVMCore.a"
  if [[ -x build/wasm32-wasip1/llvm/bin/llvm-config && -f "$llvm_lib" ]]; then
    log "wasm LLVM already built; skipping ./x.py build llvm"
    return
  fi
  if install_wasm_llvm_libs; then
    ensure_llvm_config
    log "wasm LLVM libraries installed from build tree; skipping ./x.py build llvm"
    return
  fi
  log "Building LLVM for wasm32-wasip1 host (WebAssembly-only backend)"
  ./x.py build llvm --host wasm32-wasip1 -j "$(nproc)" \
    --set llvm.download-ci-llvm=false \
    --set llvm.targets=WebAssembly \
    --set llvm.experimental-targets=
  ensure_llvm_config
  install_wasm_llvm_libs
  test -x build/wasm32-wasip1/llvm/bin/llvm-config
  test -f "$llvm_lib"
}

link_ci_llvm() {
  cd "$ROOT"
  if [[ -d build/x86_64-unknown-linux-gnu/ci-llvm ]]; then
    log "Linking ci-llvm for wasm host codegen"
    ln -sfn "$ROOT/build/x86_64-unknown-linux-gnu/ci-llvm" \
      "$ROOT/build/wasm32-wasip1/ci-llvm"
  fi
}

# The wasi-libc artifacts packaged with the release wasi-sdk
# contain a generous amount of (unnecessary) debug info. Here we rebuild those
# objects from source to strip their debug info.
rebuild_wasi_libc_no_debug() {
  local wasi_sysroot="$WASI_SDK_PATH/share/wasi-sysroot/lib/wasm32-wasip1"
  local builddir srcdir outdir
  builddir="$ROOT/build/wasi-libc-nodbg"
  srcdir="$builddir/src"
  outdir="$builddir/build/sysroot/lib/wasm32-wasip1"

  log "Building wasi-libc without debug info"
  rm -rf "$builddir"
  git clone --depth 1 --branch wasi-sdk-32 https://github.com/WebAssembly/wasi-libc.git "$srcdir"

  cmake -S "$srcdir" -B "$builddir/build" -G Ninja \
    -DCMAKE_C_COMPILER="$WASI_SDK_PATH/bin/clang" \
    -DCMAKE_AR="$WASI_SDK_PATH/bin/llvm-ar" \
    -DCMAKE_RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
    -DCMAKE_NM="$WASI_SDK_PATH/bin/llvm-nm" \
    -DTARGET_TRIPLE=wasm32-wasip1 \
    -DBUILD_SHARED=OFF \
    -DBUILD_TESTS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="-g0" \
    -DCMAKE_ASM_FLAGS="-g0" \
    -DWASI_SDK_VERSION="$(head -1 "$WASI_SDK_PATH/VERSION")"
  cmake --build "$builddir/build" -j "$(nproc)"

  cp -f "$outdir/libc.a" "$outdir/crt1-command.o" "$outdir/crt1-reactor.o" "$wasi_sysroot/"
}

install_rustc() {
  cd "$ROOT"
  local stage0
  stage0="$(grep '^compiler_git_commit_hash=' src/stage0 | cut -d= -f2)"
  git cat-file -e "${stage0}^{commit}" 2>/dev/null \
    || git fetch "$RUST_UPSTREAM" "$stage0" --depth=1
  git fetch origin --deepen=256 --no-recurse-submodules 2>/dev/null || true
  log "Installing rustc (wasm32-wasip1 host, LLVM codegen)"
  ./x.py install -j "$(nproc)"
}

# Features LLVM's default ("generic") wasm32 CPU enables. `strip = true` drops the
# target_features custom section, so wasm-opt can't detect these and would otherwise
# reject the module (memory.copy/memory.fill need bulk memory).
WASM_OPT_FEATURES=(
  --enable-bulk-memory --enable-bulk-memory-opt --enable-sign-ext
  --enable-nontrapping-float-to-int --enable-mutable-globals --enable-multivalue
  --enable-reference-types --enable-call-indirect-overlong
)
# -Os and -O3 measured the same speed (see debugger-sh/bench/README.md); -Os is smaller.
WASM_OPT_LEVEL="${WASM_OPT_LEVEL:--Os}"

optimize_rustc_wasm() {
  local wasm="$1"
  log "Optimizing rustc.wasm (wasm-opt $WASM_OPT_LEVEL)... before=$(awk "BEGIN {printf \"%.1f\", $(stat -c%s "$wasm")/1048576}") MiB"
  # Fail loudly: a silently skipped wasm-opt ships an unoptimized compiler.
  wasm-opt "$WASM_OPT_LEVEL" "${WASM_OPT_FEATURES[@]}" --strip-debug --strip-producers \
    "$wasm" -o "${wasm}.opt"
  mv "${wasm}.opt" "$wasm"
  log "Finished optimizing... after=$(awk "BEGIN {printf \"%.1f\", $(stat -c%s "$wasm")/1048576}") MiB"
}

# Crates in the wasm32-wasip1 sysroot that rustc never loads when compiling a
# `-Cpanic=abort` binary (no --test, no proc-macro crates): std's backtrace stack
# (addr2line/gimli/object/memchr) isn't a dependency on WASI, and test/getopts/
# proc_macro/panic_unwind/... are only for other configurations. Dropping them cuts
# sysroot.tar.gz by ~27%. Set FULL_SYSROOT=1 to keep them.
SYSROOT_UNUSED_CRATES=(
  addr2line getopts gimli memchr object panic_unwind proc_macro
  rustc_literal_escaper rustc_std_workspace_std sysroot test
)

trim_sysroot() {
  local libdir="$1/lib/rustlib/wasm32-wasip1/lib"
  [[ "${FULL_SYSROOT:-0}" == 1 ]] && return 0
  local crate
  for crate in "${SYSROOT_UNUSED_CRATES[@]}"; do
    rm -f "$libdir/lib${crate}-"*.rlib "$libdir/lib${crate}-"*.rmeta
  done
  log "Trimmed sysroot to $(find "$libdir" -maxdepth 1 -name '*.rlib' | wc -l) crates"
}

package_artifacts() {
  cd "$ROOT"
  mkdir -p "$BUILD_OUT"
  local rustc_src=""
  for cand in dist/bin/rustc.wasm dist/bin/rustc \
    build/wasm32-wasip1/stage2/bin/rustc.wasm build/wasm32-wasip1/stage2/bin/rustc; do
    [[ -f "$cand" ]] || continue
    rustc_src="$cand"
    break
  done
  [[ -n "$rustc_src" ]] || { echo "error: rustc wasm binary not found after install" >&2; exit 1; }
  [[ -d dist/lib/rustlib ]] || { echo "error: dist/lib/rustlib missing after install" >&2; exit 1; }

  log "Packaging $BUILD_OUT/rustc.wasm and sysroot.tar.gz"
  cp -f "$rustc_src" "$BUILD_OUT/rustc.wasm"
  optimize_rustc_wasm "$BUILD_OUT/rustc.wasm"

  local staging
  staging="$(mktemp -d)"
  mkdir -p "$staging/sysroot/lib"
  cp -a dist/lib/rustlib "$staging/sysroot/lib/rustlib"
  trim_sysroot "$staging/sysroot"

  if [[ -d dist/etc ]]; then
    mkdir -p "$staging/sysroot/etc"
    cp -a dist/etc "$staging/sysroot/etc"
  fi
  tar -czf "$BUILD_OUT/sysroot.tar.gz" -C "$staging/sysroot" lib etc 2>/dev/null \
    || tar -czf "$BUILD_OUT/sysroot.tar.gz" -C "$staging/sysroot" lib
  rm -rf "$staging"

  gzip -t "$BUILD_OUT/sysroot.tar.gz"

  # Brotli-11 copies for serving with `Content-Encoding: br`. On-the-fly CDN brotli is far
  # weaker (rustc.wasm: 19.1 MB on the wire vs 12.9 MB at q11). The engine accepts the
  # plain tar the browser hands back after decoding.
  gzip -dc "$BUILD_OUT/sysroot.tar.gz" | brotli -q 11 -c > "$BUILD_OUT/sysroot.tar.br"
  brotli -q 11 -f -o "$BUILD_OUT/rustc.wasm.br" "$BUILD_OUT/rustc.wasm"
  ls -lh "$BUILD_OUT/rustc.wasm" "$BUILD_OUT/rustc.wasm.br" "$BUILD_OUT/sysroot.tar.gz" "$BUILD_OUT/sysroot.tar.br"
}

main() {
  ensure_wasi_sdk
  ensure_submodules
  build_llvm_wasm
  link_ci_llvm
  rebuild_wasi_libc_no_debug
  install_rustc
  package_artifacts
  log "Build complete. Run debugger-sh/test.sh to validate artifacts."
}

main "$@"

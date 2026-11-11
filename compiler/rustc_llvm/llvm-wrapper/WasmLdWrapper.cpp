// The wasm-ld that a wasm-hosted rustc links with (see `link_natively` in rustc_codegen_ssa).

#include "lld/Common/Driver.h"
#include "llvm/Support/raw_ostream.h"

LLD_HAS_DRIVER(wasm)

extern "C" int LLVMRustWasmLd(const char *const *Args, size_t Len) {
  bool Ok = lld::wasm::link(llvm::ArrayRef(Args, Len), llvm::outs(), llvm::errs(),
                            /*exitEarly=*/false, /*disableOutput=*/false);
  return Ok ? 0 : 1;
}

// Runs a split rustc (wasm-split): the primary module alone until it calls a function that
// lives in the secondary module, which is then instantiated on the spot.
//   node split-run.mjs <primary.wasm> <secondary.wasm> <sysroot> <work dir> <rustc args...>
import { readFileSync } from 'node:fs';
import { WASI } from 'node:wasi';
const [primaryPath, secondaryPath, sysroot, work, ...args] = process.argv.slice(2);
const wasi = new WASI({ version: 'preview1', args: ['rustc', ...args], preopens: { '/': sysroot, '/work': work }, returnOnExit: true });
const primary = new WebAssembly.Module(readFileSync(primaryPath));
let instance, loaded = null;
const loadSecondary = (slot) => {
  if (!loaded) {
    const t = performance.now();
    new WebAssembly.Instance(new WebAssembly.Module(readFileSync(secondaryPath)), { primary: instance.exports });
    loaded = { slot, ms: performance.now() - t };
  }
};
// Every table slot of a secondary function starts as an imported placeholder named by its
// index. Calling one loads the secondary module, whose element segments overwrite the slots
// with the real functions; the call is then repeated through the table.
const stubs = new Map();
const placeholder = new Proxy({}, {
  get: (_, slot) => {
    if (!stubs.has(slot)) {
      const stub = (...a) => {
        loadSecondary(slot);
        return deferred.get(Number(slot))(...a);
      };
      stubs.set(slot, stub);
    }
    return stubs.get(slot);
  },
});
instance = new WebAssembly.Instance(primary, { ...wasi.getImportObject(), 'placeholder.deferred': placeholder });
// wasm-split keeps the placeholders in a table of their own, added after the program's.
const deferred = Object.values(instance.exports).filter((e) => e instanceof WebAssembly.Table).at(-1);
const code = wasi.start(instance);
console.error(loaded ? `[secondary loaded at slot ${loaded.slot} in ${loaded.ms.toFixed(0)} ms]` : '[primary only]');
process.exit(code);

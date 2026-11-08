// Run one rustc.wasm invocation and report where its WASI time goes: call counts, time
// and bytes per import, plus (with --files) every path the compiler opened or stat'ed.
// Useful for questions like "how much metadata does a hello-world compile read?"
//
// usage: node wasi-prof.mjs [--files] --sysroot DIR --work DIR rustc.wasm -- <rustc args>
//   paths inside rustc args are guest paths: /sysroot/... and /work/...
import fs from 'node:fs';
import { WASI } from 'node:wasi';
import { parseArgs } from 'node:util';

process.removeAllListeners('warning');

const { values: opt, positionals } = parseArgs({
  allowPositionals: true,
  options: { sysroot: { type: 'string' }, work: { type: 'string' }, files: { type: 'boolean', default: false } },
});
const [file, ...args] = positionals;
const wasi = new WASI({ version: 'preview1', args: ['rustc', ...args], env: {},
  preopens: { '/sysroot': opt.sysroot, '/work': opt.work }, returnOnExit: true });
const mod = await WebAssembly.compile(fs.readFileSync(file));

let mem;
const stats = {};
const paths = new Set();
const imports = {};
for (const [name, f] of Object.entries(wasi.wasiImport)) {
  imports[name] = (...a) => {
    if (name === 'path_open' || name === 'path_filestat_get') {
      // path_open(fd, dirflags, path, len, ...) / path_filestat_get(fd, flags, path, len, buf)
      paths.add(Buffer.from(mem.buffer, a[2], a[3]).toString());
    }
    const t0 = performance.now();
    const r = f(...a);
    const s = (stats[name] ??= { calls: 0, ms: 0, bytes: 0 });
    s.calls++;
    s.ms += performance.now() - t0;
    if (name === 'fd_read') s.bytes += new DataView(mem.buffer).getUint32(a[3], true);
    if (name === 'fd_pread') s.bytes += new DataView(mem.buffer).getUint32(a[4], true);
    return r;
  };
}
const inst = new WebAssembly.Instance(mod, { wasi_snapshot_preview1: imports });
mem = inst.exports.memory;
const t0 = performance.now();
const code = wasi.start(inst);
console.log(`exit ${code}, ${(performance.now() - t0).toFixed(0)} ms, linear memory ${(mem.buffer.byteLength / 2 ** 20).toFixed(0)} MiB`);
for (const [name, s] of Object.entries(stats).sort((a, b) => b[1].ms - a[1].ms)) {
  console.log(`  ${name.padEnd(22)} ${String(s.calls).padStart(6)} calls ${s.ms.toFixed(1).padStart(8)} ms` +
    (s.bytes ? ` ${(s.bytes / 2 ** 20).toFixed(1).padStart(7)} MiB` : ''));
}
if (opt.files) console.log([...paths].sort().join('\n'));

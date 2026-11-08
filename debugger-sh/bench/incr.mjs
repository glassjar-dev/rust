// Edit-compile loop: does keeping rustc's incremental cache between runs help?
// Compiles prog.rs once, then applies N small edits (changing a string literal in one
// function), recompiling after each. Compares no-incremental vs -Cincremental with
// various codegen-unit counts. Debug mode (-g -Copt-level=0), like the engine default.
//
// usage: node incr.mjs --rustc rustc.wasm --sysroot DIR [--edits N] [--variants none:1,incr:16] prog.rs
//
// NOTE: rustc.wasm needs a WASI file-lock implementation for -Cincremental; the current
// build fails with "file locks not supported on this platform" (see
// compiler/rustc_data_structures/src/flock/unsupported.rs). Use --variants none:1 until then.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { WASI } from 'node:wasi';
import { parseArgs } from 'node:util';

process.removeAllListeners('warning');

const { values: opt, positionals: [prog] } = parseArgs({
  allowPositionals: true,
  options: { rustc: { type: 'string' }, sysroot: { type: 'string' }, edits: { type: 'string', default: '3' },
    variants: { type: 'string', default: 'none:1,incr:1,incr:16,incr:64' } },
});
const tmpBase = process.env.BENCH_TMP || os.tmpdir();
const wrap = (o) => Object.fromEntries(Object.entries(o).map(([k, f]) => [k, (...a) => f(...a)]));
const mod = await WebAssembly.compile(fs.readFileSync(opt.rustc));

function rustc(args, preopens) {
  const errF = path.join(tmpBase, `err-${process.pid}`);
  const err = fs.openSync(errF, 'w');
  const wasi = new WASI({ version: 'preview1', args: ['rustc', ...args], env: {}, preopens, stderr: err, returnOnExit: true });
  const t0 = performance.now();
  const code = wasi.start(new WebAssembly.Instance(mod, { wasi_snapshot_preview1: wrap(wasi.wasiImport) }));
  const ms = performance.now() - t0;
  fs.closeSync(err);
  if (code !== 0) throw new Error(fs.readFileSync(errF, 'utf8'));
  return ms;
}

// warm up V8 tiering so the first variant isn't penalised
{ const w = fs.mkdtempSync(path.join(tmpBase, 'warm-')); fs.copyFileSync(prog, path.join(w, 'p.rs'));
  for (let i = 0; i < 2; i++) rustc(['/work/p.rs', '--sysroot', '/sysroot', '--target', 'wasm32-wasip1', '--emit=obj', '-o', '/work/p.o'], { '/sysroot': opt.sysroot, '/work': w });
  fs.rmSync(w, { recursive: true }); }

const src = fs.readFileSync(prog, 'utf8');
// Each edit changes one string literal in one function; that's the typical playground edit.
const edit = (n) => src.replace('"circle".into()', `"circle${n}".into()`);

for (const v of opt.variants.split(',')) {
  const [mode, cgu] = v.split(':');
  const work = fs.mkdtempSync(path.join(tmpBase, 'incr-'));
  const preopens = { '/sysroot': opt.sysroot, '/work': work };
  const args = ['/work/p.rs', '--sysroot', '/sysroot', '--target', 'wasm32-wasip1', '-Cpanic=abort',
    `-Ccodegen-units=${cgu}`, '-Zthreads=1', '--emit=obj', '-o', '/work/p.o', '-g', '-Copt-level=0'];
  if (mode === 'incr') args.push('-Cincremental=/work/incr');
  const times = [];
  for (let n = 0; n <= Number(opt.edits); n++) {
    fs.writeFileSync(path.join(work, 'p.rs'), edit(n));
    times.push(rustc(args, preopens));
  }
  const objs = fs.readdirSync(work).filter(f => f.endsWith('.o')).length;
  const incrBytes = mode === 'incr' ? [...walk(path.join(work, 'incr'))].reduce((a, f) => a + fs.statSync(f).size, 0) : 0;
  console.log(`${v.padEnd(9)} first ${times[0].toFixed(0).padStart(5)} ms  edits ${times.slice(1).map(t => t.toFixed(0)).join(' / ')} ms` +
    `  (objs ${objs}, cache ${(incrBytes / 2 ** 20).toFixed(1)} MiB)`);
  fs.rmSync(work, { recursive: true, force: true });
}

function* walk(d) { for (const e of fs.readdirSync(d, { withFileTypes: true })) {
  const p = path.join(d, e.name); if (e.isDirectory()) yield* walk(p); else yield p; } }

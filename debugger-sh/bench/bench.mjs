// Benchmark the glassjar Rust pipeline (rustc.wasm -> wasm-ld -> run) under Node's WASI.
// Node runs wasm on V8, the same engine as Chrome, and the flags below mirror
// `start_rust` in glassjar-dev/engine (src/worker/mod.rs).
//
// usage:
//   node bench.mjs --rustc rustc.wasm --sysroot DIR [--ld llvm.core.wasm]
//                  [--iters N] [--debug] [--time-passes] [--extra "-Zflag ..."]
//                  [--json out.json] prog.rs...
//
// Without --ld only rustc is timed. Iteration #0 of the first program includes V8's lazy
// compilation of rustc.wasm (a cold start); later iterations reuse the compiled module with
// a fresh instance each time, like the engine's retained worker.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { WASI } from 'node:wasi';
import { parseArgs } from 'node:util';

process.removeAllListeners('warning'); // "WASI is experimental"

const { values: opt, positionals: progs } = parseArgs({
  allowPositionals: true,
  options: {
    rustc: { type: 'string' }, ld: { type: 'string' }, sysroot: { type: 'string' },
    iters: { type: 'string', default: '3' }, debug: { type: 'boolean', default: false },
    'time-passes': { type: 'boolean', default: false }, json: { type: 'string' },
    extra: { type: 'string', default: '' },
  },
});
if (!opt.rustc || !opt.sysroot || progs.length === 0) {
  console.error('usage: node bench.mjs --rustc rustc.wasm --sysroot DIR [--ld llvm.core.wasm] prog.rs...');
  process.exit(2);
}
const iters = Number(opt.iters);
const now = () => performance.now();
const tmpBase = process.env.BENCH_TMP || os.tmpdir();

async function compileModule(file) {
  const bytes = fs.readFileSync(file);
  const t0 = now();
  const mod = await WebAssembly.compile(bytes);
  return { mod, ms: now() - t0, bytes: bytes.length };
}

// Node segfaults when WASI imports are passed straight through (its fast-call path);
// wrapping them in JS functions avoids that and matches the browser, where imports are JS.
const wrap = (o) => Object.fromEntries(Object.entries(o).map(([k, f]) => [k, (...a) => f(...a)]));

function runWasi(mod, args, preopens) {
  const tmp = fs.mkdtempSync(path.join(tmpBase, 'wasi-'));
  const outF = path.join(tmp, 'out'), errF = path.join(tmp, 'err');
  const out = fs.openSync(outF, 'w'), err = fs.openSync(errF, 'w');
  const wasi = new WASI({ version: 'preview1', args, env: {}, preopens, stdout: out, stderr: err, returnOnExit: true });
  const t0 = now();
  let code;
  try {
    code = wasi.start(new WebAssembly.Instance(mod, { wasi_snapshot_preview1: wrap(wasi.wasiImport) }));
  } catch (e) {
    code = `trap: ${e.message}`;
  }
  const ms = now() - t0;
  fs.closeSync(out); fs.closeSync(err);
  const res = { code, ms, stdout: fs.readFileSync(outF, 'utf8'), stderr: fs.readFileSync(errF, 'utf8') };
  fs.rmSync(tmp, { recursive: true, force: true });
  return res;
}

const rustc = await compileModule(opt.rustc);
const ld = opt.ld ? await compileModule(opt.ld) : null;
console.error(`module compile: rustc ${rustc.ms.toFixed(0)} ms (${(rustc.bytes / 2 ** 20).toFixed(1)} MiB)` +
  (ld ? `, ld ${ld.ms.toFixed(0)} ms (${(ld.bytes / 2 ** 20).toFixed(1)} MiB)` : ''));

// Same rlib set as find_rust_rlibs in the engine.
const rlibPrefixes = ['libpanic_abort-', 'libstd-', 'libwasi-', 'libcfg_if-', 'librustc_demangle-', 'libstd_detect-',
  'libhashbrown-', 'librustc_std_workspace_alloc-', 'libminiz_oxide-', 'libadler2-', 'libunwind-', 'liblibc-',
  'librustc_std_workspace_core-', 'liballoc-', 'libcore-', 'libcompiler_builtins-'];
const libDir = path.join(opt.sysroot, 'lib/rustlib/wasm32-wasip1/lib');
const rlibs = fs.readdirSync(libDir).filter(f => f.endsWith('.rlib') && rlibPrefixes.some(p => f.startsWith(p)))
  .map(f => `/sysroot/lib/rustlib/wasm32-wasip1/lib/${f}`);

const results = [];
for (const prog of progs) {
  const name = path.basename(prog, '.rs');
  for (let i = 0; i < iters; i++) {
    const work = fs.mkdtempSync(path.join(tmpBase, 'work-'));
    fs.copyFileSync(prog, path.join(work, `${name}.rs`));
    const preopens = { '/sysroot': opt.sysroot, '/work': work };
    const args = ['rustc', `/work/${name}.rs`, '--sysroot', '/sysroot', '--target', 'wasm32-wasip1',
      '-Cpanic=abort', '-Ccodegen-units=1', '-Zthreads=1', '--emit=obj', '-o', `/work/${name}.o`];
    if (opt.debug) args.push('-g', '-Copt-level=0');
    if (opt['time-passes']) args.push('-Ztime-passes');
    if (opt.extra) args.push(...opt.extra.split(' ').filter(Boolean));
    const rc = runWasi(rustc.mod, args, preopens);
    if (rc.code !== 0) { console.error(rc.stderr); throw new Error(`rustc failed on ${name}: ${rc.code}`); }
    const row = { prog: name, iter: i, rustcMs: rc.ms };
    if (opt['time-passes'] && i === iters - 1) row.timePasses = rc.stderr;
    if (ld) {
      const objs = fs.readdirSync(work).filter(f => f.endsWith('.o')).map(f => `/work/${f}`);
      const largs = ['wasm-ld', '--export=__main_void', '-z', 'stack-size=1048576', '--stack-first', '--no-demangle',
        '/sysroot/lib/rustlib/wasm32-wasip1/lib/self-contained/crt1-command.o', ...objs, ...rlibs,
        '-L/sysroot/lib/rustlib/wasm32-wasip1/lib/self-contained', '-lc', '-o', '/work/main.wasm', '--gc-sections', '-O0'];
      const lr = runWasi(ld.mod, largs, preopens);
      if (lr.code !== 0) { console.error(lr.stderr); throw new Error(`wasm-ld failed on ${name}`); }
      row.ldMs = lr.ms;
      const main = await WebAssembly.compile(fs.readFileSync(path.join(work, 'main.wasm')));
      const pr = runWasi(main, ['main'], {});
      row.run = pr.code === 0 ? 'ok' : String(pr.code);
      row.stdoutHead = pr.stdout.split('\n')[0];
    }
    fs.rmSync(work, { recursive: true, force: true });
    results.push(row);
    console.error(`${name.padEnd(8)} #${i} rustc ${row.rustcMs.toFixed(0).padStart(6)} ms` +
      (ld ? `  ld ${row.ldMs.toFixed(0).padStart(5)} ms  run ${row.run} (${row.stdoutHead})` : ''));
  }
}

const median = (xs) => { const s = [...xs].sort((a, b) => a - b); return s[s.length >> 1]; };
console.error('\nmedian of warm iterations (#1..):');
for (const prog of [...new Set(results.map(r => r.prog))]) {
  const warm = results.filter(r => r.prog === prog && r.iter > 0);
  if (warm.length) console.error(`  ${prog.padEnd(8)} rustc ${median(warm.map(r => r.rustcMs)).toFixed(0)} ms` +
    (ld ? `  ld ${median(warm.map(r => r.ldMs)).toFixed(0)} ms` : ''));
}
if (opt.json) fs.writeFileSync(opt.json, JSON.stringify({ rustc: opt.rustc, rustcModuleMs: rustc.ms, rustcBytes: rustc.bytes, results }, null, 1));
for (const r of results) if (r.timePasses) console.log(`--- time-passes ${r.prog} ---\n${r.timePasses}`);

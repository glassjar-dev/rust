// Runs an instrumented rustc.wasm (wasm-split --instrument) over the corpus the way glassjar
// does (run, debug and the IDE's check) and writes one profile per run.
//   node profile.mjs <instr.wasm> <sysroot dir> <corpus dir> <out dir>
import { readFileSync, writeFileSync, mkdirSync, readdirSync, copyFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { WASI } from 'node:wasi';
const [wasm, sysroot, corpus, out] = process.argv.slice(2);
const module = new WebAssembly.Module(readFileSync(wasm));
mkdirSync(out, { recursive: true });
const base = ['rustc', '/work/main.rs', '--edition=2024', '--sysroot', '/', '--target', 'wasm32-wasip1'];
const modes = {
  run: ['-Ccodegen-units=1', '-Clink-arg=--export=__main_void', '-o', '/work/main.wasm'],
  debug: ['-Ccodegen-units=1', '-Clink-arg=--export=__main_void', '-o', '/work/main.wasm', '-g'],
  check: ['-Zthreads=1', '--emit=metadata', '-o', '/work/main.rmeta', '--error-format=json', '--crate-type', 'bin'],
};
for (const file of readdirSync(corpus).filter((f) => f.endsWith('.rs'))) {
  for (const [mode, extra] of Object.entries(modes)) {
    const work = join(out, 'work');
    rmSync(work, { recursive: true, force: true }); mkdirSync(work);
    copyFileSync(join(corpus, file), join(work, 'main.rs'));
    const wasi = new WASI({ version: 'preview1', args: [...base, ...extra], preopens: { '/': sysroot, '/work': work }, returnOnExit: true, stdout: 2 });
    const instance = new WebAssembly.Instance(module, wasi.getImportObject());
    let code;
    try { code = wasi.start(instance); } catch (e) { code = `trap ${e.message}`; }
    const { memory, __write_profile } = instance.exports;
    const size = 4 << 20, addr = memory.grow(size >> 16) << 16;
    const written = __write_profile(addr, size);
    if (written > size) throw new Error('profile buffer too small');
    writeFileSync(join(out, `${file}.${mode}.prof`), new Uint8Array(memory.buffer, addr, written));
    console.error(`${file} ${mode}: exit ${code}, profile ${written} bytes`);
    rmSync(work, { recursive: true, force: true });
  }
}

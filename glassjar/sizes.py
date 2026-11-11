#!/usr/bin/env python3
"""Where rustc.wasm's code goes, by crate, in a build that kept its names.

    glassjar/sizes.py <named rustc.wasm> [regex ...]

With no regex: code size per crate (Rust) or library (C/C++), then the largest functions.
With regexes: the total and the largest functions matching each.
"""
import re, subprocess, sys

d = open(sys.argv[1], 'rb').read()

def leb(i):
    r = s = 0
    while True:
        b = d[i]; i += 1; r |= (b & 0x7f) << s; s += 7
        if b < 0x80: return r, i

i = 8; nimp = 0; sizes = []; names = {}; sections = []
while i < len(d):
    sid = d[i]; n, j = leb(i + 1); end = j + n
    label = {1: 'type', 2: 'import', 3: 'function', 4: 'table', 6: 'global', 7: 'export', 9: 'element', 10: 'code', 11: 'data'}.get(sid, str(sid))
    if sid == 2:
        c, k = leb(j)
        for _ in range(c):
            l, k = leb(k); k += l; l, k = leb(k); k += l; kind = d[k]; k += 1
            if kind == 0: _, k = leb(k); nimp += 1
            elif kind == 1: k += 1; f, k = leb(k); _, k = leb(k)
            elif kind == 2:
                f, k = leb(k); _, k = leb(k)
                if f & 1: _, k = leb(k)
            elif kind == 3: k += 2
    elif sid == 10:
        c, k = leb(j)
        for _ in range(c):
            l, k2 = leb(k); sizes.append(l + (k2 - k)); k = k2 + l
    elif sid == 0:
        l, k = leb(j); label = d[k:k + l].decode(); k += l
        if label == 'name':
            while k < end:
                st = d[k]; sl, k = leb(k + 1); se = k + sl
                if st == 1:
                    c, k = leb(k)
                    for _ in range(c):
                        idx, k = leb(k); l, k = leb(k); names[idx] = d[k:k + l].decode('utf8', 'replace'); k += l
                k = se
    sections.append((label, n)); i = end
if not names: sys.exit('no name section: build with rust.strip = false')

def owner(name):
    """The crate of a Rust symbol, or the library of a C/C++ one."""
    # Trait impls and generic instances start with `<`: credit the first crate path inside.
    m = re.match(r'[<&\[(*]*(?:mut |const |dyn |impl |unsafe |extern "C" |fn\()*([A-Za-z_][A-Za-z0-9_]*)::', name)
    if m: return 'llvm' if m.group(1) in ('llvm', 'lld') else m.group(1)
    if 'llvm::' in name or 'lld::' in name or name.startswith(('LLVM', '(anonymous namespace)', 'std::__2', '_GLOBAL__sub_I_')): return 'llvm'
    return '(c / other)'

fns = sorted(((s, names.get(nimp + x, '?')) for x, s in enumerate(sizes)), reverse=True)
total = sum(sizes)
print(f'{len(d) / 1e6:.1f} MB file:', ', '.join(f'{l} {n / 1e6:.1f}' for l, n in sections if n > 2e5))
print(f'{len(sizes)} functions, {total / 1e6:.2f} MB of code')
if len(sys.argv) == 2:
    by = {}
    for s, n in fns:
        o = owner(n); c = by.setdefault(o, [0, 0]); c[0] += s; c[1] += 1
    for o, (s, c) in sorted(by.items(), key=lambda kv: -kv[1][0])[:60]:
        print(f'  {s / 1e6:7.2f} MB {100 * s / total:5.1f}%  {c:6d} fns  {o}')
for pat in sys.argv[2:] or ['']:
    hit = [(s, n) for s, n in fns if re.search(pat, n)]
    sub = sum(s for s, _ in hit)
    if pat: print(f'\n/{pat}/: {len(hit)} functions, {sub / 1e6:.2f} MB ({100 * sub / total:.1f}%)')
    for s, n in hit[:30 if not pat else 15]: print(f'  {s:8d}  {n[:150]}')

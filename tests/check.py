#!/usr/bin/env python3
"""Static checks only; no Android or GPU runtime claimed."""
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
for path in sorted(root.rglob('*.sh')):
    subprocess.run(['bash', '-n', str(path)], check=True)
    print('Bash OK:', path.relative_to(root))
s = (root / 'scripts/build-adreno.sh').read_text()
blocks = re.findall(r"<<'PY'\n(.*?)\nPY", s, re.S)
assert blocks
for i, block in enumerate(blocks):
    compile(block, f'embedded-patcher-{i}', 'exec')
audit = re.search(r"<<'VERIFY_EOF'\n(.*?)\nVERIFY_EOF", s, re.S).group(1)
compile(audit, 'probar-adreno-real', 'exec')
assert s.index('pkg install -y clang') < s.index('clang -O2')
assert 'binutils-is-llvm' not in s
assert 'SKIP_AUDIT' in s
assert 'Modelo {MODEL!r} no registrado' in audit
assert 'TABLA COMPARATIVA FINAL ({MODEL}' in audit
assert 'urllib.error.HTTPError' in audit
print(f'Python OK: {len(blocks)} patchers + auditor; invariantes OK')

"""Transpile the ArkTS min-cut block in EditorMath.ets into plain JS for parity testing."""
import re, sys

P = '/Users/abhi/Desktop/OpenPhotoSuite/entry/src/main/ets/model/EditorMath.ets'
src = open(P).read()
start = src.index('const HEAL_SOURCE_TREE')
end = src.index('const HEAL_POISSON_UNKNOWN')
sec = src[start:end]

# Interfaces are pure types.
sec = re.sub(r'interface (HealCutResult|HealFlowState) \{[^}]*\}', '', sec)

TY = r'(?:number\[\]|Int32Array\[\]|Float64Array|Int32Array|Uint32Array|Uint8Array|HealIndexedQueue|HealCutResult|HealFlowState|number|boolean|void)'

# Drop class field declarations without initialisers.
kept = []
for line in sec.split('\n'):
    st = line.strip()
    if re.match(r'^(?:private\s+)?\w+\s*:\s*' + TY + r'\s*;$', st):
        continue
    kept.append(line)
sec = '\n'.join(kept)
sec = re.sub(r'\bprivate\s+', '', sec)

# Class fields WITH initialisers must become constructor assignments: a JS class
# field runs before the constructor body, which is not how ArkTS orders them.
fields = []
def grab_field(m):
    fields.append(m.group(1))
    return ''
sec = re.sub(r'^\s+(\w+)\s*:\s*' + TY + r'\s*=\s*[^;]+;\s*$', grab_field, sec, flags=re.M)
if fields:
    init = '\n'.join('    this.%s = 0;' % f for f in fields)
    sec = re.sub(r'constructor\(([^)]*)\) \{',
                 lambda m: 'constructor(%s) {\n%s' % (m.group(1), init), sec, count=1)

# Signatures: `name(params): Ret {` and `constructor(params) {`
def fix_sig(m):
    sig = m.group(1)
    name, rest = sig.split('(', 1)
    params = rest.rsplit(')', 1)[0]
    params = re.sub(r':\s*' + TY, '', params)
    return '%s(%s) {' % (name, ' '.join(params.split()))

sec = re.sub(r'([\w]+\s*\((?:[^()]|\([^()]*\))*)\)\s*:\s*(?:' + TY + r'|void)\s*\{', fix_sig, sec, flags=re.S)
sec = re.sub(r'constructor\(((?:[^()]|\([^()]*\))*)\)\s*\{',
             lambda m: 'constructor(%s) {' % ' '.join(re.sub(r':\s*' + TY, '', m.group(1)).split()), sec)
sec = re.sub(r'\)\s*:\s*' + TY + r'\s*,', '),', sec)
sec = re.sub(r'\bas\s+' + TY + r'\b', '', sec)
sec = re.sub(r'(\w+)\s*:\s*' + TY + r'(\s*=[^=])', r'\1\2', sec)
sec = re.sub(r'new Array<number>\(\)', '[]', sec)
sec = sec.replace('export function', 'function').replace('export class', 'class')

open('/tmp/mc-mirror.mjs', 'w').write(sec + '\nexport { healMinCut };\n')
print('mirror lines', sec.count('\n'))

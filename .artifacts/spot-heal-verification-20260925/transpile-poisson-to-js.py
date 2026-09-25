import re
P = '/Users/abhi/Desktop/OpenPhotoSuite/entry/src/main/ets/model/EditorMath.ets'
src = open(P).read()
start = src.index('const HEAL_POISSON_UNKNOWN')
end = src.index('/**\n * Vote for the single strongest translation offset.')
sec = src[start:end]

TY = r'(?:number\[\]|Int16Array|Int32Array|Uint8Array|Float64Array|HealSparseMatrix|number|boolean|void)'

# Drop class field declarations: lines that are only `name: type` or `name = []`.
out = []
for line in sec.split('\n'):
    stripped = line.strip()
    if re.match(r'^(?:private\s+)?\w+\s*:\s*' + TY + r'\s*;$', stripped):
        continue
    # Keep `name: Type = [];` initialisers: only the type is stripped later.
    if re.match(r'^(?:private\s+)?\w+\s*:\s*' + TY + r'\s*=\s', stripped):
        out.append(re.sub(r':\s*' + TY + r'(\s*=)', r'\1', line))
        continue
    out.append(line)
sec = '\n'.join(out)
sec = re.sub(r'\bprivate\s+', '', sec)

# Return type on any signature, including multi-line parameter lists.
sec = re.sub(r'\)\s*:\s*' + TY + r'\s*,', '),', sec)
sec = re.sub(r'\)\s*:\s*void\s*\{', ') {', sec)
sec = re.sub(r'\)\s*:\s*void\s*\{', ') {', sec)
# Parameter annotations: `: Type name` and `name: Type` inside parameter lists.
sec = re.sub(r'(\(|,)\s*(\w+)\s*:\s*' + TY, r'\1\2', sec)
sec = re.sub(r'\bas\s+' + TY + r'\b', '', sec)
sec = re.sub(r'(\w+)\s*:\s*' + TY + r'(\s*=)', r'\1\2', sec)
sec = re.sub(r'new Array<number>\(\)', '[]', sec)
sec = sec.replace('export function', 'function').replace('export class', 'class')

open('/tmp/poisson-mirror.mjs', 'w').write(sec + '\nexport { healPoissonBlend };\n')
print('mirror lines', sec.count('\n'))

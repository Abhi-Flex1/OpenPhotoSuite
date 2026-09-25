import re
P = '/Users/abhi/Desktop/OpenPhotoSuite/entry/src/main/ets/model/EditorMath.ets'
src = open(P).read()
start = src.index('/**\n * Content-aware healing')
end = src.index('export function floodFillMask')
sec = src[start:end]

# Drop interface declarations (pure types, no runtime behaviour).
for pat in (r'export interface HealOffset \{[^}]*\}\n',
            r'interface HealBounds \{[^}]*\}\n',
            r'export interface HealPatch \{[^}]*\}\n',
            r'export interface HealPlan \{[^}]*\}\n'):
    sec = re.sub(pat, '', sec)

SIMPLE = r'(?:number|boolean|void|number\[\]|Int16Array|Int32Array|Uint8Array|Float64Array|HealOffset|HealBounds|HealPatch|HealPlan)'
ARR    = r'(?:number\[\]|Int16Array\[\]|Int32Array\[\]|Uint8Array\[\]|Float64Array\[\]|HealPatch\[\]|HealPlan\[\])'
BASE   = r'(?:number|boolean|void|Int16Array|Int32Array|Uint8Array|Float64Array|HealOffset|HealBounds|HealPatch|HealPlan)'
UNION  = r'(?:' + BASE + r'(?:\s*\|\s*(?:' + BASE + r'|undefined))*)'
TYPE   = r'(?:' + ARR + r'|' + UNION + r')'

def fix_sig(m):
    name, params = m.group(1), m.group(2)
    params = re.sub(r':\s*' + TYPE, '', params)
    return 'function %s(%s) {' % (name, ' '.join(params.split()))

# Function signatures, possibly spanning lines.
sec = re.sub(r'function (\w+)\(((?:[^()]|\([^()]*\))*)\)\s*:\s*' + UNION + r'\s*\{',
             fix_sig, sec, flags=re.S)
# Typed local variable declarations.
sec = re.sub(r'(\w+)\s*:\s*' + TYPE + r'(\s*)=', r'\1 =', sec)
# `as` casts and generic array constructors.
sec = re.sub(r'\bas\s+' + SIMPLE + r'\b', '', sec)
sec = re.sub(r'\((\w+):\s*' + TYPE + r',\s*(\w+):\s*' + TYPE + r'\):\s*' + UNION + r'\s*=>', r'(\1, \2) =>', sec)
sec = sec.replace('new Array<number>()', '[]')
sec = sec.replace('export function', 'function')

open('/tmp/heal-ets-mirror.mjs', 'w').write(
    sec + '\nexport { rgbaToYcbcr, fwht64, healVotedOffset, healPatchPlan, applyHealPlan };\n')
print('mirror lines', sec.count('\n'))

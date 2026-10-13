import glob
import re

skills = [
    'barricade', 'toughness', 'reinforced_armor', 'fortitude', 'overbear', 'smite',
    'critical_shot', 'dodge', 'survival', 'quick_draw', 'bleed', 'penetrate',
    'devastation', 'searing_flames', 'ignite'
]

gd_files = glob.glob('game/**/*.gd', recursive=True)

findings = {s: [] for s in skills}

for s in skills:
    pat = re.compile(rf'["\']{s}["\']')
    for f in gd_files:
        content = open(f, encoding='utf-8').read()
        matches = pat.findall(content)
        if matches:
            lines = []
            for i, line in enumerate(content.splitlines(), 1):
                if pat.search(line):
                    lines.append((i, line.strip()))
            findings[s].append((f, lines))

print("=" * 80)
print("PASSIVE SKILL GAMEPLAY CONSUMER AUDIT (15 Skills across 6 Suites)")
print("=" * 80)
for s in skills:
    print(f"\nSkill: {s}")
    files = findings[s]
    runtime_consumers = []
    test_consumers = []
    data_consumers = []
    for f, lines in files:
        f_norm = f.replace('\\', '/')
        if 'test' in f_norm:
            test_consumers.append((f_norm, lines))
        elif 'data' in f_norm or 'ui' in f_norm:
            data_consumers.append((f_norm, lines))
        else:
            runtime_consumers.append((f_norm, lines))

    print(f"  Runtime Consumers ({len(runtime_consumers)}):")
    for f, lines in runtime_consumers:
        print(f"    - {f}:")
        for lno, text in lines[:3]:
            print(f"        L{lno}: {text}")
    print(f"  UI/Data Files: {len(data_consumers)} | Tests: {len(test_consumers)}")

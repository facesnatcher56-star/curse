import glob
import re

curse_passives = [
    'alacrity', 'arcane_fury', 'barricade', 'biting_arrow', 'bleed', 'brilliance',
    'critical_shot', 'critical_strike', 'cunning_renewal', 'deadly_strike', 'devastation',
    'dodge', 'far_shot', 'fierce_renewal', 'fortitude', 'ignite', 'mortal_wound',
    'overbear', 'penetrate', 'quick_draw', 'quickened_casting', 'rebuke', 'reinforced_armor',
    'ricochet', 'searing_flames', 'smite', 'survival', 'toughness'
]

gd_files = glob.glob('game/**/*.gd', recursive=True)

findings = {s: [] for s in curse_passives}

for s in curse_passives:
    pat = re.compile(rf'["\']{s}["\']')
    for f in gd_files:
        content = open(f, encoding='utf-8').read()
        matches = pat.findall(content)
        if matches:
            lines = []
            for i, line in enumerate(content.splitlines(), 1):
                if pat.search(line):
                    lines.append((i, line.strip()))
            findings[s].append((f.replace('\\', '/'), lines))

print("=" * 80)
print("ALL 28 CURSE PASSIVES - RUNTIME GAMEPLAY IMPLEMENTATION STATUS")
print("=" * 80)

wired_passives = []
dormant_passives = []

for s in sorted(curse_passives):
    files = findings[s]
    runtime_consumers = []
    for f, lines in files:
        if 'test' in f or 'data/' in f or 'ui/' in f:
            continue
        runtime_consumers.append((f, lines))

    if runtime_consumers:
        wired_passives.append(s)
        print(f"ACTIVE   | {s:20} | {len(runtime_consumers)} runtime files:")
        for f, lines in runtime_consumers:
            print(f"           -> {f}:{lines[0][0]} ({lines[0][1]})")
    else:
        dormant_passives.append(s)
        print(f"DORMANT  | {s:20} | 0 runtime consumers (resource def only)")

print("\n" + "=" * 80)
print(f"Summary: {len(wired_passives)} Active / Wired Passives | {len(dormant_passives)} Dormant Passives")
print("=" * 80)

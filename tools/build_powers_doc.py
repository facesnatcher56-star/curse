import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from extract_power_stats import powers

doc = []
doc.append('# Dungeon Siege II: Powers (Active Skills) Complete Reference\n')
doc.append('Extracted directly from installed game data (`active_skills.gas`, `Logic.ds2res`).\n')
doc.append('Complete numerical baseline for Phase 6 combat powers, weapon stances, recharge formulas, area radii, duration, and exact scaling across all ranks.\n\n---\n')

doc.append('## 1. Power Recharge Mechanics\n')
doc.append('Active skills in DS2 do not cost mana and do not have timed cooldowns. Instead, they recharge via **Damage Dealt in Combat** by the active party.\n')
doc.append('```text')
doc.append('reload_damage = SECONDS * (6 + 1.5 * character_level) * (1 + 0.022 * character_level) * active_party_members')
doc.append('```\n')
doc.append('Recharge durations by tier:\n')
doc.append('* **Very Fast Recharge**: 12 seconds of party combat damage\n')
doc.append('* **Fast Recharge**: 21 seconds of party combat damage\n')
doc.append('* **Medium Recharge**: 35 seconds of party combat damage\n')
doc.append('* **Long Recharge**: 60 seconds of party combat damage\n\n---\n')

type_map = {
    'melee': 'Melee (Fighter)',
    'ranged': 'Ranged (Archer)',
    'combat': 'Combat Magic',
    'nature': 'Nature Magic'
}

# Group Hero Powers by class
for t_key, t_title in type_map.items():
    doc.append(f'## {t_title} Powers\n')
    t_powers = [p for p in powers if p['type'] == t_key and p['max_level'] > 1]
    for p in t_powers:
        doc.append(f"### {p['screen_name']} (`{p['id']}`)")
        doc.append(f"* **Summary**: {p['summary'].replace(chr(10), ' ')}")
        doc.append(f"* **Max Ranks**: {p['max_level']}")
        doc.append(f"* **Stances Required**: `{p['stances']}`")
        doc.append(f"* **Target Type**: `{p['target']}`")
        doc.append(f"* **Cast / Charge Time**: {p['charge_time']}s")
        doc.append(f"* **Recharge Formula**: `{p['reload_formula']}`")
        doc.append("* **Unlock Requirements**:")
        for rk, rv in p['requirements'].items():
            req_str = ', '.join([f"{k}: {v}" for k, v in rv.items()])
            doc.append(f"  * **{rk}**: {req_str}")
        doc.append("* **Rank Scaling (All Parameters Across Ranks 1, 2, 3)**:")
        for vk, vv in p['skill_values'].items():
            doc.append(f"  * `{vk}`:")
            for r in range(1, p['max_level'] + 1):
                lk = f"level_{r}"
                val = vv.get(lk, "N/A")
                doc.append(f"    * **Rank {r} ({lk})**: `{val}`")
        doc.append('\n')
    doc.append('---\n')

# Pet Powers section
doc.append('## Pet & Summon Powers (1 Rank Each)\n')
pet_powers = [p for p in powers if p['max_level'] == 1]
for p in pet_powers:
    doc.append(f"### {p['screen_name']} (`{p['id']}`)")
    doc.append(f"* **Class Type**: {p['type']}")
    doc.append(f"* **Target Type**: `{p['target']}`")
    doc.append(f"* **Recharge Formula**: `{p['reload_formula']}`")
    doc.append("* **Values**:")
    for vk, vv in p['skill_values'].items():
        doc.append(f"  * `{vk}`: `{vv.get('level_1', 'N/A')}`")
    doc.append('\n')

full_text = '\n'.join(doc)

out1 = r'c:\Users\lloyd\OneDrive\Documents\curse\docs\ds2_powers_reference.md'
out2 = r'C:\Users\lloyd\OneDrive\Documents\curse-claude\docs\ds2_powers_reference.md'

with open(out1, 'w', encoding='utf-8') as f:
    f.write(full_text)
print('Wrote to', out1, f'({len(full_text):,} bytes)')

with open(out2, 'w', encoding='utf-8') as f:
    f.write(full_text)
print('Wrote to', out2, f'({len(full_text):,} bytes)')

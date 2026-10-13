import json
import glob
import os
import re

# 1. Load Curse passives
curse_passives = {}
for path in sorted(glob.glob('data/passives/*.tres')):
    pid = os.path.splitext(os.path.basename(path))[0]
    content = open(path, encoding='utf-8').read()
    tree = re.search(r'tree = "([^"]+)"', content)
    disp = re.search(r'display_name = "([^"]+)"', content)
    tier = re.search(r'tier = (\d+)', content)
    curse_passives[pid] = {
        'id': pid,
        'tree': tree.group(1) if tree else '',
        'display_name': disp.group(1) if disp else pid,
        'tier': int(tier.group(1)) if tier else 0,
        'path': path
    }

print("=" * 80)
print(f"CURSE IMPLEMENTED PASSIVES: {len(curse_passives)}")
print("=" * 80)
for pid, p in sorted(curse_passives.items(), key=lambda x: (x[1]['tree'], x[1]['tier'], x[0])):
    print(f"  [{p['tree']:7}] Tier {p['tier']}: {pid:20} -> {p['display_name']}")

# 2. Parse all 14 DS2 Skill Suites from ds2_equipment_catalog.json
cat = json.load(open('data/reference/ds2_equipment_catalog.json', encoding='utf-8'))

# Map suite id to list of skill names from descriptions
suite_info = {}
for it in cat.get('items', []) + cat.get('affixes', []):
    for eff in it.get('effects', []):
        if eff.get('alteration') == 'alter_skill_suite':
            sid = eff.get('suite')
            desc = eff.get('description', '')
            if sid and sid not in suite_info:
                suite_info[sid] = desc

for s in cat.get('sets', []):
    for c, effs in s.get('totals', {}).items():
        for eff in effs:
            if eff.get('alteration') == 'alter_skill_suite':
                sid = eff.get('suite')
                desc = eff.get('description', '')
                if sid and sid not in suite_info:
                    suite_info[sid] = desc

print("\n" + "=" * 80)
print(f"DS2 SKILL SUITES (14 Total):")
print("=" * 80)

# Known canonical DS2 skill name to Curse passive id mapping
# Let's inspect descriptions and map them
canonical_skill_map = {
    # Melee
    'Barricade': 'barricade',
    'Toughness': 'toughness',
    'Reinforced Armor': 'reinforced_armor',
    'Fortitude': 'fortitude',
    'Overbear': 'overbear',
    'Smite': 'smite',
    'Critical Strike': 'critical_strike',
    'Dual Wield': 'dual_wield',
    'Alacrity': 'alacrity',
    'Fierce Renewal': 'fierce_renewal',
    # Ranged
    'Critical Shot': 'critical_shot',
    'Dodge': 'dodge',
    'Survival': 'survival',
    'Biting Arrow': 'biting_arrow',
    'Far Shot': 'far_shot',
    'Shockwave': 'shockwave',
    'Quick Draw': 'quick_draw',
    'Bleed': 'bleed',
    'Penetrate': 'penetrate',
    'Cunning Renewal': 'cunning_renewal',
    'Ricochet': 'ricochet',
    # Combat Magic
    'Debilitation': 'debilitation',
    'Grim Necromancy': 'grim_necromancy',
    'Vampirism': 'vampirism',
    'Brilliance': 'brilliance',
    'Amplified Lightning': 'amplified_lightning',
    'Arcing': 'arcing',
    'Devastation': 'devastation',
    'Searing Flames': 'searing_flames',
    'Ignite': 'ignite',
    'Quickened Casting': 'quickened_casting',
    'Arcane Fury': 'arcane_fury',
    # Nature Magic
    'Summon Fortitude': 'summon_fortitude',
    'Summon Might': 'summon_might',
    'Summon Bond': 'summon_bond',
    'Aquatic Affinity': 'aquatic_affinity',
    'Arctic Mastery': 'arctic_mastery',
    'Freezing': 'freezing',
    'Nurturing Gift': 'nurturing_gift',
    'Enveloping Embrace': 'enveloping_embrace',
    'Feral Wrath': 'feral_wrath',
    'Summon Alacrity': 'summon_alacrity',
}

suites_detail = {}
fully_supported_suites = []

for sid in sorted(suite_info.keys()):
    desc = suite_info[sid]
    # parse skills from desc: e.g. "+<value> to Barricade, Toughness, and Reinforced Armor"
    m = re.sub(r'^\+<value> to ', '', desc)
    # split by comma and/or "and"
    raw_skills = [s.strip().replace('and ', '').strip() for s in re.split(r',|\band\b', m) if s.strip() and s.strip() != 'and']
    # clean up empty or punctuation
    skills = []
    for s in raw_skills:
        s_clean = s.strip()
        if s_clean.startswith('and '): s_clean = s_clean[4:].strip()
        if s_clean: skills.append(s_clean)

    mapped_ids = [canonical_skill_map.get(s, s.lower().replace(' ', '_')) for s in skills]
    curse_status = [mid in curse_passives for mid in mapped_ids]
    all_present = all(curse_status)
    if all_present:
        fully_supported_suites.append(sid)

    suites_detail[sid] = {
        'desc': desc,
        'raw_skills': skills,
        'mapped_ids': mapped_ids,
        'curse_status': curse_status,
        'all_present': all_present
    }

    status_str = "FULLY SUPPORTED IN CURSE (3/3 or 2/2)" if all_present else f"PARTIAL/MISSING ({sum(curse_status)}/{len(curse_status)})"
    print(f"\nSuite: {sid:15} | Status: {status_str}")
    print(f"  Description: {desc}")
    for s_name, mid, present in zip(skills, mapped_ids, curse_status):
        flag = "IN CURSE" if present else "MISSING"
        print(f"    - {s_name:22} -> ID: {mid:20} [{flag}]")

print("\n" + "=" * 80)
print(f"FULLY SUPPORTED SUITES IN CURSE ({len(fully_supported_suites)} Suites):")
print("=" * 80)
for sid in fully_supported_suites:
    print(f"  - {sid:15}: {', '.join(suites_detail[sid]['mapped_ids'])}")

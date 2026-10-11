import re

path_passives = r'C:\Users\lloyd\Desktop\DS2_Reference_Extracted\Extracted\skills_decompressed\passive_skills.gas'
path_actives = r'C:\Users\lloyd\Desktop\DS2_Reference_Extracted\Extracted\skills_decompressed\active_skills.gas'

text_p = open(path_passives, 'r', encoding='latin1').read()
text_a = open(path_actives, 'r', encoding='latin1').read()

def get_child_blocks(text, root_name):
    root_m = re.search(r'\[' + root_name + r'\]\s*\{', text)
    if not root_m:
        return {}
    start_brace = root_m.end() - 1
    
    # find matching brace for root
    depth = 0
    end_brace = -1
    for i in range(start_brace, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                end_brace = i
                break
    inner = text[start_brace+1:end_brace]
    
    # parse top-level blocks inside inner
    blocks = {}
    pos = 0
    while pos < len(inner):
        m = re.search(r'\[([a-zA-Z0-9_]+)\]\s*\{', inner[pos:])
        if not m:
            break
        bname = m.group(1)
        b_start = pos + m.end() - 1
        d = 0
        b_end = -1
        for j in range(b_start, len(inner)):
            if inner[j] == '{':
                d += 1
            elif inner[j] == '}':
                d -= 1
                if d == 0:
                    b_end = j
                    break
        if b_end == -1:
            break
        blocks[bname] = inner[b_start+1:b_end]
        pos = b_end + 1
    return blocks

p_blocks = get_child_blocks(text_p, 'passive_skills')
a_blocks = get_child_blocks(text_a, 'active_skills')

print(f"Properly parsed {len(p_blocks)} passives, {len(a_blocks)} actives.")

def parse_requirements(body):
    req_m = re.search(r'\[skill_requirements_0\]\s*\{([^}]+)\}', body)
    reqs = {}
    if req_m:
        raw = req_m.group(1)
        for item in raw.split(';'):
            item = item.strip()
            if '=' in item:
                k, v = item.split('=')
                try:
                    reqs[k.strip()] = int(v.strip())
                except:
                    reqs[k.strip()] = v.strip()
    return reqs

passives = {}
for name, body in p_blocks.items():
    t_m = re.search(r'type\s*=\s*([a-zA-Z0-9_]+);', body)
    sn_m = re.search(r'screen_name\s*=\s*"([^"]+)";', body)
    desc_m = re.search(r'description\s*=\s*"([^"]+)";', body)
    reqs = parse_requirements(body)
    
    passives[name] = {
        'type': t_m.group(1) if t_m else 'unknown',
        'screen_name': sn_m.group(1) if sn_m else name,
        'description': desc_m.group(1) if desc_m else '',
        'reqs': reqs
    }

actives = {}
for name, body in a_blocks.items():
    t_m = re.search(r'type\s*=\s*([a-zA-Z0-9_]+);', body)
    sn_m = re.search(r'screen_name\s*=\s*"([^"]+)";', body)
    reqs = parse_requirements(body)
    actives[name] = {
        'type': t_m.group(1) if t_m else 'unknown',
        'screen_name': sn_m.group(1) if sn_m else name,
        'reqs': reqs
    }

type_map = {
    'melee': 'MELEE (FIGHTER)',
    'ranged': 'RANGED (ARCHER)',
    'combat': 'COMBAT MAGIC',
    'nature': 'NATURE MAGIC'
}

for t_key, title in type_map.items():
    print("\n" + "=" * 70)
    print(f"=== {title} ===")
    print("=" * 70)
    
    t_passives = {k: v for k, v in passives.items() if v['type'] == t_key}
    t_actives = {k: v for k, v in actives.items() if v['type'] == t_key}
    
    level_key = t_key if t_key in ['melee', 'ranged'] else (t_key + '_magic')
    
    sorted_passives = sorted(t_passives.items(), key=lambda kv: kv[1]['reqs'].get(level_key, 0))
    
    print("\n-- PASSIVES (12 total) --")
    for k, v in sorted_passives:
        lvl = v['reqs'].get(level_key, 0)
        prereqs = {rk: rv for rk, rv in v['reqs'].items() if rk != level_key}
        print(f"Level {lvl:2d} | {v['screen_name']:22s} ({k:20s}) -> Prereqs: {prereqs}")
        
    print("\n-- ACTIVE POWERS --")
    for k, v in t_actives.items():
        print(f"Power: {v['screen_name']:22s} ({k:20s}) -> Requirements: {v['reqs']}")

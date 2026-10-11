import re
import os

path_actives = r'C:\Users\lloyd\Desktop\DS2_Reference_Extracted\Extracted\skills_decompressed\active_skills.gas'
text = open(path_actives, 'r', encoding='latin1').read()

# Parse active_skills blocks
def get_child_blocks(text, root_name):
    root_m = re.search(r'\[' + root_name + r'\]\s*\{', text)
    if not root_m:
        return {}
    start_brace = root_m.end() - 1
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

a_blocks = get_child_blocks(text, 'active_skills')

powers = []

for name, body in a_blocks.items():
    sn_m = re.search(r'screen_name\s*=\s*"([^"]+)";', body)
    t_m = re.search(r'type\s*=\s*([a-zA-Z0-9_]+);', body)
    stances_m = re.search(r'valid_stances\s*=\s*"([^"]+)";', body)
    reload_m = re.search(r'reload_damage_formula\s*=\s*([^;]+);', body)
    charge_m = re.search(r'charge_time\s*=\s*([^;]+);', body)
    target_m = re.search(r'target\s*=\s*([^;]+);', body)
    desc_m = re.search(r'description\s*=\s*"([^"]+)";', body)
    summary_m = re.search(r'summary\s*=\s*"([^"]+)";', body)
    
    # parse skill_values
    skill_values = {}
    sv_m = re.search(r'\[skill_values\]\s*\{', body)
    if sv_m:
        sv_start = sv_m.end() - 1
        d = 0
        sv_end = -1
        for j in range(sv_start, len(body)):
            if body[j] == '{': d += 1
            elif body[j] == '}':
                d -= 1
                if d == 0:
                    sv_end = j
                    break
        sv_inner = body[sv_start+1:sv_end]
        # find sub-blocks
        for sub_m in re.finditer(r'\[([a-zA-Z0-9_]+)\]\s*\{([^}]+)\}', sv_inner):
            sub_name = sub_m.group(1)
            sub_body = sub_m.group(2)
            levels = {}
            for l_item in sub_body.split(';'):
                l_item = l_item.strip()
                if '=' in l_item:
                    k, v = l_item.split('=', 1)
                    levels[k.strip()] = v.strip()
            skill_values[sub_name] = levels

    # parse requirements per rank
    reqs = {}
    for r_idx in range(3):
        r_m = re.search(r'\[skill_requirements_' + str(r_idx) + r'\]\s*\{([^}]+)\}', body)
        if r_m:
            r_dict = {}
            for item in r_m.group(1).split(';'):
                item = item.strip()
                if '=' in item:
                    k, v = item.split('=', 1)
                    k_clean = re.sub(r'//[^\n]*', '', k).strip()
                    r_dict[k_clean] = v.strip()
            reqs[f"Rank_{r_idx+1}"] = r_dict

    powers.append({
        'id': name,
        'screen_name': sn_m.group(1) if sn_m else name,
        'type': t_m.group(1) if t_m else 'unknown',
        'stances': stances_m.group(1) if stances_m else 'Any / None required',
        'reload_formula': reload_m.group(1).strip() if reload_m else 'None',
        'charge_time': charge_m.group(1).strip() if charge_m else '0',
        'target': target_m.group(1).strip() if target_m else 'None',
        'description': desc_m.group(1) if desc_m else '',
        'summary': summary_m.group(1) if summary_m else '',
        'skill_values': skill_values,
        'requirements': reqs
    })

# Group by type
type_order = ['melee', 'ranged', 'combat', 'nature']
for t in type_order:
    print(f"\n==================== {t.upper()} POWERS ====================")
    for p in powers:
        if p['type'] == t:
            print(f"\n--- {p['screen_name']} ({p['id']}) ---")
            print(f"Stances: {p['stances']}")
            print(f"Charge Time: {p['charge_time']}s | Target: {p['target']}")
            print(f"Reload Formula: {p['reload_formula']}")
            print(f"Requirements: {p['requirements']}")
            print(f"Values:")
            for vk, vv in p['skill_values'].items():
                print(f"  {vk}: {vv}")

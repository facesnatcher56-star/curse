import os
import re

path_actives = r'C:\Users\lloyd\Desktop\DS2_Reference_Extracted\Extracted\skills_decompressed\active_skills.gas'
text = open(path_actives, 'r', encoding='latin1').read()


def strip_comments(s):
    s = re.sub(r'/\*[\s\S]*?\*/', '', s)
    s = re.sub(r'//[^\n]*', '', s)
    return s


def get_child_blocks(raw, root):
    m = re.search(r'\[' + root + r'\]\s*\{', raw)
    if not m:
        return {}
    start = m.end() - 1
    d = 0
    end = -1
    for i in range(start, len(raw)):
        if raw[i] == '{':
            d += 1
        elif raw[i] == '}':
            d -= 1
            if d == 0:
                end = i
                break
    inner = raw[start + 1 : end]
    blocks = {}
    pos = 0
    while pos < len(inner):
        bm = re.search(r'\[([a-zA-Z0-9_]+)\]\s*\{', inner[pos:])
        if not bm:
            break
        name = bm.group(1)
        bstart = pos + bm.end() - 1
        bd = 0
        bend = -1
        for j in range(bstart, len(inner)):
            if inner[j] == '{':
                bd += 1
            elif inner[j] == '}':
                bd -= 1
                if bd == 0:
                    bend = j
                    break
        if bend == -1:
            break
        blocks[name] = inner[bstart + 1 : bend]
        pos = bend + 1
    return blocks


powers_raw = get_child_blocks(text, 'active_skills')

powers = []

for name, body in powers_raw.items():
    sn_m = re.search(r'screen_name\s*=\s*"([^"]+)";', body)
    sn = sn_m.group(1) if sn_m else name
    t_m = re.search(r'type\s*=\s*([a-zA-Z0-9_]+);', body)
    stances_m = re.search(r'valid_stances\s*=\s*"([^"]+)";', body)
    reload_m = re.search(r'reload_damage_formula\s*=\s*([^;]+);', body)
    charge_m = re.search(r'charge_time\s*=\s*([^;]+);', body)
    target_m = re.search(r'target\s*=\s*([^;]+);', body)
    desc_m = re.search(r'description\s*=\s*"([^"]+)";', body)
    summary_m = re.search(r'summary\s*=\s*"([^"]+)";', body)
    max_lvl_m = re.search(r'max_level\s*=\s*(\d+);', body)
    max_lvl = int(max_lvl_m.group(1)) if max_lvl_m else 1

    # Clean body for skill_values
    sv_m = re.search(
        r'\[skill_values\]\s*\{([^{}]+(?:\{[^{}]*\}[^{}]*)*)\}', body
    )
    skill_values = {}
    if sv_m:
        sv_clean = strip_comments(sv_m.group(1))
        for sub_name, sub_body in re.findall(
            r'\[([a-zA-Z0-9_]+)\]\s*\{([^}]+)\}', sv_clean
        ):
            levels = {}
            for lk, lv in re.findall(r'(level_\d+)\s*=\s*([^;]+);', sub_body):
                levels[lk] = ' '.join(lv.split())
            skill_values[sub_name] = levels

    # Requirements per rank
    reqs = {}
    for r_idx in range(max_lvl):
        r_m = re.search(
            r'\[skill_requirements_' + str(r_idx) + r'\]\s*\{([^}]+)\}', body
        )
        if r_m:
            r_clean = strip_comments(r_m.group(1))
            r_dict = {}
            for item in r_clean.split(';'):
                item = item.strip()
                if '=' in item:
                    k, v = item.split('=', 1)
                    r_dict[k.strip()] = v.strip()
            reqs[f'Rank_{r_idx+1}'] = r_dict

    powers.append({
        'id': name,
        'screen_name': sn,
        'type': t_m.group(1) if t_m else 'unknown',
        'max_level': max_lvl,
        'stances': stances_m.group(1) if stances_m else 'Any / None required',
        'reload_formula': (
            ' '.join(strip_comments(reload_m.group(1)).split())
            if reload_m
            else 'None'
        ),
        'charge_time': charge_m.group(1).strip() if charge_m else '0',
        'target': target_m.group(1).strip() if target_m else 'None',
        'description': desc_m.group(1) if desc_m else '',
        'summary': summary_m.group(1) if summary_m else '',
        'skill_values': skill_values,
        'requirements': reqs,
    })

if __name__ == '__main__':
    print(f'Total powers parsed: {len(powers)}')
    hero = [p for p in powers if p['max_level'] > 1]
    pets = [p for p in powers if p['max_level'] == 1]
    print(f'Hero powers: {len(hero)} (all 3 ranks)')
    print(f'Pet powers: {len(pets)} (1 rank)')

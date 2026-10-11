import os
import re
import json

GAS_PATH = r"c:\Users\lloyd\OneDrive\Documents\curse\ds2_sourceds2_reference\passive_skills.gas"
if not os.path.exists(GAS_PATH):
    GAS_PATH = r"C:\Users\lloyd\Desktop\DS2_Reference_Extracted\Extracted\skills_decompressed\passive_skills.gas"

with open(GAS_PATH, "r", encoding="utf-8", errors="ignore") as f:
    text = f.read()

text_clean = re.sub(r'/\*[\s\S]*?\*/', '', text)
text_clean = re.sub(r'//[^\n]*', '', text_clean)

def extract_blocks(content):
    blocks = {}
    pattern = re.compile(r'\[([a-zA-Z0-9_]+)\]\s*\{')
    pos = 0
    while True:
        m = pattern.search(content, pos)
        if not m:
            break
        name = m.group(1)
        start = m.end()
        depth = 1
        i = start
        while i < len(content) and depth > 0:
            if content[i] == '{':
                depth += 1
            elif content[i] == '}':
                depth -= 1
            i += 1
        blocks[name] = content[start:i-1]
        pos = i
    return blocks

top_blocks = extract_blocks(text_clean)
skills_container = top_blocks.get("passive_skills", text_clean)
skill_blocks = extract_blocks(skills_container)

target_skills = [
    # Melee
    ("Fortitude", "fortitude"),
    ("Critical Strike", "critical_strike"),
    ("Barricade", "aegis"),
    ("Overbear", "overbear"),
    ("Toughness", "toughness"),
    ("Alacrity", "alacrity"),
    ("Smite", "smite"),
    ("Reinforced Armor", "reinforced_armor"),
    ("Fierce Renewal", "fierce_renewal"),
    ("Rebuke", "rebuke"),
    # Ranged
    ("Critical Shot", "critical_shot"),
    ("Dodge", "dodge"),
    ("Quick Draw", "quick_draw"),
    ("Survival", "survival"),
    ("Bleed", "bleed"),
    # Combat Magic
    ("Brilliance", "brilliance"),
    ("Devastation", "devastation"),
    ("Searing Flames", "searing_flames"),
    ("Quickened Casting", "quickened_casting"),
    ("Ignite", "ignite")
]

doc_lines = []

for display_name, internal_name in target_skills:
    block_body = skill_blocks[internal_name]
    sub_blocks = extract_blocks(block_body)
    
    # get description and screen_name
    desc_m = re.search(r'description\s*=\s*"([^"]+)"', block_body)
    desc = desc_m.group(1) if desc_m else ""
    sn_m = re.search(r'screen_name\s*=\s*"([^"]+)"', block_body)
    screen_name = sn_m.group(1) if sn_m else display_name
    
    doc_lines.append(f"### {screen_name} (`{internal_name}`)")
    if desc:
        doc_lines.append(f"**Description**: {desc}\n")
        
    val_content = sub_blocks.get("skill_values", "")
    val_sub_blocks = extract_blocks(val_content)
    
    for sub_name, sub_body in val_sub_blocks.items():
        doc_lines.append(f"#### `[{sub_name}]`")
        doc_lines.append("```gas")
        doc_lines.append(f"[{sub_name}]")
        doc_lines.append("{")
        
        # parse level_1 .. 20
        levels = {}
        for line in sub_body.split(';'):
            line = line.strip()
            if '=' in line:
                k, v = line.split('=', 1)
                k = k.strip()
                v = v.strip()
                if k.startswith("level_"):
                    try:
                        lvl_num = int(k.replace("level_", ""))
                        levels[lvl_num] = v
                    except ValueError:
                        pass
        
        # format in 4 lines of 5 levels each like DS2 / Deadly Strike
        for row in range(4):
            line_parts = []
            for col in range(1, 6):
                lvl = row * 5 + col
                if lvl in levels:
                    line_parts.append(f"level_{lvl} = {levels[lvl]};")
            if line_parts:
                doc_lines.append("\t" + " ".join(line_parts))
        doc_lines.append("}")
        doc_lines.append("```\n")

full_doc = "\n".join(doc_lines)
with open("docs/ds2_passives_reference.md", "w", encoding="utf-8") as f:
    f.write("# Dungeon Siege II - Passive Skills 20-Rank Tables Reference\n\n" + full_doc)

print("Generated docs/ds2_passives_reference.md successfully!")

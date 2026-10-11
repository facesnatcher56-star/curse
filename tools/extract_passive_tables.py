import os
import re
import json

GAS_PATH = r"c:\Users\lloyd\OneDrive\Documents\curse\ds2_source\ds2_reference\passive_skills.gas"
if not os.path.exists(GAS_PATH):
    GAS_PATH = r"C:\Users\lloyd\Desktop\DS2_Reference_Extracted\Extracted\skills_decompressed\passive_skills.gas"

TARGET_PASSIVES = {
    # Melee
    "Fortitude": "fortitude",
    "Critical Strike": "critical_strike",
    "Barricade": "aegis",
    "Overbear": "overbear",
    "Toughness": "toughness",
    "Alacrity": "alacrity",
    "Smite": "smite",
    "Reinforced Armor": "reinforced_armor",
    "Fierce Renewal": "fierce_renewal",
    "Rebuke": "rebuke",
    # Ranged
    "Critical Shot": "critical_shot",
    "Dodge": "dodge",
    "Quick Draw": "quick_draw",
    "Survival": "survival",
    "Bleed": "bleed",
    # Combat Magic
    "Brilliance": "brilliance",
    "Devastation": "devastation",
    "Searing Flames": "searing_flames",
    "Quickened Casting": "quickened_casting",
    "Ignite": "ignite"
}

with open(GAS_PATH, "r", encoding="utf-8", errors="ignore") as f:
    text = f.read()

# Strip comments
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
        # count braces
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

# If enclosed in [passive_skills]
skills_container = top_blocks.get("passive_skills", text_clean)
skill_blocks = extract_blocks(skills_container)

results = {}

for display_name, internal_name in TARGET_PASSIVES.items():
    if internal_name not in skill_blocks:
        results[display_name] = {"error": f"Internal name '{internal_name}' not found. Available: {list(skill_blocks.keys())[:10]}"}
        continue
    
    skill_content = skill_blocks[internal_name]
    sub_blocks = extract_blocks(skill_content)
    
    if "skill_values" not in sub_blocks:
        results[display_name] = {"error": "No [skill_values] block found"}
        continue
        
    val_content = sub_blocks["skill_values"]
    val_sub_blocks = extract_blocks(val_content)
    
    passive_data = {}
    for sub_name, sub_body in val_sub_blocks.items():
        # extract level_1 through level_20
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
        passive_data[sub_name] = levels
        
    results[display_name] = {
        "internal_name": internal_name,
        "values": passive_data
    }

with open("tools/passive_tables_dump.json", "w", encoding="utf-8") as out:
    json.dump(results, out, indent=2)

print("Extraction complete. Processed keys:", list(results.keys()))
for name, data in results.items():
    if "error" in data:
        print(f"ERROR in {name}: {data['error']}")
    else:
        print(f"SUCCESS: {name} ({data['internal_name']}) -> sub_tables: {list(data['values'].keys())}")

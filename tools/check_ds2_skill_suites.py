#!/usr/bin/env python3
"""
Validation check for DS2 passive skill suites and discipline alterations.
Verifies data/reference/ds2_skill_suites.json against:
  - data/reference/ds2_equipment_catalog.json
  - data/passives/*.tres
"""

import glob
import json
import os
import sys

def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ref_path = os.path.join(root, "data", "reference", "ds2_skill_suites.json")
    cat_path = os.path.join(root, "data", "reference", "ds2_equipment_catalog.json")

    if not os.path.exists(ref_path):
        print(f"ERROR: {ref_path} not found.")
        return 1

    with open(ref_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    with open(cat_path, "r", encoding="utf-8") as f:
        cat = json.load(f)

    # 1. Check basic metadata
    assert data.get("schema") == 1, "Schema must be 1"
    suites = data.get("suites", {})
    assert len(suites) == 14, f"Expected 14 suites, got {len(suites)}"

    # 2. Verify all passives mapped actually exist on disk
    passives_dir = os.path.join(root, "data", "passives")
    existing_passives = {
        os.path.splitext(os.path.basename(p))[0]
        for p in glob.glob(os.path.join(passives_dir, "*.tres"))
    }

    for sid, sinfo in suites.items():
        for detail in sinfo.get("constituent_details", []):
            cid = detail.get("curse_id")
            if cid:
                assert cid in existing_passives, f"Curse passive {cid} not found in {passives_dir}"

    # 3. Check catalog occurrences match
    suite_counts = {s: 0 for s in suites}
    discipline_counts = {
        "ALTER_MELEE_PASSIVE_SKILLS": 0,
        "alter_melee_passive_skills": 0,
        "ALTER_RANGED_PASSIVE_SKILLS": 0,
        "ALTER_COMBAT_MAGIC_PASSIVE_SKILLS": 0,
        "ALTER_NATURE_MAGIC_PASSIVE_SKILLS": 0
    }

    for it in cat.get("items", []):
        for eff in it.get("effects", []):
            alt = eff.get("alteration")
            if alt == "alter_skill_suite":
                sid = eff.get("suite")
                if sid in suite_counts:
                    suite_counts[sid] += 1
            elif alt in discipline_counts:
                discipline_counts[alt] += 1

    for aff in cat.get("affixes", []):
        for eff in aff.get("effects", []):
            alt = eff.get("alteration")
            if alt == "alter_skill_suite":
                sid = eff.get("suite")
                if sid in suite_counts:
                    suite_counts[sid] += 1
            elif alt in discipline_counts:
                discipline_counts[alt] += 1

    for s in cat.get("sets", []):
        for c, effs in s.get("totals", {}).items():
            for eff in effs:
                alt = eff.get("alteration")
                if alt == "alter_skill_suite":
                    sid = eff.get("suite")
                    if sid in suite_counts:
                        suite_counts[sid] += 1
                elif alt in discipline_counts:
                    discipline_counts[alt] += 1

    for sid, count in suite_counts.items():
        ref_count = suites[sid]["occurrences"]["total"]
        assert ref_count == count, f"Occurrence mismatch for {sid}: {ref_count} vs {count}"

    for alt, count in discipline_counts.items():
        ref_count = data["discipline_alterations"][alt]["occurrences"]["total"]
        assert ref_count == count, f"Occurrence mismatch for {alt}: {ref_count} vs {count}"

    total_suites = sum(suite_counts.values())
    total_disciplines = sum(discipline_counts.values())
    total_all = total_suites + total_disciplines
    assert total_suites == 269, f"Expected 269 alter_skill_suite occurrences, got {total_suites}"
    assert total_disciplines == 138, f"Expected 138 discipline alteration occurrences, got {total_disciplines}"
    assert total_all == 407, f"Expected 407 total occurrences, got {total_all}"

    # 4. Check defined vs active suites
    fully_defined = [sid for sid, s in suites.items() if s["definition_status"] == "fully_defined"]
    fully_active = [sid for sid, s in suites.items() if s["gameplay_status"] == "fully_active"]
    assert len(fully_defined) == 6, f"Expected 6 fully defined suites, got {len(fully_defined)}: {fully_defined}"
    assert len(fully_active) == 5, f"Expected 5 fully active suites, got {len(fully_active)}: {fully_active}"

    # Verify the 6 suites are exactly the expected set
    expected_6 = {"melee_suite_1", "melee_suite_2", "ranged_suite_1", "ranged_suite_3", "cmagic_suite_3", "special_suite_2"}
    assert set(fully_defined) == expected_6, f"Defined suites set mismatch: {set(fully_defined)} vs {expected_6}"

    # Verify ranged_suite_3 is the 1 defined but dormant suite
    assert "ranged_suite_3" in fully_defined
    assert "ranged_suite_3" not in fully_active

    print("SUCCESS: DS2 Passive Skill Suites reference is 100% verified.")
    print(f"  Total catalog occurrences: {total_all}")
    print(f"    - alter_skill_suite: {total_suites} across 14 suites")
    print(f"    - discipline passives: {total_disciplines} across 5 alterations")
    print(f"  Fully defined suites in Curse: {len(fully_defined)}/14 ({', '.join(sorted(fully_defined))})")
    print(f"  Fully active in gameplay: {len(fully_active)}/14 ({', '.join(sorted(fully_active))})")
    print("  Dormant definition suite: ranged_suite_3 (quick_draw, bleed, penetrate)")
    return 0

if __name__ == "__main__":
    sys.exit(main())

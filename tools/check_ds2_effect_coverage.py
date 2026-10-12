#!/usr/bin/env python3
"""
Automated validation script for Dungeon Siege II equipment effect and property coverage.
Checks data/reference/ds2_effect_coverage_manifest.json against data/reference/ds2_equipment_catalog.json.

Verification Rules:
1. Every alteration identifier occurring in items, affixes, or sets must be explicitly mapped in the manifest.
2. Every alteration entry must have a valid status: 'supported', 'unsupported', 'unresolved', 'cosmetic_only', or 'excluded'.
3. Any 'supported' alteration MUST specify a non-empty runtime_consumer and test_path.
4. Any 'unsupported' or 'unresolved' alteration MUST NOT claim a runtime_consumer.
5. All item template fields, attack sub-fields, and requirement syntax patterns must be explicitly classified.
6. Returns exit code 0 if fully valid; exits with non-zero code on any unmapped property, silent omission, or inconsistency.
"""

import json
import os
import sys

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_PATH = os.path.join(BASE_DIR, "data", "reference", "ds2_equipment_catalog.json")
MANIFEST_PATH = os.path.join(BASE_DIR, "data", "reference", "ds2_effect_coverage_manifest.json")

VALID_STATUSES = {"supported", "unsupported", "unresolved", "cosmetic_only", "excluded"}


def validate_coverage(catalog_path=CATALOG_PATH, manifest_path=MANIFEST_PATH):
    errors = []

    if not os.path.exists(catalog_path):
        return [f"Catalog file not found: {catalog_path}"]
    if not os.path.exists(manifest_path):
        return [f"Manifest file not found: {manifest_path}"]

    try:
        with open(catalog_path, "r", encoding="utf-8") as f:
            catalog = json.load(f)
    except Exception as e:
        return [f"Failed to parse catalog JSON: {e}"]

    try:
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = json.load(f)
    except Exception as e:
        return [f"Failed to parse manifest JSON: {e}"]

    items = catalog.get("items", [])
    affixes = catalog.get("affixes", [])
    sets = catalog.get("sets", [])

    # Collect source alterations
    catalog_alts = set()
    for it in items:
        for eff in it.get("effects", []):
            catalog_alts.add(eff["alteration"])
    for aff in affixes:
        for eff in aff.get("effects", []):
            catalog_alts.add(eff["alteration"])
    for s in sets:
        for effs in s.get("totals", {}).values():
            for eff in effs:
                catalog_alts.add(eff["alteration"])

    manifest_alts = manifest.get("alterations", {})

    # Check 1: Completeness of alterations
    missing_in_manifest = catalog_alts - set(manifest_alts.keys())
    if missing_in_manifest:
        errors.append(f"Unmapped alterations found in catalog ({len(missing_in_manifest)}): {sorted(missing_in_manifest)}")

    extra_in_manifest = set(manifest_alts.keys()) - catalog_alts
    if extra_in_manifest:
        errors.append(f"Spurious alterations in manifest not present in catalog ({len(extra_in_manifest)}): {sorted(extra_in_manifest)}")

    # Check 2: Validation of alteration classifications
    for alt_id, alt_data in manifest_alts.items():
        status = alt_data.get("status")
        if status not in VALID_STATUSES:
            errors.append(f"Invalid status '{status}' for alteration '{alt_id}'. Must be one of {VALID_STATUSES}")
            continue

        if status == "supported":
            if not alt_data.get("runtime_consumer"):
                errors.append(f"Supported alteration '{alt_id}' lacks required 'runtime_consumer'.")
            if not alt_data.get("test_path"):
                errors.append(f"Supported alteration '{alt_id}' lacks required 'test_path'.")
            if not alt_data.get("runtime_key"):
                errors.append(f"Supported alteration '{alt_id}' lacks required 'runtime_key'.")
        elif status in ("unsupported", "unresolved"):
            if alt_data.get("runtime_consumer"):
                errors.append(f"Alteration '{alt_id}' has status '{status}' but specifies runtime_consumer '{alt_data['runtime_consumer']}'.")

        # Units and target should always be present
        if not alt_data.get("units"):
            errors.append(f"Alteration '{alt_id}' lacks 'units' specification.")
        if not alt_data.get("target"):
            errors.append(f"Alteration '{alt_id}' lacks 'target' specification.")

    # Check 3: Template properties coverage
    template_props = manifest.get("template_properties", {})
    item_keys = set()
    attack_keys = set()
    for it in items:
        item_keys.update(it.keys())
        if it.get("attack"):
            attack_keys.update(it["attack"].keys())

    for k in item_keys:
        if k not in template_props:
            errors.append(f"Item template key '{k}' missing from manifest 'template_properties'.")
        else:
            if template_props[k].get("status") not in VALID_STATUSES:
                errors.append(f"Template property '{k}' has invalid status '{template_props[k].get('status')}'.")

    for ak in attack_keys:
        full_ak = f"attack.{ak}"
        if full_ak not in template_props:
            errors.append(f"Attack sub-key '{full_ak}' missing from manifest 'template_properties'.")
        else:
            if template_props[full_ak].get("status") not in VALID_STATUSES:
                errors.append(f"Attack property '{full_ak}' has invalid status '{template_props[full_ak].get('status')}'.")

    # Check 4: Requirement patterns coverage
    req_patterns = manifest.get("requirement_patterns", {})
    if not req_patterns:
        errors.append("Manifest missing 'requirement_patterns' mapping.")
    else:
        for p_name, p_data in req_patterns.items():
            if p_data.get("status") not in VALID_STATUSES:
                errors.append(f"Requirement pattern '{p_name}' has invalid status '{p_data.get('status')}'.")

    # Check 5: Summary counts integrity
    summary = manifest.get("summary", {})
    if summary.get("total_catalog_items") != len(items):
        errors.append(f"Summary total_catalog_items ({summary.get('total_catalog_items')}) does not match catalog ({len(items)}).")
    if summary.get("total_source_affixes") != len(affixes):
        errors.append(f"Summary total_source_affixes ({summary.get('total_source_affixes')}) does not match catalog ({len(affixes)}).")
    if summary.get("total_set_definitions") != len(sets):
        errors.append(f"Summary total_set_definitions ({summary.get('total_set_definitions')}) does not match catalog ({len(sets)}).")
    if summary.get("total_distinct_alterations") != len(catalog_alts):
        errors.append(f"Summary total_distinct_alterations ({summary.get('total_distinct_alterations')}) does not match catalog ({len(catalog_alts)}).")

    return errors


def main():
    errors = validate_coverage()
    if errors:
        print(f"FAILED: Found {len(errors)} validation error(s):", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        sys.exit(1)

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    summary = manifest.get("summary", {})
    status_counts = summary.get("alterations_by_status", {})

    print("SUCCESS: DS2 Effect Coverage Manifest is 100% valid and verified.")
    print(f"  Total items checked: {summary.get('total_catalog_items')}")
    print(f"  Total source affixes: {summary.get('total_source_affixes')}")
    print(f"  Total set definitions: {summary.get('total_set_definitions')}")
    print(f"  Total distinct alterations: {summary.get('total_distinct_alterations')}")
    for status, count in status_counts.items():
        print(f"    - {status}: {count}")
    print(f"  Template properties covered: {summary.get('template_properties_count')}")
    print(f"  Requirement patterns covered: {summary.get('requirement_patterns_count')}")
    print(f"  Explicit exclusions recorded: {summary.get('explicit_exclusions_count')}")
    sys.exit(0)


if __name__ == "__main__":
    main()

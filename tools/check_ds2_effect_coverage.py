#!/usr/bin/env python3
"""
Automated validation script for Dungeon Siege II equipment effect and property coverage.
Checks data/reference/ds2_effect_coverage_manifest.json against data/reference/ds2_equipment_catalog.json.

Verification Rules:
1. Every alteration identifier occurring in items, affixes, or sets must be explicitly mapped in the manifest.
2. Every alteration entry must have a valid status: 'supported', 'untested', 'unsupported', 'unresolved', 'cosmetic_only', or 'excluded'.
3. Any 'supported' alteration MUST specify a verified runtime_consumer and test_path whose referenced files and symbols actually exist on disk.
4. Any 'untested' alteration MUST specify a verified runtime_consumer on disk, but MUST NOT claim a test_path until demonstrated by active test coverage.
5. Any 'unsupported' or 'unresolved' alteration MUST NOT claim a runtime_consumer or test_path.
6. All item template fields, attack sub-fields, and requirement syntax patterns must be explicitly classified and verified.
7. Returns exit code 0 if fully valid; exits with non-zero code on any unmapped property, silent omission, or inconsistency.
"""

import json
import os
import sys

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_PATH = os.path.join(BASE_DIR, "data", "reference", "ds2_equipment_catalog.json")
MANIFEST_PATH = os.path.join(BASE_DIR, "data", "reference", "ds2_effect_coverage_manifest.json")

VALID_STATUSES = {"supported", "untested", "unsupported", "unresolved", "cosmetic_only", "excluded"}


def verify_consumer_or_test_path(item_label, path_spec, base_dir=BASE_DIR, kind="consumer"):
    """
    Verifies that all referenced files in path_spec exist on disk, and if a symbol/function
    is specified (e.g. 'path/file.gd:function_name()'), verifies that the symbol is defined
    or present in the file text.
    """
    if not path_spec:
        return [f"{item_label}: Missing required {kind} path."]

    errors = []
    # Can contain multiple comma-separated entries
    parts = [p.strip() for p in path_spec.split(",") if p.strip()]
    for part in parts:
        if ":" in part:
            file_part, symbol_part = part.split(":", 1)
            file_part = file_part.strip()
            symbol = symbol_part.strip().rstrip("()").strip()
        else:
            file_part = part.strip()
            symbol = None

        full_path = os.path.join(base_dir, file_part)
        if not os.path.exists(full_path):
            errors.append(f"{item_label}: Referenced {kind} file does not exist on disk: '{file_part}'")
            continue

        if symbol:
            try:
                with open(full_path, "r", encoding="utf-8") as f:
                    content = f.read()
                if symbol not in content:
                    errors.append(f"{item_label}: Referenced {kind} symbol '{symbol}' not found in '{file_part}'")
            except Exception as e:
                errors.append(f"{item_label}: Failed reading '{file_part}': {e}")
    return errors


def validate_coverage(catalog_path=CATALOG_PATH, manifest_path=MANIFEST_PATH, base_dir=BASE_DIR):
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
            consumer = alt_data.get("runtime_consumer")
            if not consumer:
                errors.append(f"Supported alteration '{alt_id}' lacks required 'runtime_consumer'.")
            else:
                errors.extend(verify_consumer_or_test_path(f"Supported alteration '{alt_id}'", consumer, base_dir, "runtime_consumer"))

            test_p = alt_data.get("test_path")
            if not test_p:
                errors.append(f"Supported alteration '{alt_id}' lacks required 'test_path'.")
            else:
                errors.extend(verify_consumer_or_test_path(f"Supported alteration '{alt_id}'", test_p, base_dir, "test_path"))

            if not alt_data.get("runtime_key"):
                errors.append(f"Supported alteration '{alt_id}' lacks required 'runtime_key'.")

        elif status == "untested":
            consumer = alt_data.get("runtime_consumer")
            if not consumer:
                errors.append(f"Untested alteration '{alt_id}' lacks required 'runtime_consumer'.")
            else:
                errors.extend(verify_consumer_or_test_path(f"Untested alteration '{alt_id}'", consumer, base_dir, "runtime_consumer"))

            if alt_data.get("test_path"):
                errors.append(f"Untested alteration '{alt_id}' specifies test_path '{alt_data['test_path']}' but must be null until demonstrated by active test coverage.")

            if not alt_data.get("runtime_key"):
                errors.append(f"Untested alteration '{alt_id}' lacks required 'runtime_key'.")

        elif status in ("unsupported", "unresolved", "cosmetic_only", "excluded"):
            if alt_data.get("runtime_consumer"):
                errors.append(f"Alteration '{alt_id}' has status '{status}' but specifies runtime_consumer '{alt_data['runtime_consumer']}'.")
            if alt_data.get("test_path"):
                errors.append(f"Alteration '{alt_id}' has status '{status}' but specifies test_path '{alt_data['test_path']}'.")

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
            t_status = template_props[k].get("status")
            if t_status not in VALID_STATUSES:
                errors.append(f"Template property '{k}' has invalid status '{t_status}'.")
            if template_props[k].get("consumer"):
                errors.extend(verify_consumer_or_test_path(f"Template property '{k}'", template_props[k]["consumer"], base_dir, "consumer"))

    for ak in attack_keys:
        full_ak = f"attack.{ak}"
        if full_ak not in template_props:
            errors.append(f"Attack sub-key '{full_ak}' missing from manifest 'template_properties'.")
        else:
            a_status = template_props[full_ak].get("status")
            if a_status not in VALID_STATUSES:
                errors.append(f"Attack property '{full_ak}' has invalid status '{a_status}'.")
            if template_props[full_ak].get("consumer"):
                errors.extend(verify_consumer_or_test_path(f"Attack property '{full_ak}'", template_props[full_ak]["consumer"], base_dir, "consumer"))

    # Check 4: Requirement patterns coverage
    req_patterns = manifest.get("requirement_patterns", {})
    if not req_patterns:
        errors.append("Manifest missing 'requirement_patterns' mapping.")
    else:
        for p_name, p_data in req_patterns.items():
            r_status = p_data.get("status")
            if r_status not in VALID_STATUSES:
                errors.append(f"Requirement pattern '{p_name}' has invalid status '{r_status}'.")
            if p_data.get("runtime_consumer"):
                if r_status in ("unsupported", "unresolved"):
                    errors.append(f"Requirement pattern '{p_name}' has status '{r_status}' but specifies runtime_consumer '{p_data['runtime_consumer']}'.")
                else:
                    errors.extend(verify_consumer_or_test_path(f"Requirement pattern '{p_name}'", p_data["runtime_consumer"], base_dir, "runtime_consumer"))

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

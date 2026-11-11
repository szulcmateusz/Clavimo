#!/usr/bin/env python3
"""Validates configuration files against schema/config-v1.schema.json.

Usage: scripts/validate-config.py FILE [FILE ...]
Requires the jsonschema package (pip install jsonschema).
"""
import json
import pathlib
import sys

import jsonschema

ROOT = pathlib.Path(__file__).resolve().parent.parent
schema = json.loads((ROOT / "schema" / "config-v1.schema.json").read_text())
validator = jsonschema.Draft202012Validator(schema)

failed = False
for name in sys.argv[1:]:
    errors = sorted(validator.iter_errors(json.loads(pathlib.Path(name).read_text())), key=lambda e: list(e.path))
    for error in errors:
        location = "/".join(str(part) for part in error.path) or "(root)"
        print(f"{name}: {location}: {error.message}")
    if errors:
        failed = True
    else:
        print(f"{name}: valid")
sys.exit(1 if failed else 0)

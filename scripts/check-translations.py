#!/usr/bin/env python3
"""Fails when a string in the app's catalog lacks a translation or has
format specifiers that differ from the source.

Usage: scripts/check-translations.py [language ...]   (default: pl)
"""
import json
import pathlib
import re
import sys

CATALOG = pathlib.Path(__file__).resolve().parent.parent / "Packages/ClavimoApp/Resources/Localizable.xcstrings"
SPECIFIER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f)")

languages = sys.argv[1:] or ["pl"]
strings = json.loads(CATALOG.read_text())["strings"]
problems = []
for key, entry in sorted(strings.items()):
    if entry.get("extractionState") == "stale" or entry.get("shouldTranslate") is False:
        continue
    expected = sorted(re.sub(r"\d+\$", "", s) for s in SPECIFIER.findall(key))
    for language in languages:
        unit = entry.get("localizations", {}).get(language, {}).get("stringUnit")
        if not unit or not unit.get("value"):
            problems.append(f"{language}: missing translation for {key!r}")
            continue
        found = sorted(re.sub(r"\d+\$", "", s) for s in SPECIFIER.findall(unit["value"]))
        if found != expected:
            problems.append(f"{language}: format specifiers differ for {key!r}: {unit['value']!r}")
for problem in problems:
    print(problem)
print(f"{len(strings)} strings checked, {len(problems)} problems")
sys.exit(1 if problems else 0)

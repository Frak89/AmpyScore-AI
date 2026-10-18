#!/usr/bin/env python3
"""Compatibility fix for flutter_midi_pro 4.0.4 with Flutter's AGP 9 template.
Upstream declares kotlin {} in the Gradle plugin project even when it has
no kotlin project extension. Do not change synth sources or downloaded libs.
"""
from pathlib import Path
import re
import sys

pubcache = Path.home() / ".pub-cache" / "hosted" / "pub.dev"
candidates = list(pubcache.glob("flutter_midi_pro-4.0.4/android/build.gradle"))
if not candidates:
    raise SystemExit("flutter_midi_pro 4.0.4 Gradle file missing; run flutter pub get")
file = candidates[0]
source = file.read_text(encoding="utf-8")
block = re.search(r'\n// Replaces the removed android\.kotlinOptions block;[\s\S]*?\nkotlin \{\s*compilerOptions \{[\s\S]*?\n\}\s*$', source)
if block is None:
    if "// AmpyScore AGP Kotlin fix" in source:
        print("Kotlin compatibility patch already applied")
        sys.exit(0)
    raise SystemExit("Upstream plugin Gradle source changed; inspect before patching.")
out = source[:block.start()] + "\n// AmpyScore AGP Kotlin fix: no kotlin DSL extension available.\n"
file.write_text(out, encoding="utf-8")
print("Applied narrowly-scoped Gradle Kotlin DSL compatibility patch")

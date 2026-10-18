#!/usr/bin/env python3
"""Temporary compatibility patch for flutter_midi_pro 4.0.4 on Flutter 3.47.

Upstream conditionally omits Kotlin plugin but the Android library's Kotlin
class is not then compiled, causing GeneratedPluginRegistrant javac failure.
Explicit KGP also creates the required kotlin compilerOptions extension.
No source code or soundfont changes; only Gradle plugin application.
"""
from pathlib import Path
import re

pubcache = Path.home() / ".pub-cache" / "hosted" / "pub.dev"
matches = list(pubcache.glob("flutter_midi_pro-4.0.4/android/build.gradle"))
if len(matches) != 1:
    raise SystemExit("Missing pinned flutter_midi_pro Gradle file; run flutter pub get.")
path = matches[0]
source = path.read_text(encoding="utf-8")
original = '''if (agpMajor < 9) {
    apply plugin: "kotlin-android"
}'''
fixed = '''// AmpyScore v0.7 temporary Flutter 3.47 AGP compatibility:
apply plugin: "kotlin-android"'''
if original in source:
    source = source.replace(original, fixed, 1)
elif fixed not in source:
    raise SystemExit("Unexpected flutter_midi_pro Gradle structure.")
# Unpatched original included the kotlin {compilerOptions{...}} DSL.
# KGP is now explicitly applied, and this block configures JVM 17.
if not re.search(r'\bkotlin\s*\{\s*compilerOptions', source):
    raise SystemExit("Expected plugin Kotlin compilerOptions block missing.")
path.write_text(source, encoding="utf-8")
print("Applied temporary KGP compatibility patch for native MIDI plugin")

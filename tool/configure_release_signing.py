#!/usr/bin/env python3
"""Configure a generated Flutter Android Gradle Kotlin release build.

Call only after `flutter create`. Never commit signing credentials.
"""
from pathlib import Path

p = Path("android/app/build.gradle.kts")
if not p.is_file():
    raise SystemExit("Run flutter create first; expected android/app/build.gradle.kts")
source = p.read_text(encoding="utf-8")
marker = "    buildTypes {"
if marker not in source:
    raise SystemExit("Cannot locate Gradle buildTypes; inspect generated Android project.")
if 'signingConfigs.getByName("debug")' not in source:
    raise SystemExit("Expected Flutter debug release signing template not found.")

config = '''    signingConfigs {
        create("ampyProduction") {
            storeFile = file(System.getenv("AMPY_KEYSTORE_PATH")
                ?: error("Missing AMPY_KEYSTORE_PATH"))
            storePassword = System.getenv("AMPY_KEYSTORE_PASSWORD")
                ?: error("Missing AMPY_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("AMPY_KEY_ALIAS")
                ?: error("Missing AMPY_KEY_ALIAS")
            keyPassword = System.getenv("AMPY_KEY_PASSWORD")
                ?: error("Missing AMPY_KEY_PASSWORD")
        }
    }
'''
source = source.replace(marker, config + marker, 1)
source = source.replace(
    'signingConfig = signingConfigs.getByName("debug")',
    'signingConfig = signingConfigs.getByName("ampyProduction")',
)
p.write_text(source, encoding="utf-8")
print("Production signing wired from CI environment; no credentials printed.")

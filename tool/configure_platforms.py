#!/usr/bin/env python3
"""Idempotent native Flutter permission/bootstrap adjustment.

Run AFTER flutter create --platforms=android,ios ... .
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
android = root / "android/app/src/main/AndroidManifest.xml"
ios = root / "ios/Runner/Info.plist"

if not android.exists() or not ios.exists():
    raise SystemExit("Missing native platforms. Run flutter create first.")

manifest = android.read_text(encoding="utf-8")
for permission in ("android.permission.RECORD_AUDIO", "android.permission.INTERNET"):
    entry = f'    <uses-permission android:name="{permission}"/>'
    if permission not in manifest:
        manifest = manifest.replace("    <application", entry + "\n    <application", 1)
android.write_text(manifest, encoding="utf-8")

plist = ios.read_text(encoding="utf-8")
if "NSMicrophoneUsageDescription" not in plist:
    key = (
        "    <key>NSMicrophoneUsageDescription</key>\n"
        "    <string>AmpyScore registra brevi melodie da convertire in note musicali.</string>\n"
    )
    plist = plist.replace("<dict>", "<dict>\n" + key, 1)
ios.write_text(plist, encoding="utf-8")

podfile = root / "ios/Podfile"
if podfile.exists():
    text = podfile.read_text(encoding="utf-8")
    text = re.sub(r"^#?\s*platform :ios, '[^']+'",
                  "platform :ios, '14.0'", text, count=1, flags=re.M)
    if "platform :ios" not in text:
        text = "platform :ios, '14.0'\n" + text
    podfile.write_text(text, encoding="utf-8")

pbxproj = root / "ios/Runner.xcodeproj/project.pbxproj"
if pbxproj.exists():
    text = pbxproj.read_text(encoding="utf-8")
    text = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;",
                  "IPHONEOS_DEPLOYMENT_TARGET = 14.0;", text)
    pbxproj.write_text(text, encoding="utf-8")

print("Android microphone/internet permission and iOS microphone description configured.")

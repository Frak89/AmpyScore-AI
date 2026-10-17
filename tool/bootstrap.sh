#!/usr/bin/env bash
set -euo pipefail
flutter create --platforms=android,ios --project-name=ampy_score_ai --org=dev.ampyscore .
python3 tool/configure_platforms.py
flutter pub get
echo 'Setup complete. Run: flutter run'

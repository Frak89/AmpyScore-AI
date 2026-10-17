# From the repository root in Windows PowerShell:
$ErrorActionPreference = 'Stop'
flutter create --platforms=android,ios --project-name=ampy_score_ai --org=dev.ampyscore .
if ($LASTEXITCODE -ne 0) { throw 'flutter create failed' }
py -3 tool/configure_platforms.py
if ($LASTEXITCODE -ne 0) { throw 'Platform config failed' }
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
Write-Host 'Setup complete. Run: flutter run'

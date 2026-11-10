#!/usr/bin/env bash
# Linux/macOS version of setup_android.bat
set -e
flutter create --platforms=android,web --project-name tournament_master_offline --org com.tournamentmaster.offline .
rm -f test/widget_test.dart
M=android/app/src/main/AndroidManifest.xml
grep -q android.permission.INTERNET "$M" || sed -i 's#<manifest\([^>]*\)>#<manifest\1>\n    <uses-permission android:name="android.permission.INTERNET"/>#' "$M"
grep -q usesCleartextTraffic "$M" || sed -i 's#<application#<application android:usesCleartextTraffic="true"#' "$M"
sed -i 's#android:label="[^"]*"#android:label="Tournament Master Offline"#' "$M"
flutter pub get
dart run sqflite_common_ffi_web:setup
echo "Done. Next: flutter run"

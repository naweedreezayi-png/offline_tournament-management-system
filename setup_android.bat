@echo off
REM Creates the android/ and web/ folders and applies the settings this app needs.
REM Run from the "frontend" folder:  setup_android.bat
where flutter >nul 2>nul || (echo Flutter is not installed or not in PATH. See docs\INSTALLATION.md & exit /b 1)
call flutter create --platforms=android,web --project-name tournament_master_offline --org com.tournamentmaster.offline .
if exist test\widget_test.dart del test\widget_test.dart
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_android.ps1"
call flutter pub get
REM files the browser version needs for the local database (sqflite_sw.js, sqlite3.wasm)
call dart run sqflite_common_ffi_web:setup
echo.
echo Done. Next:  flutter run   (or)   flutter build apk --release

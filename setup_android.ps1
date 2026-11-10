# Patches android/app/src/main/AndroidManifest.xml: INTERNET permission, label and cleartext http
# (cleartext is only for testing against http://10.0.2.2:8081 or a LAN server; use https in production).
$m = Join-Path $PSScriptRoot 'android\app\src\main\AndroidManifest.xml'
if (-not (Test-Path $m)) { Write-Host "AndroidManifest.xml not found: run flutter create first"; exit 1 }
$x = Get-Content $m -Raw
if ($x -notmatch 'android.permission.INTERNET') {
  $x = $x -replace '<manifest([^>]*)>', "<manifest`$1>`n    <uses-permission android:name=`"android.permission.INTERNET`"/>"
}
if ($x -notmatch 'usesCleartextTraffic') {
  $x = $x -replace '<application', '<application android:usesCleartextTraffic="true"'
}
$x = $x -replace 'android:label="[^"]*"', 'android:label="Tournament Master Offline"'
Set-Content $m $x -Encoding UTF8
Write-Host "AndroidManifest.xml patched."

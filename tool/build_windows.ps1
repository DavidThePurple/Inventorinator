$ErrorActionPreference = 'Stop'

Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter is not on PATH. Install Flutter, then reopen PowerShell.'
}

flutter config --enable-windows-desktop
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build windows --release

$bundle = Join-Path $PWD 'build\windows\x64\runner\Release'
$archive = Join-Path $PWD 'build\Inventorinator-Windows-x64.zip'
if (Test-Path $archive) {
  Remove-Item $archive
}
Compress-Archive -Path "$bundle\*" -DestinationPath $archive

Write-Host "Windows release ready: $archive"

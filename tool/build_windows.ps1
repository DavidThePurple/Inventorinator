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
$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([^+]+)' | Select-Object -First 1).Matches[0].Groups[1].Value
$buildHash = (git rev-parse --short=12 HEAD).Trim()
flutter build windows --release "--dart-define=INVENTORINATOR_VERSION=$version" "--dart-define=INVENTORINATOR_BUILD_HASH=$buildHash"

$bundle = Join-Path $PWD 'build\windows\x64\runner\Release'
$archive = Join-Path $PWD 'build\Inventorinator-Windows-x64.zip'
if (Test-Path $archive) {
  Remove-Item $archive
}
Compress-Archive -Path "$bundle\*" -DestinationPath $archive

Write-Host "Windows release ready: $archive"

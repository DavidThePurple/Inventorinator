# Checks that a built Windows bundle carries a working label-OCR engine.
# Usage: tool\verify_windows_ocr.ps1 [bundle directory]
param(
  [string]$Bundle = 'build\windows\x64\runner\Release'
)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$ocr = Join-Path $Bundle 'data\ocr\windows_x64'
$engine = Join-Path $ocr 'tesseract.exe'
$tessdata = Join-Path $ocr 'tessdata'

foreach ($path in @($engine, (Join-Path $tessdata 'eng.traineddata'))) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Missing Windows OCR asset: $path"
  }
}

# Run with only the system directories on PATH so a compiler runtime that
# happens to be installed on this machine cannot hide a missing dependency.
$savedPath = $env:PATH
$savedTessdata = $env:TESSDATA_PREFIX
try {
  $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
  $env:TESSDATA_PREFIX = $tessdata

  & $engine --version
  if ($LASTEXITCODE -ne 0) { throw "tesseract.exe did not start (exit $LASTEXITCODE)" }

  # PNG and JPEG both matter: the app hands Tesseract the original camera
  # frame as well as JPEG-encoded enhancement candidates.
  foreach ($fixture in 'label.png', 'label.jpg') {
    $image = Join-Path $root "test\fixtures\ocr\$fixture"
    $text = (& $engine $image stdout -l eng --psm 6 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "OCR failed for $fixture (exit $LASTEXITCODE)" }
    foreach ($expected in 'POLYLITE', 'PETG', '1.75', 'Black') {
      if ($text -notmatch [regex]::Escape($expected)) {
        throw "OCR of $fixture did not find '$expected'. Output:`n$text"
      }
    }
  }
} finally {
  $env:PATH = $savedPath
  $env:TESSDATA_PREFIX = $savedTessdata
}

Write-Host 'Windows label OCR engine verified.'

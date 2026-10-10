$ErrorActionPreference = 'Stop'
$secretDirectory = Join-Path $PSScriptRoot '.secrets'
New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null
$passwordPath = Join-Path $secretDirectory 'jenkins-admin'
if (-not (Test-Path -LiteralPath $passwordPath)) { [IO.File]::WriteAllText($passwordPath, [guid]::NewGuid().ToString('N')) }
docker compose -f (Join-Path $PSScriptRoot 'compose.yaml') up -d --build
if ($LASTEXITCODE -ne 0) { throw 'Exercise 9 Jenkins startup failed.' }
Write-Output 'Exercise 9 Jenkins started; its administrator password stays in .secrets/.'

$ErrorActionPreference = 'Stop'
$secretDirectory = Join-Path $PSScriptRoot '.secrets'
New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null
foreach ($name in @('jenkins-admin', 'grafana-admin')) {
    $path = Join-Path $secretDirectory $name
    if (-not (Test-Path -LiteralPath $path)) {
        [System.IO.File]::WriteAllText($path, [guid]::NewGuid().ToString('N'), [System.Text.UTF8Encoding]::new($false))
    }
}
docker compose -f (Join-Path $PSScriptRoot 'compose.yaml') up -d --build
if ($LASTEXITCODE -ne 0) { throw 'Jenkins lab startup failed.' }
Write-Output 'Jenkins lab started. Credentials remain in the ignored .secrets folder.'

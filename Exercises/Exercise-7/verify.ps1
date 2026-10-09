param([ValidateSet('installed', 'restarted')][string]$Phase = 'installed')

$ErrorActionPreference = 'Stop'
$baseUrl = 'http://127.0.0.1:18007'
$password = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '.secrets/admin-password')).Trim()
$headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$password")) }
$deadline = (Get-Date).AddMinutes(3)
do {
    try { $api = Invoke-RestMethod "$baseUrl/api/json" -Headers $headers -TimeoutSec 5; break } catch { Start-Sleep -Seconds 2 }
} while ((Get-Date) -lt $deadline)
if (-not $api) { throw 'Authenticated Jenkins API did not become ready.' }
$identity = Invoke-RestMethod "$baseUrl/whoAmI/api/json" -Headers $headers -TimeoutSec 10
$homeResponse = Invoke-WebRequest "$baseUrl/" -Headers $headers -TimeoutSec 10
$plugins = (Invoke-RestMethod "$baseUrl/pluginManager/api/json?depth=1" -Headers $headers -TimeoutSec 10).plugins
$required = @($plugins | Where-Object { $_.shortName -in @('git', 'workflow-aggregator', 'pipeline-stage-view') -and $_.active })
$anonymous = Invoke-WebRequest "$baseUrl/api/json" -SkipHttpErrorCheck -TimeoutSec 10
docker compose -f (Join-Path $PSScriptRoot 'compose.yaml') exec -T jenkins test -f /var/jenkins_home/jenkins.install.InstallUtil.lastExecVersion
$setupMarkerExists = $LASTEXITCODE -eq 0
$checks = @(
    [ordered]@{ name = 'Administrator authentication'; passed = $identity.authenticated -and $identity.name -eq 'admin'; details = $identity.name },
    [ordered]@{ name = 'Jenkins ready in NORMAL mode'; passed = $api.mode -eq 'NORMAL'; details = $api.mode },
    [ordered]@{ name = 'Setup completed and dashboard served'; passed = $setupMarkerExists -and $homeResponse.StatusCode -eq 200 -and -not $homeResponse.Content.Contains('Unlock Jenkins'); details = @{ setup_marker_exists = $setupMarkerExists; http_status = $homeResponse.StatusCode } },
    [ordered]@{ name = 'Git and Pipeline plugins active'; passed = $required.Count -eq 3; details = @($required | Select-Object shortName, version, active) },
    [ordered]@{ name = 'Anonymous API access is denied'; passed = $anonymous.StatusCode -eq 403; details = $anonymous.StatusCode }
)
$directory = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
[ordered]@{ checked_at_utc = (Get-Date).ToUniversalTime().ToString('o'); phase = $Phase; jenkins_version = $homeResponse.Headers['X-Jenkins'] -join ''; checks = $checks } |
    ConvertTo-Json -Depth 8 | Set-Content (Join-Path $directory "verification-$Phase.json") -Encoding utf8
if (@($checks | Where-Object { -not $_.passed }).Count) { throw 'Jenkins installation verification failed. Inspect the report.' }
Write-Output "Five Jenkins installation checks passed ($Phase)."

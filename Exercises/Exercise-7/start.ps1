$ErrorActionPreference = 'Stop'
$composeFile = Join-Path $PSScriptRoot 'compose.yaml'
docker compose -f $composeFile up -d
if ($LASTEXITCODE -ne 0) { throw 'Jenkins startup failed.' }
$deadline = (Get-Date).AddMinutes(5)
do {
    try {
        $response = Invoke-WebRequest 'http://127.0.0.1:18007/login' -TimeoutSec 5
        if ($response.StatusCode -eq 200) { break }
    } catch { }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
if (-not $response -or $response.StatusCode -ne 200) { throw 'Jenkins did not become ready.' }
$secretDirectory = Join-Path $PSScriptRoot '.secrets'
New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null
$initialPassword = docker compose -f $composeFile exec -T jenkins sh -c 'if test -f /var/jenkins_home/secrets/initialAdminPassword; then cat /var/jenkins_home/secrets/initialAdminPassword; fi'
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the initial password file.' }
if ($initialPassword) { [IO.File]::WriteAllText((Join-Path $secretDirectory 'initial-admin'), ($initialPassword -join '').Trim()) }
$containerId = docker compose -f $composeFile ps -q jenkins
$container = docker inspect $containerId | ConvertFrom-Json
$report = [ordered]@{
    checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    url = 'http://127.0.0.1:18007/'
    jenkins_version = $response.Headers['X-Jenkins'] -join ''
    running = $container.State.Running
    image = $container.Config.Image
    image_id = $container.Image
    home_mount = @($container.Mounts | Where-Object Destination -eq '/var/jenkins_home' | Select-Object Type, Name, Destination)
    initial_password_saved_privately = [bool]$initialPassword
    unlock_page_visible = $response.Content.Contains('Unlock Jenkins')
}
$directory = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $directory 'installation.json') -Encoding utf8
Write-Output 'Jenkins is reachable. Initial credentials, when present, are saved only under .secrets/.'

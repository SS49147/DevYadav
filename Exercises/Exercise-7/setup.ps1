$ErrorActionPreference = 'Stop'
$baseUrl = 'http://127.0.0.1:18007'
$secretDirectory = Join-Path $PSScriptRoot '.secrets'
$passwordPath = Join-Path $secretDirectory 'admin-password'
if (-not (Test-Path -LiteralPath $passwordPath)) { [IO.File]::WriteAllText($passwordPath, [guid]::NewGuid().ToString('N')) }
$adminPassword = [IO.File]::ReadAllText($passwordPath).Trim()
$initialPassword = [IO.File]::ReadAllText((Join-Path $secretDirectory 'initial-admin')).Trim()
$headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$initialPassword")) }
$crumb = Invoke-RestMethod "$baseUrl/crumbIssuer/api/json" -Headers $headers -SessionVariable session
$headers[$crumb.crumbRequestField] = $crumb.crumb
$pluginRequest = @{ plugins = @('git', 'workflow-aggregator', 'pipeline-stage-view'); dynamicLoad = $true } | ConvertTo-Json
$installation = Invoke-RestMethod "$baseUrl/pluginManager/installPlugins" -Method Post -ContentType 'application/json' -Body $pluginRequest -Headers $headers -WebSession $session
if ($installation.status -ne 'ok') { throw 'Jenkins refused the plugin installation.' }
$deadline = (Get-Date).AddMinutes(10)
do {
    $status = Invoke-RestMethod "$baseUrl/updateCenter/installStatus?correlationId=$($installation.data.correlationId)" -Headers $headers -WebSession $session
    $jobs = @($status.data.jobs)
    if (@($jobs | Where-Object { $_.installStatus -eq 'Failure' }).Count) { throw 'A Jenkins plugin failed to install.' }
    $plugins = (Invoke-RestMethod "$baseUrl/pluginManager/api/json?depth=1" -Headers $headers -WebSession $session).plugins
    $required = @($plugins | Where-Object { $_.shortName -in @('git', 'workflow-aggregator', 'pipeline-stage-view') -and $_.active })
    $installationComplete = $required.Count -eq 3 -and @($jobs | Where-Object { $_.installStatus -notin @('Success', 'Skipped') }).Count -eq 0
    if ($installationComplete) { break }
    Start-Sleep -Seconds 3
} while ((Get-Date) -lt $deadline)
if (-not $installationComplete) { throw 'Required Jenkins plugins did not finish installing.' }
$account = @{ username = 'admin'; password1 = $adminPassword; password2 = $adminPassword; fullname = 'Lab Administrator'; email = 'admin@localhost.invalid' }
$created = Invoke-RestMethod "$baseUrl/setupWizard/createAdminUser" -Method Post -Body $account -Headers $headers -WebSession $session
if ($created.status -ne 'ok') { throw 'Administrator account creation failed.' }
$headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$adminPassword")) }
$crumb = Invoke-RestMethod "$baseUrl/crumbIssuer/api/json" -Headers $headers -WebSession $session
$headers[$crumb.crumbRequestField] = $crumb.crumb
$configured = Invoke-RestMethod "$baseUrl/setupWizard/configureInstance" -Method Post -Body @{ rootUrl = "$baseUrl/" } -Headers $headers -WebSession $session
if ($configured.status -ne 'ok') { throw 'Jenkins URL configuration failed.' }
$completed = Invoke-RestMethod "$baseUrl/setupWizard/completeInstall" -Method Post -Headers $headers -WebSession $session
if ($completed.status -ne 'ok') { throw 'Jenkins setup did not complete.' }
$cookies = @($session.Cookies.GetCookies([Uri]$baseUrl) | ForEach-Object { [ordered]@{
    name = $_.Name; value = $_.Value; domain = $_.Domain; path = $_.Path; expires = -1
    httpOnly = $_.HttpOnly; secure = $_.Secure; sameSite = 'Lax'
} })
@{ cookies = $cookies; origins = @() } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $secretDirectory 'browser.auth-state.json') -Encoding utf8
Write-Output 'Setup completed with the Git and Pipeline plugins. Credentials and browser session are private.'

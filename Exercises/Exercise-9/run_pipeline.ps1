param([switch]$SaveBrowserSession)

$ErrorActionPreference = 'Stop'
$baseUrl = 'http://127.0.0.1:18009'
$password = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '.secrets/jenkins-admin')).Trim()
$headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$password")) }
$deadline = (Get-Date).AddMinutes(5)
do {
    try { $crumb = Invoke-RestMethod "$baseUrl/crumbIssuer/api/json" -Headers $headers -SessionVariable session -TimeoutSec 5; break } catch { Start-Sleep -Seconds 2 }
} while ((Get-Date) -lt $deadline)
if (-not $crumb) { throw 'Exercise 9 Jenkins did not become ready.' }
$headers[$crumb.crumbRequestField] = $crumb.crumb
$jobUrl = "$baseUrl/job/Python-MultiStage-Pipeline"
$job = Invoke-WebRequest "$jobUrl/api/json" -Headers $headers -WebSession $session -SkipHttpErrorCheck
$xml = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'job.xml'))
if ($job.StatusCode -eq 404) {
    Invoke-WebRequest "$baseUrl/createItem?name=Python-MultiStage-Pipeline" -Method Post -ContentType 'application/xml' -Body $xml -Headers $headers -WebSession $session | Out-Null
} elseif ($job.StatusCode -eq 200) {
    if (($job.Content | ConvertFrom-Json).description -ne 'Exercise 9: Python multi-stage pipeline.') { throw 'Refusing to overwrite an unrelated pipeline job.' }
    Invoke-WebRequest "$jobUrl/config.xml" -Method Post -ContentType 'application/xml' -Body $xml -Headers $headers -WebSession $session | Out-Null
} else { throw 'Could not inspect the pipeline job.' }
$queued = Invoke-WebRequest "$jobUrl/build" -Method Post -Headers $headers -WebSession $session
$queueUrl = $queued.Headers.Location -join ''
if ($queueUrl.StartsWith('/')) { $queueUrl = $baseUrl + $queueUrl }
if (-not $queueUrl) { throw 'Jenkins did not return a queue item.' }
$deadline = (Get-Date).AddMinutes(15)
do {
    $queue = Invoke-RestMethod "$queueUrl/api/json" -Headers $headers -WebSession $session
    if ($queue.cancelled) { throw 'Pipeline build was cancelled.' }
    if ($queue.executable) { break }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
if (-not $queue.executable) { throw 'Pipeline build did not start.' }
$number = $queue.executable.number
do {
    $build = Invoke-RestMethod "$jobUrl/$number/api/json" -Headers $headers -WebSession $session
    if (-not $build.building) { break }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
$directory = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$console = [string](Invoke-WebRequest "$jobUrl/$number/consoleText" -Headers $headers -WebSession $session).Content
[IO.File]::WriteAllText((Join-Path $directory 'console.txt'), $console)
if ($build.building -or $build.result -ne 'SUCCESS') { throw "Pipeline build $number did not succeed. Inspect evidence/console.txt." }
$stages = Invoke-RestMethod "$jobUrl/$number/wfapi/describe" -Headers $headers -WebSession $session
foreach ($filename in @('http-response.json', 'server-cleanup.json')) {
    $artifact = [string](Invoke-WebRequest "$jobUrl/$number/artifact/Exercises/Exercise-9/evidence/$filename" -Headers $headers -WebSession $session).Content
    [IO.File]::WriteAllText((Join-Path $directory $filename), $artifact)
}
$httpProof = Get-Content (Join-Path $directory 'http-response.json') -Raw | ConvertFrom-Json
$cleanupProof = Get-Content (Join-Path $directory 'server-cleanup.json') -Raw | ConvertFrom-Json
$started = [DateTimeOffset]::FromUnixTimeMilliseconds($build.timestamp)
$expectedStages = @('Build', 'Test', 'Deploy', 'Run Application', 'Test Application')
$requiredStages = @($stages.stages | Where-Object name -in $expectedStages)
$revision = ($build.actions | Where-Object { $_.lastBuiltRevision }).lastBuiltRevision.SHA1
$checks = @(
    [ordered]@{ name = 'Jenkinsfile obtained from Git SCM'; passed = $console.Contains('Obtained Exercises/Exercise-9/Jenkinsfile from git https://github.com/Anas2694/DevOps-Lab.git') -and $revision -match '^[a-f0-9]{40}$'; details = $revision },
    [ordered]@{ name = 'All five required stages succeeded'; passed = $requiredStages.Count -eq 5 -and @($requiredStages | Where-Object status -ne 'SUCCESS').Count -eq 0; details = @($requiredStages | Select-Object name, status, durationMillis) },
    [ordered]@{ name = 'Dependencies installed and unit tests passed'; passed = $console.Contains('pip install -r requirements.txt') -and $console.Contains('No broken requirements found.') -and $console.Contains('Ran 2 tests') -and $console.Contains('OK'); details = 'Virtual environment, pip check and two unit tests' },
    [ordered]@{ name = 'Live deployed application returned the exact response'; passed = $httpProof.http_status -eq 200 -and $httpProof.body -eq 'Hello, Jenkins Multi-Stage Pipeline!' -and $httpProof.source_matches_deployment -and $httpProof.pid_runs_deployed_app -and [DateTimeOffset]$httpProof.checked_at_utc -ge $started; details = $httpProof },
    [ordered]@{ name = 'Only the owned application process was stopped'; passed = $cleanupProof.application_stopped -and $cleanupProof.pid_file_removed -and $cleanupProof.process_id -eq $httpProof.process_id -and [DateTimeOffset]$cleanupProof.checked_at_utc -ge [DateTimeOffset]$httpProof.checked_at_utc; details = $cleanupProof }
)
[ordered]@{ checked_at_utc = (Get-Date).ToUniversalTime().ToString('o'); build_number = $number; job_url = "$jobUrl/$number/"; result = $build.result; scm_revision = $revision; checks = $checks } |
    ConvertTo-Json -Depth 10 | Set-Content (Join-Path $directory 'verification.json') -Encoding utf8
if (@($checks | Where-Object { -not $_.passed }).Count) { throw 'Pipeline evidence verification failed. Inspect the saved report.' }
if ($SaveBrowserSession) {
    $loginPage = Invoke-WebRequest "$baseUrl/login" -SessionVariable browserSession
    $loginCrumb = [regex]::Match($loginPage.Content, '<input name="Jenkins-Crumb"[^>]*value="([^"]+)"').Groups[1].Value
    if (-not $loginCrumb) { throw 'Jenkins login form did not provide its CSRF token.' }
    Invoke-WebRequest "$baseUrl/j_spring_security_check" -Method Post -ContentType 'application/x-www-form-urlencoded' -Body @{ j_username = 'admin'; j_password = $password; from = '/'; 'Jenkins-Crumb' = $loginCrumb } -WebSession $browserSession | Out-Null
    $cookies = @($browserSession.Cookies.GetCookies([Uri]$baseUrl) | ForEach-Object { [ordered]@{
        name = $_.Name; value = $_.Value; domain = $_.Domain; path = $_.Path; expires = -1
        httpOnly = $_.HttpOnly; secure = $_.Secure; sameSite = 'Lax'
    } })
    @{ cookies = $cookies; origins = @() } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $PSScriptRoot '.secrets/browser.auth-state.json') -Encoding utf8
}
Write-Output "Pipeline build $number succeeded; five evidence checks passed."

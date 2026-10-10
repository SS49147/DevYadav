param([switch]$SaveBrowserSession)

$ErrorActionPreference = 'Stop'
$baseUrl = 'http://127.0.0.1:18007'
$password = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../Exercise-7/.secrets/admin-password')).Trim()
$headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$password")) }
$crumb = Invoke-RestMethod "$baseUrl/crumbIssuer/api/json" -Headers $headers -SessionVariable session -TimeoutSec 10
$headers[$crumb.crumbRequestField] = $crumb.crumb
$jobUrl = "$baseUrl/job/HelloWorld"
$job = Invoke-WebRequest "$jobUrl/api/json" -Headers $headers -WebSession $session -SkipHttpErrorCheck
$xml = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'job.xml'))
if ($job.StatusCode -eq 404) {
    Invoke-WebRequest "$baseUrl/createItem?name=HelloWorld" -Method Post -ContentType 'application/xml' -Body $xml -Headers $headers -WebSession $session | Out-Null
} elseif ($job.StatusCode -eq 200) {
    $existing = $job.Content | ConvertFrom-Json
    if ($existing.description -ne 'Exercise 8: Hello World! Jenkins job.') { throw 'Refusing to overwrite an unrelated HelloWorld job.' }
    Invoke-WebRequest "$jobUrl/config.xml" -Method Post -ContentType 'application/xml' -Body $xml -Headers $headers -WebSession $session | Out-Null
} else { throw 'Could not inspect the HelloWorld job.' }
$queued = Invoke-WebRequest "$jobUrl/build" -Method Post -Headers $headers -WebSession $session
$queueUrl = $queued.Headers.Location -join ''
if ($queueUrl.StartsWith('/')) { $queueUrl = $baseUrl + $queueUrl }
if (-not $queueUrl) { throw 'No Jenkins queue item was returned.' }
$deadline = (Get-Date).AddMinutes(10)
do {
    $queue = Invoke-RestMethod "$queueUrl/api/json" -Headers $headers -WebSession $session
    if ($queue.cancelled) { throw 'HelloWorld build was cancelled.' }
    if ($queue.executable) { break }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
if (-not $queue.executable) { throw 'HelloWorld build did not start.' }
$number = $queue.executable.number
do {
    $build = Invoke-RestMethod "$jobUrl/$number/api/json" -Headers $headers -WebSession $session
    if (-not $build.building) { break }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
$console = [string](Invoke-WebRequest "$jobUrl/$number/consoleText" -Headers $headers -WebSession $session).Content
$directory = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $directory 'console.txt'), $console)
$configurationText = [string](Invoke-WebRequest "$jobUrl/config.xml" -Headers $headers -WebSession $session).Content
$configuration = [xml][regex]::Replace($configurationText, '^\s*<\?xml[^>]*\?>', '')
$revision = ($build.actions | Where-Object { $_.lastBuiltRevision }).lastBuiltRevision.SHA1
$checks = @(
    [ordered]@{ name = 'Freestyle project'; passed = $build._class -eq 'hudson.model.FreeStyleBuild'; details = $build._class },
    [ordered]@{ name = 'Git SCM uses the lab repository and main branch'; passed = $configuration.project.scm.userRemoteConfigs.'hudson.plugins.git.UserRemoteConfig'.url -eq 'https://github.com/Anas2694/DevOps-Lab.git' -and $configuration.project.scm.branches.'hudson.plugins.git.BranchSpec'.name -eq '*/main' -and $revision -match '^[a-f0-9]{40}$' -and $console.Contains("Checking out Revision $revision"); details = $revision },
    [ordered]@{ name = 'Execute shell runs the committed script'; passed = $configuration.project.builders.'hudson.tasks.Shell'.command -eq 'sh Exercises/Exercise-8/hello-world.sh' -and $console.Contains('+ sh Exercises/Exercise-8/hello-world.sh'); details = 'sh Exercises/Exercise-8/hello-world.sh' },
    [ordered]@{ name = 'Expected output appears in the real console'; passed = $console.Contains('Hello, Jenkins!'); details = 'Hello, Jenkins!' },
    [ordered]@{ name = 'Build finished successfully'; passed = -not $build.building -and $build.result -eq 'SUCCESS' -and $console.Contains('Finished: SUCCESS'); details = $build.result }
)
[ordered]@{ checked_at_utc = (Get-Date).ToUniversalTime().ToString('o'); job_url = "$jobUrl/$number/"; build_number = $number; result = $build.result; scm_revision = $revision; checks = $checks } |
    ConvertTo-Json -Depth 8 | Set-Content (Join-Path $directory 'verification.json') -Encoding utf8
if (@($checks | Where-Object { -not $_.passed }).Count) { throw 'HelloWorld verification failed. Inspect the saved console and report.' }
if ($SaveBrowserSession) {
    $loginPage = Invoke-WebRequest "$baseUrl/login" -SessionVariable browserSession
    $loginCrumb = [regex]::Match($loginPage.Content, '<input name="Jenkins-Crumb"[^>]*value="([^"]+)"').Groups[1].Value
    if (-not $loginCrumb) { throw 'Jenkins login form did not provide its CSRF token.' }
    $loginBody = @{ j_username = 'admin'; j_password = $password; from = '/'; 'Jenkins-Crumb' = $loginCrumb }
    Invoke-WebRequest "$baseUrl/j_spring_security_check" -Method Post -ContentType 'application/x-www-form-urlencoded' -Body $loginBody -WebSession $browserSession | Out-Null
    $cookies = @($browserSession.Cookies.GetCookies([Uri]$baseUrl) | ForEach-Object { [ordered]@{
        name = $_.Name; value = $_.Value; domain = $_.Domain; path = $_.Path; expires = -1
        httpOnly = $_.HttpOnly; secure = $_.Secure; sameSite = 'Lax'
    } })
    $secretDirectory = Join-Path $PSScriptRoot '.secrets'
    New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null
    @{ cookies = $cookies; origins = @() } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $secretDirectory 'browser.auth-state.json') -Encoding utf8
}
Write-Output "HelloWorld build $number succeeded; five checks passed."

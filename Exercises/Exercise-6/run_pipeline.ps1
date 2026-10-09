param([ValidateSet('normal', 'high_pending', 'high_pending_slow')][string]$Mode = 'normal')

$ErrorActionPreference = 'Stop'
$baseUrl = 'http://127.0.0.1:18006'
$password = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '.secrets/jenkins-admin')).Trim()
$credential = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$password"))
$headers = @{ Authorization = "Basic $credential" }
$session = $null
$deadline = (Get-Date).AddMinutes(5)
do {
    try {
        $crumb = Invoke-RestMethod -Uri "$baseUrl/crumbIssuer/api/json" -Headers $headers -SessionVariable session -TimeoutSec 5
        break
    } catch { Start-Sleep -Seconds 2 }
} while ((Get-Date) -lt $deadline)
if (-not $crumb) { throw 'Jenkins did not become ready for authenticated requests.' }
$headers[$crumb.crumbRequestField] = $crumb.crumb
$script = [Security.SecurityElement]::Escape([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Jenkinsfile')))
$parametersXml = '<properties><hudson.model.ParametersDefinitionProperty><parameterDefinitions><hudson.model.StringParameterDefinition><name>DELIVERY_MODE</name><description>Delivery simulation scenario</description><defaultValue>normal</defaultValue><trim>true</trim></hudson.model.StringParameterDefinition></parameterDefinitions></hudson.model.ParametersDefinitionProperty></properties>'
$jobXml = "<flow-definition plugin='workflow-job'><description>Exercise 6 delivery monitoring</description><keepDependencies>false</keepDependencies>$parametersXml<definition class='org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition' plugin='workflow-cps'><script>$script</script><sandbox>true</sandbox></definition><triggers/><disabled>false</disabled></flow-definition>"
$jobUrl = "$baseUrl/job/DeliveryMonitoring"
$existingJob = Invoke-WebRequest -Uri "$jobUrl/api/json" -Headers $headers -WebSession $session -SkipHttpErrorCheck
if ($existingJob.StatusCode -eq 404) {
    Invoke-WebRequest -Uri "$baseUrl/createItem?name=DeliveryMonitoring" -Method Post -ContentType 'application/xml' -Body $jobXml -Headers $headers -WebSession $session | Out-Null
} elseif ($existingJob.StatusCode -eq 200) {
    Invoke-WebRequest -Uri "$jobUrl/config.xml" -Method Post -ContentType 'application/xml' -Body $jobXml -Headers $headers -WebSession $session | Out-Null
} else { throw 'Could not inspect the lab Jenkins job.' }
$queued = Invoke-WebRequest -Uri "$jobUrl/buildWithParameters?DELIVERY_MODE=$Mode" -Method Post -Headers $headers -WebSession $session
$queueUrl = $queued.Headers.Location -join ''
if (-not $queueUrl) { throw 'Jenkins did not return a queue item.' }
if ($queueUrl.StartsWith('/')) { $queueUrl = $baseUrl + $queueUrl }
$deadline = (Get-Date).AddMinutes(20)
do {
    $queueItem = Invoke-RestMethod -Uri "$queueUrl/api/json" -Headers $headers -WebSession $session
    if ($queueItem.cancelled) { throw 'Jenkins queue item was cancelled.' }
    if ($queueItem.executable) { break }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
if (-not $queueItem.executable) { throw 'Jenkins did not start the build.' }
$number = $queueItem.executable.number
do {
    $build = Invoke-RestMethod -Uri "$jobUrl/$number/api/json" -Headers $headers -WebSession $session
    if (-not $build.building) { break }
    Start-Sleep -Seconds 3
} while ((Get-Date) -lt $deadline)
$evidenceDirectory = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
$console = Invoke-WebRequest -Uri "$jobUrl/$number/consoleText" -Headers $headers -WebSession $session
[IO.File]::WriteAllText((Join-Path $evidenceDirectory "jenkins-$Mode.txt"), [string]$console.Content)
[ordered]@{ checked_at_utc = (Get-Date).ToUniversalTime().ToString('o'); mode = $Mode; build_number = $number
    result = $build.result; building = $build.building; duration_ms = $build.duration; job_url = "$jobUrl/$number/" } |
    ConvertTo-Json | Set-Content (Join-Path $evidenceDirectory "jenkins-$Mode.json") -Encoding utf8
if ($build.building -or $build.result -ne 'SUCCESS') { throw "Jenkins build $number did not succeed. Inspect the saved console output." }
Write-Output "Jenkins build $number succeeded ($Mode)."

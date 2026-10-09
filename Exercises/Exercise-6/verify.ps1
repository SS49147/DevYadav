param([ValidateSet('normal', 'high_pending', 'high_pending_slow')][string]$Mode = 'normal')

$ErrorActionPreference = 'Stop'
$prometheusUrl = 'http://127.0.0.1:13906'
$grafanaUrl = 'http://127.0.0.1:13006'
$password = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '.secrets/grafana-admin')).Trim()
$headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$password")) }
$checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [bool]$Passed, $Details) {
    $checks.Add([ordered]@{ name = $Name; passed = $Passed; details = $Details })
    if (-not $Passed) { throw "Verification failed: $Name" }
}
function Query([string]$Expression) {
    $response = Invoke-RestMethod "$prometheusUrl/api/v1/query?query=$([Uri]::EscapeDataString($Expression))" -TimeoutSec 10
    if ($response.status -ne 'success') { throw "Prometheus query failed: $Expression" }
    return $response.data.result
}
function Metric([string]$Text, [string]$Name) {
    $match = [regex]::Match($Text, "(?m)^$Name ([0-9.eE+-]+)\r?$")
    if (-not $match.Success) { throw "Metric not found: $Name" }
    return [double]::Parse($match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
}
$deadline = (Get-Date).AddMinutes(3)
do {
    try {
        $targets = (Invoke-RestMethod "$prometheusUrl/api/v1/targets" -TimeoutSec 5).data.activeTargets
        $health = Invoke-RestMethod "$grafanaUrl/api/health" -TimeoutSec 5
        if ($targets.Count -eq 2 -and @($targets | Where-Object health -ne 'up').Count -eq 0 -and $health.database -eq 'ok') { break }
    } catch { }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
try {
    Check 'Both Prometheus scrape targets are up' ($targets.Count -eq 2 -and @($targets | Where-Object health -ne 'up').Count -eq 0) @($targets | Select-Object scrapeUrl, health, lastError)
    Check 'Grafana database is healthy' ($health.database -eq 'ok') $health
    $first = [string](Invoke-WebRequest 'http://127.0.0.1:18000/metrics' -TimeoutSec 10).Content
    $pending = Metric $first 'pending_deliveries'
    $onWay = Metric $first 'on_the_way_deliveries'
    $total = Metric $first 'total_deliveries'
    $count = Metric $first 'average_delivery_time_count'
    $mean = (Metric $first 'average_delivery_time_sum') / $count
    $minimumPending = if ($Mode -eq 'normal') { 10 } else { 50 }
    $maximumPending = if ($Mode -eq 'normal') { 20 } else { 100 }
    Check 'Simulator metrics match the selected scenario' ($pending -ge $minimumPending -and $pending -le $maximumPending -and $onWay -ge 5 -and $onWay -le 20 -and ($total - $pending - $onWay) -ge 30 -and ($total - $pending - $onWay) -le 70 -and $mean -ge 15 -and $mean -le 45) @{ total = $total; pending = $pending; on_the_way = $onWay; observations = $count; observed_mean_seconds = $mean }
    Start-Sleep -Seconds 3
    $second = [string](Invoke-WebRequest 'http://127.0.0.1:18000/metrics' -TimeoutSec 10).Content
    $nextCount = Metric $second 'average_delivery_time_count'
    Check 'Simulator continues producing observations' ($nextCount -gt $count) @{ before = $count; after = $nextCount }
    $dashboard = (Invoke-RestMethod "$grafanaUrl/api/dashboards/uid/delivery-monitoring" -Headers $headers -TimeoutSec 10).dashboard
    $expectedQueries = @('total_deliveries', 'pending_deliveries', 'on_the_way_deliveries', 'average_delivery_time_sum / average_delivery_time_count')
    $metricPanels = @($dashboard.panels | Where-Object type -eq 'timeseries')
    Check 'Dashboard contains all four required metric panels' ($metricPanels.Count -eq 4 -and @($metricPanels | Where-Object { $_.targets[0].expr -notin $expectedQueries }).Count -eq 0) @($metricPanels | Select-Object title, targets)
    $dataSourceHealth = Invoke-RestMethod "$grafanaUrl/api/datasources/uid/delivery-prometheus/health" -Headers $headers -TimeoutSec 10
    Check 'Grafana can reach the Prometheus data source' ($dataSourceHealth.status -eq 'OK') $dataSourceHealth.message
    foreach ($expression in $expectedQueries) {
        $result = @(Query $expression)
        Check "Prometheus has data for $expression" ($result.Count -eq 1) $result
        $proxy = Invoke-RestMethod "$grafanaUrl/api/datasources/proxy/uid/delivery-prometheus/api/v1/query?query=$([Uri]::EscapeDataString($expression))" -Headers $headers -TimeoutSec 10
        Check "Grafana can query $expression" ($proxy.status -eq 'success' -and $proxy.data.result.Count -eq 1) $proxy.data.result
    }
    $deadline = (Get-Date).AddMinutes(2)
    do {
        $rules = @((Invoke-RestMethod "$prometheusUrl/api/v1/rules?type=alert" -TimeoutSec 10).data.groups.rules)
        $pendingRule = $rules | Where-Object name -eq 'HighPendingDeliveries'
        $timeRule = $rules | Where-Object name -eq 'HighAverageDeliveryTime'
        if ($Mode -eq 'normal' -or ($pendingRule.state -eq 'firing' -and ($Mode -ne 'high_pending_slow' -or $timeRule.state -eq 'firing'))) { break }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    Check 'Source alert rules and severities are loaded' ($pendingRule.labels.severity -eq 'warning' -and $pendingRule.duration -eq 15 -and $timeRule.labels.severity -eq 'critical' -and $timeRule.duration -eq 0) $rules
    if ($Mode -ne 'normal') { Check 'High pending deliveries alert is firing' ($pendingRule.state -eq 'firing') $pendingRule.state }
    if ($Mode -eq 'high_pending_slow') { Check 'High average delivery time alert is firing' ($timeRule.state -eq 'firing') $timeRule.state }
    $alerts = @(Query 'ALERTS{alertstate="firing"}')
    $grafanaAlerts = Invoke-RestMethod "$grafanaUrl/api/datasources/proxy/uid/delivery-prometheus/api/v1/query?query=$([Uri]::EscapeDataString('ALERTS{alertstate="firing"}'))" -Headers $headers -TimeoutSec 10
    Check 'Dashboard alert query is usable' ($grafanaAlerts.status -eq 'success') $grafanaAlerts.data.result
    if ($Mode -eq 'high_pending_slow') { Check 'Both firing alerts are visible through Grafana' ($grafanaAlerts.data.result.Count -eq 2) $grafanaAlerts.data.result }
} finally {
    $directory = Join-Path $PSScriptRoot 'evidence'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    [ordered]@{ checked_at_utc = (Get-Date).ToUniversalTime().ToString('o'); mode = $Mode; checks = @($checks.ToArray()) } |
        ConvertTo-Json -Depth 16 | Set-Content (Join-Path $directory "verification-$Mode.json") -Encoding utf8
}
Write-Output "$($checks.Count) monitoring checks passed ($Mode)."

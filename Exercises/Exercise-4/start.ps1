param([ValidateRange(1024, 65535)][int]$HostPort = 15004)

$ErrorActionPreference = 'Stop'
$labNames = @('exercise4-mysql', 'exercise4-redis', 'exercise4-flask', 'exercise4-flask-test')
$existingNames = docker ps -a --format '{{.Names}}'
if ($LASTEXITCODE -ne 0) { throw 'Docker is not available.' }
if (@($labNames | Where-Object { $_ -in $existingNames }).Count) { throw 'A lab container already exists. Inspect it before rerunning.' }
$existingNetworks = docker network ls --format '{{.Name}}'
if ($LASTEXITCODE -ne 0) { throw 'Docker network listing failed.' }
if ('my-bridge-net' -in $existingNetworks) { throw 'my-bridge-net already exists. It will not be overwritten.' }
$portCheck = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $HostPort)
try { $portCheck.Start() } finally { $portCheck.Stop() }

function Run-Docker {
    param([string[]]$Arguments)
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Docker command failed.' }
}
function Wait-About {
    $deadline = (Get-Date).AddSeconds(60)
    do {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$HostPort/about" -UseBasicParsing -TimeoutSec 3
            if ($response.StatusCode -eq 200 -and ($response.Content | ConvertFrom-Json).name -eq 'Simple REST API') { return $response }
        } catch { }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    throw 'The standalone Flask container did not respond.'
}

$evidencePath = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null
Run-Docker @('network', 'create', '--driver', 'bridge', '--label', 'devops.lab.exercise=4', 'my-bridge-net')
Run-Docker @('run', '-d', '--name', 'exercise4-flask-test', '--label', 'devops.lab.exercise=4', '-p', "127.0.0.1:${HostPort}:5001", 'flask-api:latest')
$standalone = Wait-About
[ordered]@{ checked_at_utc = (Get-Date).ToUniversalTime().ToString('o'); http_status = [int]$standalone.StatusCode
    url = "http://127.0.0.1:$HostPort/about"; body = ($standalone.Content | ConvertFrom-Json) } |
    ConvertTo-Json | Set-Content (Join-Path $evidencePath 'standalone.json') -Encoding utf8
Run-Docker @('stop', 'exercise4-flask-test')
Run-Docker @('rm', 'exercise4-flask-test')

$previousRootPassword = $env:MYSQL_ROOT_PASSWORD
try {
    $env:MYSQL_ROOT_PASSWORD = [guid]::NewGuid().ToString('N')
    Run-Docker @('run', '-d', '--name', 'exercise4-mysql', '--label', 'devops.lab.exercise=4',
        '--network', 'my-bridge-net', '--network-alias', 'mysql', '-e', 'MYSQL_ROOT_PASSWORD',
        '-e', 'MYSQL_DATABASE=devopsdb', 'mysql:latest')
} finally { $env:MYSQL_ROOT_PASSWORD = $previousRootPassword }
Run-Docker @('run', '-d', '--name', 'exercise4-redis', '--label', 'devops.lab.exercise=4',
    '--network', 'my-bridge-net', '--network-alias', 'redis', 'redis:latest')
Run-Docker @('run', '-d', '--name', 'exercise4-flask', '--label', 'devops.lab.exercise=4',
    '--network', 'my-bridge-net', '--network-alias', 'flask', '-p', "127.0.0.1:${HostPort}:5001", 'flask-api:latest')

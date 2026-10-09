param([ValidateRange(1024, 65535)][int]$HostPort = 15004)

$ErrorActionPreference = 'Stop'
function Read-DockerJson {
    param([string[]]$Arguments)
    $result = & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Docker inspection failed.' }
    return ($result -join "`n" | ConvertFrom-Json)
}
$network = (Read-DockerJson @('network', 'inspect', 'my-bridge-net'))[0]
if ($network.Driver -ne 'bridge' -or $network.Labels.'devops.lab.exercise' -ne '4') { throw 'Unexpected network driver or owner.' }
$expected = @('exercise4-flask', 'exercise4-mysql', 'exercise4-redis')
$members = @($network.Containers.PSObject.Properties.Value.Name)
if ($members.Count -ne 3 -or @($expected | Where-Object { $_ -notin $members }).Count) { throw 'The bridge network must contain all three lab containers.' }
foreach ($name in $expected) {
    $running = docker inspect --format '{{.State.Running}}' $name
    if ($LASTEXITCODE -ne 0 -or $running -ne 'true') { throw "$name is not running." }
}
$ports = Read-DockerJson @('inspect', '--format', '{{json .NetworkSettings.Ports}}', 'exercise4-flask')
if ($ports.'5001/tcp'[0].HostPort -ne "$HostPort" -or $ports.'5001/tcp'[0].HostIp -ne '127.0.0.1') {
    throw 'Flask port 5001 must be published on the selected loopback host port.'
}
foreach ($name in @('exercise4-mysql', 'exercise4-redis')) {
    $published = docker port $name
    if ($LASTEXITCODE -ne 0 -or $published) { throw 'Database/cache ports must not be published to the host.' }
}
$networkTests = docker exec exercise4-flask python verify_network.py
if ($LASTEXITCODE -ne 0) { throw 'DNS, ping or internal server connectivity failed.' }
$connections = $networkTests -join "`n" | ConvertFrom-Json
$databases = docker exec exercise4-mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -e "SHOW DATABASES;"'
if ($LASTEXITCODE -ne 0 -or 'devopsdb' -notin $databases) { throw 'MySQL did not contain the required devopsdb database.' }
$redis = docker exec exercise4-redis redis-cli ping
if ($LASTEXITCODE -ne 0 -or $redis -ne 'PONG') { throw 'Redis PING failed.' }
$url = "http://127.0.0.1:$HostPort/about"
$response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
$body = $response.Content | ConvertFrom-Json
if ($response.StatusCode -ne 200 -or $body.name -ne 'Simple REST API' -or $body.version -ne '1.0' -or
    $body.description -ne 'This is a simple REST API built with Flask.') { throw 'Unexpected API response.' }
$report = [ordered]@{
    checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    docker_engine = (docker version --format '{{.Server.Version}}')
    network = $network.Name
    driver = $network.Driver
    ipam = $network.IPAM.Config
    containers = $members
    flask_port = 5001
    host_port = $HostPort
    host_bind_address = '127.0.0.1'
    mysql_and_redis_host_ports_published = $false
    connectivity = $connections
    mysql_databases = @($databases)
    redis_ping = $redis
    request_url = $url
    http_status = [int]$response.StatusCode
    response = $body
}
$evidencePath = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null
$network | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidencePath 'network-inspection.json') -Encoding utf8
$report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidencePath 'verification.json') -Encoding utf8
$report | ConvertTo-Json -Depth 8

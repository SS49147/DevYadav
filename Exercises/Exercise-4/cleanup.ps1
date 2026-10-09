$ErrorActionPreference = 'Stop'
$labNames = @('exercise4-flask-test', 'exercise4-flask', 'exercise4-mysql', 'exercise4-redis')
$existing = @(docker ps -a --format '{{.Names}}')
if ($LASTEXITCODE -ne 0) { throw 'Docker is unavailable; cleanup stopped.' }
$targets = @($labNames | Where-Object { $_ -in $existing })
foreach ($name in $targets) {
    $labelsJson = docker inspect --format '{{json .Config.Labels}}' $name
    if ($LASTEXITCODE -ne 0 -or ($labelsJson | ConvertFrom-Json).'devops.lab.exercise' -ne '4') {
        throw "Refusing to remove ${name}: it is not labelled as this exercise."
    }
}
$existingNetworks = docker network ls --format '{{.Name}}'
if ($LASTEXITCODE -ne 0) { throw 'Docker network listing failed; cleanup stopped.' }
$networkExists = 'my-bridge-net' -in $existingNetworks
if ($networkExists) {
    $networkJson = docker network inspect my-bridge-net
    if ($LASTEXITCODE -ne 0) { throw 'Network inspection failed.' }
    $network = ($networkJson -join "`n" | ConvertFrom-Json)[0]
    if ($network.Labels.'devops.lab.exercise' -ne '4' -or
        @($network.Containers.PSObject.Properties.Value.Name | Where-Object { $_ -notin $labNames }).Count) {
        throw 'Refusing to remove a network owned or used by other work.'
    }
}
foreach ($name in $targets) {
    docker stop $name | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Stopping a lab container failed.' }
    docker rm --volumes $name | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Removing a lab container failed.' }
}
if ($networkExists) {
    docker network rm my-bridge-net | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Removing the lab network failed.' }
}
$remaining = @(docker ps -a --format '{{.Names}}' | Where-Object { $_ -in $labNames })
if ($LASTEXITCODE -ne 0) { throw 'Could not verify container removal.' }
$remainingNetworks = docker network ls --format '{{.Name}}'
if ($LASTEXITCODE -ne 0) { throw 'Could not verify network removal.' }
$networkStillExists = 'my-bridge-net' -in $remainingNetworks
if ($remaining.Count -or $networkStillExists) { throw 'Cleanup was incomplete.' }
$evidencePath = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null
[ordered]@{ checked_at_utc = (Get-Date).ToUniversalTime().ToString('o'); removed_containers = $targets
    removed_network = $networkExists; remaining_lab_containers = $remaining; network_still_exists = $networkStillExists } |
    ConvertTo-Json | Set-Content (Join-Path $evidencePath 'cleanup.json') -Encoding utf8

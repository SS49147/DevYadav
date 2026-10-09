param(
    [Parameter(Mandatory = $true)][uri]$ServiceUrl,
    [string]$ClusterProfile = 'devops-exercises',
    [string]$Minikube = 'minikube'
)

$ErrorActionPreference = 'Stop'
function Read-Resource {
    param([string[]]$Arguments)
    $result = & $Minikube --profile $ClusterProfile kubectl -- --context $ClusterProfile -n exercise2 @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Kubernetes query failed.' }
    return ($result -join "`n" | ConvertFrom-Json)
}

$deployment = Read-Resource @('get', 'deployment', 'flask-app', '-o', 'json')
if ($deployment.spec.replicas -ne 1 -or $deployment.status.readyReplicas -ne 1 -or
    $deployment.status.availableReplicas -ne 1) { throw 'Expected one ready and available replica.' }
$container = $deployment.spec.template.spec.containers[0]
if ($container.image -ne 'flask-app:latest' -or $container.imagePullPolicy -ne 'Never' -or
    $container.ports[0].containerPort -ne 15000) { throw 'Deployment differs from the required image or port.' }
$pods = Read-Resource @('get', 'pods', '-l', 'app=flask-app', '-o', 'json')
$pod = @($pods.items | Where-Object { -not $_.metadata.deletionTimestamp })
if ($pod.Count -ne 1 -or $pod[0].status.phase -ne 'Running' -or
    -not ($pod[0].status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })) {
    throw 'Expected one running, ready Flask pod.'
}
$service = Read-Resource @('get', 'service', 'flask-app-service', '-o', 'json')
if ($service.spec.type -ne 'NodePort' -or $service.spec.ports[0].port -ne 15000 -or
    $service.spec.ports[0].targetPort -ne 15000 -or $service.spec.selector.app -ne 'flask-app') {
    throw 'Service ports or selector are incorrect.'
}
$slices = Read-Resource @('get', 'endpointslices', '-l', 'kubernetes.io/service-name=flask-app-service', '-o', 'json')
$addresses = @($slices.items.endpoints | Where-Object { $_.conditions.ready -eq $true } |
    ForEach-Object { $_.addresses })
if ($pod[0].status.podIP -notin $addresses) { throw 'Service has no ready endpoint for the pod.' }
$response = Invoke-WebRequest -Uri $ServiceUrl -UseBasicParsing -TimeoutSec 30
if ($response.StatusCode -ne 200 -or $response.Content -ne 'Hello from Flask on Kubernetes!') {
    throw 'Unexpected Flask response.'
}
$report = [ordered]@{
    checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    profile = $ClusterProfile
    namespace = 'exercise2'
    deployment = $deployment.metadata.name
    replicas = $deployment.spec.replicas
    ready_replicas = $deployment.status.readyReplicas
    pod = $pod[0].metadata.name
    pod_ip = $pod[0].status.podIP
    node = $pod[0].spec.nodeName
    image = $container.image
    image_id = $pod[0].status.containerStatuses[0].imageID
    image_pull_policy = $container.imagePullPolicy
    container_port = $container.ports[0].containerPort
    service_type = $service.spec.type
    service_port = $service.spec.ports[0].port
    target_port = $service.spec.ports[0].targetPort
    node_port = $service.spec.ports[0].nodePort
    ready_endpoints = $addresses
    request_url = $ServiceUrl.AbsoluteUri
    http_status = [int]$response.StatusCode
    response = $response.Content
    checks_passed = 6
}
$evidencePath = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null
$report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $evidencePath 'verification.json') -Encoding utf8
$report | ConvertTo-Json -Depth 5

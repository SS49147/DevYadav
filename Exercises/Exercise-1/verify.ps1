param(
    [Parameter(Mandatory = $true)]
    [uri]$ServiceUrl,
    [string]$ClusterProfile = 'devops-exercises',
    [string]$Minikube = 'minikube'
)

$ErrorActionPreference = 'Stop'

function Read-KubernetesResource {
    param([string[]]$Arguments)
    $resourceJson = & $Minikube --profile $ClusterProfile kubectl -- @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Kubernetes resource query failed.' }
    return ($resourceJson -join "`n" | ConvertFrom-Json)
}

$pod = Read-KubernetesResource @('-n', 'exercise1', 'get', 'pod', 'hello-k8s', '-o', 'json')
if ($pod.status.phase -ne 'Running' -or
    -not ($pod.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })) {
    throw 'hello-k8s is not running and ready.'
}
if ($pod.spec.containers[0].image -notin @('nginx', 'nginx:latest') -or
    $pod.spec.containers[0].ports[0].containerPort -ne 80) {
    throw 'The pod must use the Nginx image and container port 80.'
}

$service = Read-KubernetesResource @('-n', 'exercise1', 'get', 'service', 'hello-k8s', '-o', 'json')
if ($service.spec.type -ne 'NodePort' -or $service.spec.ports[0].port -ne 80 -or
    $service.spec.ports[0].targetPort -ne 80 -or $service.spec.ports[0].nodePort -lt 30000 -or
    $service.spec.selector.run -ne 'hello-k8s') {
    throw 'The NodePort service is not configured for the Nginx pod.'
}

$slices = Read-KubernetesResource @('-n', 'exercise1', 'get', 'endpointslices',
    '-l', 'kubernetes.io/service-name=hello-k8s', '-o', 'json')
$readyAddresses = @($slices.items.endpoints | Where-Object { $_.conditions.ready -eq $true } |
    ForEach-Object { $_.addresses })
if ($pod.status.podIP -notin $readyAddresses) { throw 'The service has no ready endpoint for hello-k8s.' }

$response = Invoke-WebRequest -Uri $ServiceUrl -UseBasicParsing -TimeoutSec 30
if ($response.StatusCode -ne 200 -or $response.Content -notmatch '<h1>Welcome to nginx!</h1>') {
    throw 'The service did not return the Nginx welcome page with HTTP 200.'
}

$report = [ordered]@{
    checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    profile = $ClusterProfile
    namespace = 'exercise1'
    pod = $pod.metadata.name
    phase = $pod.status.phase
    ready = $true
    image = $pod.spec.containers[0].image
    image_id = $pod.status.containerStatuses[0].imageID
    pod_ip = $pod.status.podIP
    service_type = $service.spec.type
    service_port = $service.spec.ports[0].port
    node_port = $service.spec.ports[0].nodePort
    ready_endpoints = $readyAddresses
    request_url = $ServiceUrl.AbsoluteUri
    http_status = [int]$response.StatusCode
    server = ($response.Headers.Server -join ', ')
    welcome_page = $true
    checks_passed = 5
}
$evidenceDirectory = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'verification.json') -Encoding utf8
[System.IO.File]::WriteAllText((Join-Path $evidenceDirectory 'nginx-response.html'),
    [string]$response.Content, [System.Text.UTF8Encoding]::new($false))
$report | ConvertTo-Json -Depth 5

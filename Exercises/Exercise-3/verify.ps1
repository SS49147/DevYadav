param(
    [string]$ClusterProfile = 'devops-exercises',
    [string]$Minikube = 'minikube'
)

$ErrorActionPreference = 'Stop'
function Invoke-Kube {
    param([string[]]$Arguments)
    $output = & $Minikube --profile $ClusterProfile kubectl -- --context $ClusterProfile @Arguments
    if ($LASTEXITCODE -ne 0) { throw "kubectl failed: $($Arguments -join ' ')" }
    return $output
}
function Read-Resource {
    param([string[]]$Arguments)
    return ((Invoke-Kube $Arguments) -join "`n" | ConvertFrom-Json)
}
function Wait-Replicas {
    param([int]$Count)
    $deadline = (Get-Date).AddSeconds(180)
    do {
        $rs = Read-Resource @('-n', 'exercise3', 'get', 'rs', 'flashsale-rs', '-o', 'json')
        $list = Read-Resource @('-n', 'exercise3', 'get', 'pods', '-l', 'app=flashsale', '-o', 'json')
        $pods = @($list.items | Where-Object { -not $_.metadata.deletionTimestamp })
        $ready = @($pods | Where-Object {
            $_.status.phase -eq 'Running' -and
            ($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })
        })
        if ($rs.spec.replicas -eq $Count -and $rs.status.replicas -eq $Count -and
            $rs.status.readyReplicas -eq $Count -and $pods.Count -eq $Count -and $ready.Count -eq $Count) {
            return $pods
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw "ReplicaSet did not reach $Count ready pods."
}
function Snapshot-Pods {
    param([object[]]$Pods)
    return @($Pods | ForEach-Object {
        [ordered]@{ name = $_.metadata.name; uid = $_.metadata.uid; ip = $_.status.podIP
            node = $_.spec.nodeName; image_id = $_.status.containerStatuses[0].imageID }
    })
}

$nodes = Read-Resource @('get', 'nodes', '-o', 'json')
if (@($nodes.items).Count -ne 1 -or
    -not ($nodes.items[0].status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })) {
    throw 'This exercise requires one ready node.'
}
$rs = Read-Resource @('-n', 'exercise3', 'get', 'rs', 'flashsale-rs', '-o', 'json')
$container = $rs.spec.template.spec.containers[0]
if ($container.image -ne 'anas2694/flashsale:1.0' -or $container.ports[0].containerPort -ne 5000 -or
    $container.readinessProbe.httpGet.path -ne '/health' -or $container.readinessProbe.httpGet.port -ne 5000 -or
    $container.livenessProbe.httpGet.path -ne '/health' -or $container.livenessProbe.httpGet.port -ne 5000 -or
    $container.resources.requests.cpu -ne '100m' -or $container.resources.requests.memory -ne '128Mi' -or
    $container.resources.limits.cpu -ne '500m' -or $container.resources.limits.memory -ne '256Mi') {
    throw 'ReplicaSet image, port, probes or resources differ from the exercise.'
}
$initial = @(Wait-Replicas 3)
$initialSnapshot = Snapshot-Pods $initial
Invoke-Kube @('-n', 'exercise3', 'scale', 'rs', 'flashsale-rs', '--replicas=5') | Out-Host
$scaled = @(Wait-Replicas 5)
$scaledSnapshot = Snapshot-Pods $scaled
if (@($scaled.metadata.uid | Where-Object { $_ -notin $initial.metadata.uid }).Count -ne 2) {
    throw 'Scaling did not add exactly two pods.'
}
if (@($scaled.spec.nodeName | Select-Object -Unique).Count -ne 1) { throw 'Pods are not on one node.' }
$victim = $scaled[0]
if (-not ($victim.metadata.ownerReferences | Where-Object { $_.uid -eq $rs.metadata.uid -and $_.kind -eq 'ReplicaSet' })) {
    throw 'Refusing to delete a pod not owned by this exercise ReplicaSet.'
}
Invoke-Kube @('-n', 'exercise3', 'delete', 'pod', $victim.metadata.name, '--wait=true') | Out-Host
$recovered = @(Wait-Replicas 5)
$replacement = @($recovered | Where-Object { $_.metadata.uid -notin $scaled.metadata.uid })
if ($replacement.Count -ne 1 -or $victim.metadata.uid -in $recovered.metadata.uid) {
    throw 'ReplicaSet did not replace exactly the deleted pod.'
}
$service = Read-Resource @('-n', 'exercise3', 'get', 'service', 'flashsale-svc', '-o', 'json')
if ($service.spec.type -ne 'ClusterIP' -or $service.spec.ports[0].port -ne 80 -or
    $service.spec.ports[0].targetPort -ne 5000 -or $service.spec.selector.app -ne 'flashsale') {
    throw 'The service must route port 80 to flashsale pods on port 5000.'
}
$endpointDeadline = (Get-Date).AddSeconds(30)
do {
    $slices = Read-Resource @('-n', 'exercise3', 'get', 'endpointslices', '-l', 'kubernetes.io/service-name=flashsale-svc', '-o', 'json')
    $addresses = @($slices.items.endpoints | Where-Object { $_.conditions.ready -eq $true } | ForEach-Object { $_.addresses })
    if ($addresses.Count -eq 5 -and -not (@($recovered.status.podIP | Where-Object { $_ -notin $addresses }).Count)) { break }
    Start-Sleep -Seconds 1
} while ((Get-Date) -lt $endpointDeadline)
if ($addresses.Count -ne 5 -or @($recovered.status.podIP | Where-Object { $_ -notin $addresses }).Count) {
    throw 'The service does not have all five ready pod endpoints.'
}
$httpTest = @'
import collections, json, sys, urllib.request
base = 'http://flashsale-svc.exercise3.svc.cluster.local'
expected = set(sys.argv[1].split(','))
def get(path):
    with urllib.request.urlopen(base + path, timeout=10) as response:
        assert response.status == 200
        return json.load(response)
home = get('/')
health = get('/health')
assert home['message'] == 'Welcome to Big Sale!' and home['pod'] in expected
assert health['status'] == 'healthy' and health['pod'] in expected
counts = collections.Counter()
for _ in range(100):
    purchase = get('/buy?user=lab-test')
    assert purchase['status'] == 'success' and purchase['user'] == 'lab-test'
    assert purchase['item'] in ['Smartphone', 'Shoes', 'Headphones', 'Laptop']
    assert purchase['served_by_pod'] in expected
    counts[purchase['served_by_pod']] += 1
assert len(counts) > 1, 'Requests did not demonstrate distribution across pods'
print(json.dumps({'home': home, 'health': health, 'buy_requests': 100, 'served_by_pod': dict(counts)}))
'@
$http = (Invoke-Kube @('-n', 'exercise3', 'exec', $recovered[0].metadata.name, '--',
    'python', '-c', $httpTest, ($recovered.metadata.name -join ','))) -join "`n" | ConvertFrom-Json
$report = [ordered]@{
    checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    profile = $ClusterProfile
    namespace = 'exercise3'
    node_count = @($nodes.items).Count
    replicaset = 'flashsale-rs'
    image = $container.image
    initial_pods = $initialSnapshot
    scaled_pods = $scaledSnapshot
    deleted_pod = $victim.metadata.name
    deleted_uid = $victim.metadata.uid
    replacement_pod = $replacement[0].metadata.name
    replacement_uid = $replacement[0].metadata.uid
    recovered_pods = (Snapshot-Pods $recovered)
    service_type = $service.spec.type
    ready_endpoints = $addresses
    http = $http
}
$evidencePath = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidencePath 'verification.json') -Encoding utf8
$report | ConvertTo-Json -Depth 8

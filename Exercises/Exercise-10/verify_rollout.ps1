param([string]$Minikube = 'minikube', [string]$ClusterProfile = 'devops-multinode')

$ErrorActionPreference = 'Stop'
function Kube ([string[]]$Arguments) {
    $output = & $Minikube --profile $ClusterProfile kubectl -- --context $ClusterProfile @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Kubectl failed: $($Arguments -join ' ')" }
    return $output -join "`n"
}
$deployment = Kube -Arguments @('-n', 'default', 'get', 'deployment', 'shopping-cart', '-o', 'json') | ConvertFrom-Json
if ($deployment.metadata.labels.'devops.lab.exercise' -ne '10') { throw 'Refusing to restart a Deployment not owned by Exercise 10.' }
if ($deployment.spec.strategy.rollingUpdate.maxSurge -ne 0 -or $deployment.spec.strategy.rollingUpdate.maxUnavailable -ne 1) {
    throw 'The cart rollout must use maxSurge 0 and maxUnavailable 1.'
}
$before = (Kube -Arguments @('-n', 'default', 'get', 'pods', '-l', 'app=shopping-cart', '-o', 'json') | ConvertFrom-Json).items
if ($before.Count -ne 3 -or $deployment.status.availableReplicas -ne 3) { throw 'Start with three available cart replicas.' }
$beforeUids = @($before.metadata.uid)
$samples = [Collections.Generic.List[object]]::new()
Kube -Arguments @('-n', 'default', 'rollout', 'restart', 'deployment/shopping-cart') | Out-Host
$deadline = (Get-Date).AddSeconds(180)
do {
    $deployment = Kube -Arguments @('-n', 'default', 'get', 'deployment', 'shopping-cart', '-o', 'json') | ConvertFrom-Json
    $pods = (Kube -Arguments @('-n', 'default', 'get', 'pods', '-l', 'app=shopping-cart', '-o', 'json') | ConvertFrom-Json).items
    $samples.Add(@{ checked_at_utc = (Get-Date).ToUniversalTime().ToString('o'); available = $deployment.status.availableReplicas; updated = $deployment.status.updatedReplicas })
    $oldPods = @($pods | Where-Object { $_.metadata.uid -in $beforeUids })
    if ($deployment.status.observedGeneration -ge $deployment.metadata.generation -and
        $deployment.status.updatedReplicas -eq 3 -and $deployment.status.availableReplicas -eq 3 -and
        $oldPods.Count -eq 0 -and $pods.Count -eq 3) { break }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
if ($oldPods.Count -ne 0 -or $pods.Count -ne 3 -or $deployment.status.availableReplicas -ne 3) { throw 'The cart rollout did not replace all three pods before the timeout.' }
if (@($samples | Where-Object { $_.available -lt 2 }).Count -gt 0) { throw 'Fewer than two cart replicas remained available during the rollout.' }
if (@($pods.spec.nodeName | Sort-Object -Unique).Count -ne 3) { throw 'Cart replicas no longer occupy three distinct nodes.' }
$carts = @($pods | ForEach-Object {
    $content = Kube -Arguments @('-n', 'default', 'exec', $_.metadata.name, '--', 'python', '-c', "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:80/cart').read().decode())")
    $cart = $content | ConvertFrom-Json -NoEnumerate
    if ($cart.Count -ne 0) { throw 'A freshly replaced cart pod was not empty.' }
    @{ pod = $_.metadata.name; uid = $_.metadata.uid; node = $_.spec.nodeName; cart = $cart }
})
$report = [ordered]@{
    checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    profile = $ClusterProfile
    strategy = $deployment.spec.strategy
    previous_uids = $beforeUids
    replacement_pods = $carts
    availability_samples = $samples.ToArray()
    passed = $true
    cart_data_lost_on_restart = $true
}
$directory = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $directory 'rollout.json') -Encoding utf8
Write-Output 'All three cart pods were replaced on three nodes, with at least two available in every sample. New carts are empty.'

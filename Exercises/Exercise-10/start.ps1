param([string]$Minikube = 'minikube', [string]$ClusterProfile = 'devops-multinode')

$ErrorActionPreference = 'Stop'
function Run-Min ([string[]]$Arguments) {
    & $Minikube @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Minikube command failed: $($Arguments -join ' ')" }
}
Run-Min -Arguments @('start', '--profile', $ClusterProfile, '--nodes', '3', '--driver', 'docker', '--container-runtime', 'containerd', '--cpus', '2', '--memory', '2048', '--kubernetes-version', 'v1.37.0', '--keep-context', '--preload=false')
& $Minikube --profile $ClusterProfile kubectl -- --context $ClusterProfile wait nodes --all --for=condition=Ready --timeout=180s
if ($LASTEXITCODE -ne 0) {
    Write-Output 'Node readiness timed out. Loading the cluster networking images through the host Docker cache.'
    $daemonSets = (& $Minikube --profile $ClusterProfile kubectl -- --context $ClusterProfile -n kube-system get daemonsets kindnet kube-proxy -o json) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect networking image references.' }
    $networkImages = ($daemonSets | ConvertFrom-Json).items.spec.template.spec.containers.image | Sort-Object -Unique
    foreach ($image in $networkImages) {
        if ($image -notmatch '^(docker\.io/kindest/kindnetd:|registry\.k8s\.io/kube-proxy:)') { throw 'Unexpected networking image reference; inspect the cluster before retrying.' }
        docker pull $image
        if ($LASTEXITCODE -ne 0) { throw "Networking image download failed: $image" }
        Run-Min -Arguments @('--profile', $ClusterProfile, 'image', 'load', $image)
    }
    Run-Min -Arguments @('--profile', $ClusterProfile, 'kubectl', '--', '--context', $ClusterProfile, 'wait', 'nodes', '--all', '--for=condition=Ready', '--timeout=300s')
}
Run-Min -Arguments @('--profile', $ClusterProfile, 'addons', 'enable', 'registry')
foreach ($kind in @('product', 'shopping')) {
    $image = if ($kind -eq 'product') { 'product-catalog:latest' } else { 'shopping-cart:latest' }
    docker build -t $image -f (Join-Path $PSScriptRoot "Dockerfile.$kind") $PSScriptRoot
    if ($LASTEXITCODE -ne 0) { throw "Image build failed: $image" }
    $testOutput = docker run --rm $image python -m unittest -v 2>&1
    $testExitCode = $LASTEXITCODE
    $testText = ($testOutput | ForEach-Object { [string]$_ }) -join "`n"
    Write-Output $testText
    $evidenceDirectory = Join-Path $PSScriptRoot 'evidence'
    New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    [ordered]@{ checked_at_utc = (Get-Date).ToUniversalTime().ToString('o'); image = $image; exit_code = $testExitCode; output = $testText } |
        ConvertTo-Json | Set-Content (Join-Path $evidenceDirectory "unit-$kind.json") -Encoding utf8
    if ($testExitCode -ne 0) { throw "Application tests failed: $image" }
    Run-Min -Arguments @('--profile', $ClusterProfile, 'image', 'load', $image)
}
foreach ($resource in @('deployment/product-catalog', 'deployment/shopping-cart', 'service/product-catalog-service', 'service/shopping-cart-service')) {
    $existing = (& $Minikube --profile $ClusterProfile kubectl -- --context $ClusterProfile -n default get $resource --ignore-not-found -o json) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect $resource" }
    if ($existing) {
        $owner = ($existing | ConvertFrom-Json).metadata.labels.'devops.lab.exercise'
        if ($owner -ne '10') { throw "Refusing to replace an unrelated $resource" }
    }
}
foreach ($manifest in @('product_catalog_deployment.yaml', 'shopping_cart_deployment.yaml', 'product_catalog_service.yaml', 'shopping_cart_service.yaml')) {
    Run-Min -Arguments @('--profile', $ClusterProfile, 'kubectl', '--', '--context', $ClusterProfile, 'apply', '-f', (Join-Path $PSScriptRoot $manifest))
}
foreach ($deployment in @('product-catalog', 'shopping-cart')) {
    Run-Min -Arguments @('--profile', $ClusterProfile, 'kubectl', '--', '--context', $ClusterProfile, '-n', 'default', 'rollout', 'status', "deployment/$deployment", '--timeout=180s')
}
Write-Output 'Both applications are deployed on the dedicated three-node profile.'

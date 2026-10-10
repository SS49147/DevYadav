param([string]$Minikube = 'minikube', [string]$ClusterProfile = 'devops-multinode', [switch]$RequireEmptyCarts)

$ErrorActionPreference = 'Stop'
$checks = [Collections.Generic.List[object]]::new()
$tunnels = [Collections.Generic.List[object]]::new()
$directory = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
function Kube ([string[]]$Arguments) {
    $output = & $Minikube --profile $ClusterProfile kubectl -- --context $ClusterProfile @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Kubectl failed: $($Arguments -join ' ')" }
    return $output -join "`n"
}
function Check ([string]$Name, [bool]$Passed, $Details) {
    $checks.Add([ordered]@{ name = $Name; passed = $Passed; details = $Details })
    if (-not $Passed) { throw "Verification failed: $Name" }
}
function Service-Url ([string]$Name) {
    $binary = (Get-Command $Minikube -CommandType Application | Select-Object -First 1).Source
    $stdout = Join-Path $directory "$Name.stdout.log"
    $stderr = Join-Path $directory "$Name.stderr.log"
    $options = @{ FilePath = $binary; ArgumentList = @('--profile', $ClusterProfile, 'service', $Name, '--namespace', 'default', '--url'); RedirectStandardOutput = $stdout; RedirectStandardError = $stderr; PassThru = $true }
    if ($IsWindows) { $options.WindowStyle = 'Hidden' }
    $process = Start-Process @options
    $tunnels.Add($process)
    $deadline = (Get-Date).AddSeconds(60)
    do {
        $text = if (Test-Path $stdout) { Get-Content $stdout -Raw } else { '' }
        if ([string]::IsNullOrEmpty($text)) {
            if ($process.HasExited -and $process.ExitCode -ne 0) { throw "Minikube service forwarding failed for $Name" }
            Start-Sleep -Milliseconds 500
            continue
        }
        $pattern = if ($IsWindows) { 'http://127\.0\.0\.1:\d+' } else { 'http://[^\s|]+' }
        $match = [regex]::Match([string]$text, $pattern)
        if ($match.Success) { return $match.Value }
        if ($process.HasExited -and $process.ExitCode -ne 0) { throw "Minikube service forwarding failed for $Name" }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "No reachable service URL was returned for $Name"
}
function Pod-Get ([string]$PodName, [string]$Path) {
    $code = "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:80$Path').read().decode())"
    return (Kube -Arguments @('-n', 'default', 'exec', $PodName, '--', 'python', '-c', $code)) | ConvertFrom-Json -NoEnumerate
}
try {
    Kube -Arguments @('wait', 'nodes', '--all', '--for=condition=Ready', '--timeout=180s') | Out-Null
    foreach ($name in @('product-catalog', 'shopping-cart')) { Kube -Arguments @('-n', 'default', 'rollout', 'status', "deployment/$name", '--timeout=180s') | Out-Null }
    $nodes = (Kube -Arguments @('get', 'nodes', '-o', 'json') | ConvertFrom-Json).items
    Check 'Three Kubernetes nodes are Ready' ($nodes.Count -eq 3 -and @($nodes | Where-Object { @($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }).Count -ne 1 }).Count -eq 0) @($nodes | ForEach-Object { @{ name = $_.metadata.name; version = $_.status.nodeInfo.kubeletVersion; runtime = $_.status.nodeInfo.containerRuntimeVersion } })
    $catalogPods = (Kube -Arguments @('-n', 'default', 'get', 'pods', '-l', 'app=product-catalog', '-o', 'json') | ConvertFrom-Json).items
    $cartPods = (Kube -Arguments @('-n', 'default', 'get', 'pods', '-l', 'app=shopping-cart', '-o', 'json') | ConvertFrom-Json).items
    foreach ($application in @(@{ name = 'Product Catalog'; pods = $catalogPods; count = 2 }, @{ name = 'Shopping Cart'; pods = $cartPods; count = 3 })) {
        $pods = $application.pods
        Check "$($application.name) has the required ready replicas" ($pods.Count -eq $application.count -and @($pods | Where-Object { @($_.status.containerStatuses | Where-Object { -not $_.ready }).Count -gt 0 -or $_.status.phase -ne 'Running' }).Count -eq 0) @($pods | ForEach-Object { @{ pod = $_.metadata.name; node = $_.spec.nodeName; image_id = $_.status.containerStatuses[0].imageID } })
        Check "$($application.name) replicas occupy distinct nodes" (@($pods.spec.nodeName | Sort-Object -Unique).Count -eq $application.count) $pods.spec.nodeName
    }
    $replicaSets = (Kube -Arguments @('-n', 'default', 'get', 'replicasets', '-l', 'devops.lab.exercise=10', '-o', 'json') | ConvertFrom-Json).items
    Check 'Deployments own the two active ReplicaSets with 2 and 3 replicas' (@($replicaSets | Where-Object { $_.metadata.ownerReferences[0].kind -eq 'Deployment' -and $_.spec.replicas -eq 2 -and $_.status.readyReplicas -eq 2 }).Count -eq 1 -and @($replicaSets | Where-Object { $_.metadata.ownerReferences[0].kind -eq 'Deployment' -and $_.spec.replicas -eq 3 -and $_.status.readyReplicas -eq 3 }).Count -eq 1) @($replicaSets | ForEach-Object { @{ name = $_.metadata.name; owner = $_.metadata.ownerReferences[0].name; desired = $_.spec.replicas; ready = $_.status.readyReplicas } })
    $deadline = (Get-Date).AddMinutes(2)
    do {
        $nodes = (Kube -Arguments @('get', 'nodes', '-o', 'json') | ConvertFrom-Json).items
        $imageInventory = @($nodes | ForEach-Object { @{ node = $_.metadata.name; product_loaded = @($_.status.images.names | Where-Object { $_ -like '*product-catalog:latest' }).Count -gt 0; cart_loaded = @($_.status.images.names | Where-Object { $_ -like '*shopping-cart:latest' }).Count -gt 0 } })
        if (@($imageInventory | Where-Object { -not $_.product_loaded -or -not $_.cart_loaded }).Count -eq 0) { break }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    Check 'Both application images are cached on all three nodes' (@($imageInventory | Where-Object { -not $_.product_loaded -or -not $_.cart_loaded }).Count -eq 0) $imageInventory
    $registryPods = @((Kube -Arguments @('-n', 'kube-system', 'get', 'pods', '-o', 'json') | ConvertFrom-Json).items | Where-Object { $_.metadata.name -like 'registry-*' })
    Check 'Registry addon is running' ($registryPods.Count -ge 1 -and @($registryPods | Where-Object { @($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }).Count -ne 1 }).Count -eq 0) @($registryPods | ForEach-Object { @{ name = $_.metadata.name; node = $_.spec.nodeName; phase = $_.status.phase } })
    foreach ($service in @(@{ name = 'product-catalog-service'; count = 2 }, @{ name = 'shopping-cart-service'; count = 3 })) {
        $definition = Kube -Arguments @('-n', 'default', 'get', 'service', $service.name, '-o', 'json') | ConvertFrom-Json
        $endpoints = (Kube -Arguments @('-n', 'default', 'get', 'endpointslices', '-l', "kubernetes.io/service-name=$($service.name)", '-o', 'json') | ConvertFrom-Json).items.endpoints
        Check "$($service.name) has the expected ready endpoints" ($definition.spec.type -eq 'NodePort' -and @($endpoints | Where-Object { $_.conditions.ready }).Count -eq $service.count) @{ namespace = $definition.metadata.namespace; node_port = $definition.spec.ports[0].nodePort; endpoints = @($endpoints | Select-Object addresses, nodeName, conditions) }
    }
    $expectedProducts = @(@{ id = 1; name = 'Laptop'; price = 1200 }, @{ id = 2; name = 'Phone'; price = 800 }, @{ id = 3; name = 'Headphones'; price = 150 })
    foreach ($pod in $catalogPods) {
        $products = Pod-Get -PodName $pod.metadata.name -Path '/products'
        Check "Catalog pod $($pod.metadata.name) serves the source products" ($products.Count -eq 3 -and @($products | Where-Object { $product = $_; $expected = $expectedProducts | Where-Object { $_.id -eq $product.id }; -not $expected -or $product.name -ne $expected.name -or $product.price -ne $expected.price }).Count -eq 0) $products
    }
    $before = @($cartPods | ForEach-Object { @{ pod = $_.metadata.name; cart = (Pod-Get -PodName $_.metadata.name -Path '/cart') } })
    if ($RequireEmptyCarts) { Check 'All three source carts are initially empty' (@($before | Where-Object { $_.cart.Count -ne 0 }).Count -eq 0) $before }
    $catalogUrl = Service-Url -Name 'product-catalog-service'
    $cartUrl = Service-Url -Name 'shopping-cart-service'
    $response = Invoke-WebRequest "$catalogUrl/products" -TimeoutSec 10
    $products = $response.Content | ConvertFrom-Json -NoEnumerate
    Check 'Product Catalog NodePort returns HTTP 200 and the product list' ($response.StatusCode -eq 200 -and $products.Count -eq 3 -and $products[0].name -eq 'Laptop' -and $products[1].name -eq 'Phone' -and $products[2].name -eq 'Headphones') @{ url = "$catalogUrl/products"; status = $response.StatusCode; products = $products }
    $initialCart = Invoke-WebRequest "$cartUrl/cart" -TimeoutSec 10
    $initialItems = $initialCart.Content | ConvertFrom-Json -NoEnumerate
    Check 'Shopping Cart NodePort returns HTTP 200' ($initialCart.StatusCode -eq 200 -and (-not $RequireEmptyCarts -or $initialItems.Count -eq 0)) @{ url = "$cartUrl/cart"; status = $initialCart.StatusCode; cart = $initialItems }
    $item = @{ id = 1; name = 'Laptop'; quantity = 1 }
    $added = Invoke-WebRequest "$cartUrl/cart" -Method Post -ContentType 'application/json' -Body ($item | ConvertTo-Json -Compress) -TimeoutSec 10
    $addedItems = $added.Content | ConvertFrom-Json -NoEnumerate
    Check 'Adding the source item through NodePort returns HTTP 201' ($added.StatusCode -eq 201 -and $addedItems[-1].id -eq 1 -and $addedItems[-1].name -eq 'Laptop' -and $addedItems[-1].quantity -eq 1) @{ status = $added.StatusCode; cart = $addedItems }
    $after = @($cartPods | ForEach-Object { @{ pod = $_.metadata.name; cart = (Pod-Get -PodName $_.metadata.name -Path '/cart') } })
    if ($RequireEmptyCarts) { Check 'Source in-memory cart state exists in only the pod handling the POST' (@($after | Where-Object { $_.cart.Count -eq 1 }).Count -eq 1 -and @($after | Where-Object { $_.cart.Count -eq 0 }).Count -eq 2) $after }
    $cartState = @{ before = $before; after = $after; limitation = 'Each replica has its own in-memory cart; no shared database or session consistency is implemented.' }
} finally {
    foreach ($process in $tunnels) { if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force } }
    [ordered]@{ checked_at_utc = (Get-Date).ToUniversalTime().ToString('o'); profile = $ClusterProfile; checks = @($checks.ToArray()); cart_state = $cartState } |
        ConvertTo-Json -Depth 14 | Set-Content (Join-Path $directory 'verification.json') -Encoding utf8
}
Write-Output "$($checks.Count) multi-node and HTTP checks passed. Only this script's forwarding processes were stopped."

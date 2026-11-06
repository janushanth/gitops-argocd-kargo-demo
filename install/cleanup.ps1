# Removes this demo from Docker Desktop: Kargo, Argo CD, cert-manager,
# the nginx namespaces, and their CRDs. Other workloads on the cluster stay.
# Also puts the nginx image tags back to 1.27.5 and pushes that reset,
# so the next demo starts from the same Git state.
$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$context = "docker-desktop"
$node = kubectl --context $context get nodes -o jsonpath="{.items[0].metadata.name}"
if ($node -ne "docker-desktop") {
    throw "Refusing to clean up. Context '$context' node is '$node', expected docker-desktop."
}

Write-Host "Cleaning demo resources on context $context (node $node)"

function Remove-HelmRelease {
    param([string]$Name, [string]$Namespace)
    helm status $Name --namespace $Namespace --kube-context $context 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Helm release $Name is not installed in $Namespace"
        return
    }
    helm uninstall $Name --namespace $Namespace --kube-context $context --wait
    if ($LASTEXITCODE -ne 0) {
        throw "helm uninstall $Name failed"
    }
}

# Stop Argo CD first so it cannot recreate Kargo, then remove the Helm releases.
Remove-HelmRelease -Name "argocd" -Namespace "argocd"
Remove-HelmRelease -Name "kargo" -Namespace "kargo"
Remove-HelmRelease -Name "cert-manager" -Namespace "cert-manager"

$namespaces = @(
    "hello-world-test",
    "hello-world-prod",
    "hello-world",
    "nginx-test",
    "nginx-prod",
    "nginx",
    "kargo",
    "argocd",
    "cert-manager"
)
foreach ($namespace in $namespaces) {
    kubectl --context $context get namespace $namespace 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        continue
    }
    Write-Host "Deleting namespace $namespace"
    kubectl --context $context delete namespace $namespace --wait --timeout=180s
    if ($LASTEXITCODE -ne 0) {
        throw "Timed out deleting namespace $namespace"
    }
}

$crdGroups = @(
    ".kargo.akuity.io",
    ".argoproj.io",
    ".cert-manager.io",
    ".acme.cert-manager.io"
)
$crdList = kubectl --context $context get crd -o json | ConvertFrom-Json
foreach ($crd in $crdList.items) {
    $name = $crd.metadata.name
    $matchesGroup = $false
    foreach ($group in $crdGroups) {
        if ($name.EndsWith($group)) { $matchesGroup = $true }
    }
    if ($matchesGroup) {
        Write-Host "Deleting CRD $name"
        kubectl --context $context delete crd $name --wait=false
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$imagePattern = "image:\s*nexus\.example\.com:8082/hello-world:\S+"
$imageValue = "image: nexus.example.com:8082/hello-world:0.0.0"
$tagFiles = @(
    "gitops/test/deployment.yaml",
    "gitops/prod/deployment.yaml"
)
Push-Location $repoRoot
try {
    $reset = $false
    foreach ($relative in $tagFiles) {
        $path = Join-Path $repoRoot $relative
        $text = [System.IO.File]::ReadAllText($path)
        $updated = [regex]::Replace($text, $imagePattern, $imageValue)
        if ($updated -ne $text) {
            $utf8 = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($path, $updated, $utf8)
            git add -- $relative
            $reset = $true
        }
    }
    if ($reset) {
        git commit -m "Reset Hello World image tags to 0.0.0 for the next demo."
        if ($LASTEXITCODE -ne 0) { throw "git commit of the tag reset failed" }
        git push origin HEAD
        if ($LASTEXITCODE -ne 0) { throw "git push of the tag reset failed" }
        Write-Host "Pushed Hello World tags back to 0.0.0."
    } else {
        Write-Host "Hello World tags are already 0.0.0."
    }
} finally {
    Pop-Location
}

Write-Host "Demo cleanup finished. Run .\install\install.ps1 before the next demo."

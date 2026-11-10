# Removes this demo from Docker Desktop and puts the Hello World image tag
# back to 0.0.0. Other workloads on the cluster, including the my-nginx Helm
# release, stay.
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
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    helm status $Name --namespace $Namespace --kube-context $context 1>$null 2>$null
    $status = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($status -ne 0) {
        Write-Host "Helm release $Name is not installed in $Namespace"
        return
    }
    helm uninstall $Name --namespace $Namespace --kube-context $context --wait
    if ($LASTEXITCODE -ne 0) {
        throw "helm uninstall $Name failed"
    }
}

# Stop Argo CD first so it cannot recreate Kargo, Jenkins, or Nexus.
Remove-HelmRelease -Name "argocd" -Namespace "argocd"
Remove-HelmRelease -Name "kargo" -Namespace "kargo"
Remove-HelmRelease -Name "cert-manager" -Namespace "cert-manager"

# The Kargo controller adds a finalizer that blocks namespace deletion after
# the controller is gone. Clear those finalizers before deleting namespaces.
$patch = Join-Path $env:TEMP "gitops-demo-clear-finalizers.json"
[System.IO.File]::WriteAllText($patch, '{"metadata":{"finalizers":null}}', (New-Object System.Text.UTF8Encoding $false))

kubectl --context $context -n kargo delete deployment --all --wait=false --ignore-not-found 1>$null 2>$null
$finalizers = @(
    @{ Kind = "stage"; Name = "test"; Namespace = "hello-world" },
    @{ Kind = "stage"; Name = "prod"; Namespace = "hello-world" },
    @{ Kind = "warehouse"; Name = "hello-world"; Namespace = "hello-world" },
    @{ Kind = "project"; Name = "hello-world"; Namespace = "" },
    @{ Kind = "serviceaccount"; Name = "kargo-controller"; Namespace = "kargo" }
)
foreach ($item in $finalizers) {
    if ($item.Namespace) {
        kubectl --context $context -n $item.Namespace patch $item.Kind $item.Name --type=merge --patch-file $patch 1>$null 2>$null
    } else {
        kubectl --context $context patch $item.Kind $item.Name --type=merge --patch-file $patch 1>$null 2>$null
    }
}

$namespaces = @(
    "jenkins",
    "nexus",
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
        kubectl --context $context patch namespace $namespace --type=merge --patch-file $patch 1>$null 2>$null
        kubectl --context $context delete namespace $namespace --wait --timeout=60s
        if ($LASTEXITCODE -ne 0) {
            throw "Timed out deleting namespace $namespace"
        }
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
$imagePattern = "image:\s*localhost:32082/hello-world:\S+"
$imageValue = "image: localhost:32082/hello-world:0.0.0"
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

# Installs cert-manager and Argo CD on Docker Desktop.
# Argo CD then installs Kargo from the chart in this repo, plus Nexus, Jenkins, and Goldilocks.
# Jenkins builds Hello World and pushes it to the Nexus registry on this node.
$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$context = "docker-desktop"
$node = kubectl --context $context get nodes -o jsonpath="{.items[0].metadata.name}"
if ($LASTEXITCODE -ne 0) { throw "Cannot reach the docker-desktop cluster." }
if ($node -ne "docker-desktop") {
    throw "Refusing to install. Context '$context' node is '$node', expected docker-desktop."
}

Write-Host "Installing on context $context (node $node, registry localhost:32082)"
$repoRoot = Split-Path -Parent $PSScriptRoot

# Pull every image the demo runs before anything waits on a pod. Docker Desktop
# Kubernetes reads the same local image store, so a pull here means a pod does
# not sit in ContainerCreating while the laptop downloads a large image.
# Keep this list in step with the chart versions and image tags in this repo.
$demoImages = @(
    "quay.io/jetstack/cert-manager-cainjector:v1.21.2",
    "quay.io/jetstack/cert-manager-controller:v1.21.2",
    "quay.io/jetstack/cert-manager-startupapicheck:v1.21.2",
    "quay.io/jetstack/cert-manager-webhook:v1.21.2",
    "quay.io/argoproj/argocd:v3.5.5",
    "ecr-public.aws.com/docker/library/redis:8.6.4-alpine",
    "ghcr.io/akuity/kargo:v1.12.5",
    "sonatype/nexus3:3.61.0",
    "python:3.12-alpine",
    "jenkins/jenkins:2.541.3-lts-jdk17",
    "docker:27-cli",
    "public.ecr.aws/docker/library/nginx:1.27.5",
    "us-docker.pkg.dev/fairwinds-ops/oss/goldilocks:v4.16.3",
    "registry.k8s.io/autoscaling/vpa-recommender:1.7.1",
    "registry.k8s.io/autoscaling/vpa-admission-controller:1.7.1",
    "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20230312-helm-chart-4.5.2-28-g66a760794",
    "registry.k8s.io/metrics-server/metrics-server:v0.9.0"
)

function Invoke-DockerPull {
    param([string]$Image)
    # docker writes progress to stderr. Let the exit code decide, not the error stream.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            docker pull $Image *> $null
            if ($LASTEXITCODE -eq 0) { return }
            Write-Host "docker pull $Image failed (attempt $attempt of 3). Retrying in 10 seconds."
            Start-Sleep -Seconds 10
        }
    } finally {
        $ErrorActionPreference = $previous
    }
    throw "Could not pull $Image. Check the network or the company proxy, then run .\install\install.ps1 again."
}

Write-Host "Pulling $($demoImages.Count) images (skipped when already present)..."
foreach ($image in $demoImages) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    docker image inspect $image *> $null
    $present = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $previous
    if ($present) {
        Write-Host "  present  $image"
        continue
    }
    Write-Host "  pulling  $image"
    Invoke-DockerPull -Image $image
}

Write-Host "Downloading Jenkins plugins on the laptop (the image build cannot trust the company certificate)..."
& (Join-Path $PSScriptRoot "jenkins\save-plugins.ps1") -Destination (Join-Path $repoRoot "jenkins\plugins")

Write-Host "Building the Jenkins image..."
docker build -t gitops-demo-jenkins:local (Join-Path $repoRoot "jenkins")
if ($LASTEXITCODE -ne 0) { throw "Jenkins image build failed." }

function Wait-Deployment {
    param(
        [string]$Namespace,
        [string]$Name,
        [string]$ApplicationName
    )
    Write-Host "Waiting for deployment $Namespace/$Name ..."
    $deadline = (Get-Date).AddMinutes(10)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $found = $false
    $refreshed = $false
    do {
        if ($ApplicationName) {
            $message = kubectl --context $context -n argocd get application $ApplicationName -o jsonpath="{.status.conditions[?(@.type=='ComparisonError')].message}" 2>$null
            if ($message) {
                if (-not $refreshed) {
                    kubectl --context $context -n argocd annotate application $ApplicationName argocd.argoproj.io/refresh=hard --overwrite 2>$null | Out-Null
                    $refreshed = $true
                    Start-Sleep -Seconds 15
                    continue
                }
                $ErrorActionPreference = $previous
                throw @"
Argo CD Application '$ApplicationName' cannot sync: $message
GitHub main does not have this path yet. Commit and push this repo, then run .\install\install.ps1 again.
"@
            }
        }
        $existing = kubectl --context $context -n $Namespace get deployment $Name --ignore-not-found -o name 2>$null
        if ($LASTEXITCODE -eq 0 -and $existing) {
            $found = $true
            break
        }
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)
    $ErrorActionPreference = $previous
    if (-not $found) {
        throw "Deployment $Namespace/$Name was never created. Check the $ApplicationName Application in Argo CD."
    }
    kubectl --context $context -n $Namespace wait --for=condition=available "deployment/$Name" --timeout=600s
    if ($LASTEXITCODE -ne 0) {
        throw "Deployment $Namespace/$Name did not become available."
    }
}

# The company proxy sometimes closes a chart download early. Helm then reports EOF.
# Retry with HTTP/2 disabled. Upgrade-or-install, so a second run does not fail on "name in use".
function Invoke-Helm {
    param(
        [string]$Purpose,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$HelmArgs
    )
    $saved = $env:GODEBUG
    if ([string]::IsNullOrEmpty($env:GODEBUG)) {
        $env:GODEBUG = "http2client=0"
    } elseif ($env:GODEBUG -notmatch "http2client=0") {
        $env:GODEBUG = "$($env:GODEBUG),http2client=0"
    }
    try {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            & helm @HelmArgs
            if ($LASTEXITCODE -eq 0) { return }
            Write-Host "$Purpose could not reach the chart repository (attempt $attempt of 3). Retrying in 5 seconds."
            Start-Sleep -Seconds 5
        }
        throw "$Purpose failed. The chart repository closed the connection. Run .\install\install.ps1 again."
    } finally {
        if ($null -eq $saved) {
            Remove-Item Env:GODEBUG -ErrorAction SilentlyContinue
        } else {
            $env:GODEBUG = $saved
        }
    }
}

Invoke-Helm -Purpose "cert-manager install" upgrade --install cert-manager cert-manager `
    --kube-context $context `
    --repo https://charts.jetstack.io `
    --version 1.21.2 `
    --namespace cert-manager `
    --create-namespace `
    --set crds.enabled=true `
    --wait

Invoke-Helm -Purpose "Argo CD install" upgrade --install argocd argo-cd `
    --kube-context $context `
    --repo https://argoproj.github.io/argo-helm `
    --version 10.10.5 `
    --namespace argocd `
    --create-namespace `
    --set 'configs.secret.argocdServerAdminPassword=$2a$10$5vm8wXaSdbuff0m9l21JdevzXBzJFPCi8sy6OOnpZMAG.fOXL7jvO' `
    --set dex.enabled=false `
    --set notifications.enabled=false `
    --set server.service.type=NodePort `
    --set server.service.nodePortHttp=31080 `
    --set 'server.extraArgs={--insecure}' `
    --wait

# Argo CD creates a namespace only after that Application syncs successfully.
# These waits run before that sync, and a missing namespace makes kubectl
# write an error that stops this script. Create the namespaces here.
# hello-world is NOT in this list: Kargo creates it from the Project, and Kargo
# rejects a Project whose namespace already exists without its label.
$demoNamespaces = @(
    "kargo",
    "nexus",
    "jenkins",
    "hello-world-test",
    "hello-world-prod",
    "goldilocks"
)
foreach ($namespace in $demoNamespaces) {
    kubectl --context $context create namespace $namespace --dry-run=client -o yaml | kubectl --context $context apply -f -
    if ($LASTEXITCODE -ne 0) { throw "Could not create namespace $namespace." }
}

kubectl --context $context apply -f (Join-Path $repoRoot "argocd\repository.yaml")
if ($LASTEXITCODE -ne 0) { throw "Could not apply the Git repository secret to Argo CD." }
kubectl --context $context apply -f (Join-Path $repoRoot "argocd\kargo-application.yaml")
if ($LASTEXITCODE -ne 0) { throw "Could not apply the Kargo Argo CD Application." }

Wait-Deployment -Namespace "kargo" -Name "kargo-api" -ApplicationName "kargo"

$apps = @(
    "argocd\nexus-application.yaml",
    "argocd\jenkins-application.yaml",
    "argocd\kargo-config-application.yaml",
    "argocd\hello-world-test-application.yaml",
    "argocd\hello-world-prod-application.yaml",
    "argocd\goldilocks-application.yaml"
)
foreach ($app in $apps) {
    kubectl --context $context apply -f (Join-Path $repoRoot $app)
    if ($LASTEXITCODE -ne 0) { throw "Could not apply $app." }
}

Wait-Deployment -Namespace "nexus" -Name "nexus" -ApplicationName "nexus"
kubectl --context $context -n nexus wait --for=condition=complete job/nexus-docker-repo --timeout=600s
if ($LASTEXITCODE -ne 0) { throw "Nexus did not get its Docker repository. Check job nexus-docker-repo." }

Wait-Deployment -Namespace "jenkins" -Name "jenkins" -ApplicationName "jenkins"
Wait-Deployment -Namespace "goldilocks" -Name "goldilocks-dashboard" -ApplicationName "goldilocks"

Write-Host ""
Write-Host "Argo CD:    http://localhost:31080  admin / admin"
Write-Host "Kargo:      http://localhost:31081  password admin"
Write-Host "Jenkins:    http://localhost:32080  admin / admin"
Write-Host "Nexus:      http://localhost:32081  admin / admin123"
Write-Host "Goldilocks: http://localhost:31085"
Write-Host ""
Write-Host "Create the Git credential Kargo uses to commit promotions. Do not paste the token into chat."
Write-Host "  .\install\kargo\create-git-secret.ps1 -Token <github-pat>"
Write-Host ""
Write-Host "In Jenkins, run the hello-world job. It pushes localhost:32082/hello-world:1.0.<time>."
Write-Host "Kargo promotes test on its own. Promote prod in the Kargo UI."

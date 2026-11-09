# Installs cert-manager and Argo CD on Docker Desktop.
# Argo CD then installs Kargo from the chart vendored in this repo,
# and syncs the Kargo config and the Hello World apps.
$ErrorActionPreference = "Stop"

$context = "docker-desktop"
$node = kubectl --context $context get nodes -o jsonpath="{.items[0].metadata.name}"
if ($LASTEXITCODE -ne 0) { throw "Cannot reach the docker-desktop cluster." }
if ($node -ne "docker-desktop") {
    throw "Refusing to install. Context '$context' node is '$node', expected docker-desktop."
}

Write-Host "Installing on context $context (node $node)"
$repoRoot = Split-Path -Parent $PSScriptRoot

# Upgrade-or-install, so re-running after a partial install does not fail on "name in use".
helm upgrade --install cert-manager cert-manager `
    --kube-context $context `
    --repo https://charts.jetstack.io `
    --version 1.21.2 `
    --namespace cert-manager `
    --create-namespace `
    --set crds.enabled=true `
    --wait
if ($LASTEXITCODE -ne 0) { throw "cert-manager install failed." }

helm upgrade --install argocd argo-cd `
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
if ($LASTEXITCODE -ne 0) { throw "Argo CD install failed." }

kubectl --context $context apply -f (Join-Path $repoRoot "argocd\repository.yaml")
if ($LASTEXITCODE -ne 0) { throw "Could not apply the Git repository secret to Argo CD." }
kubectl --context $context apply -f (Join-Path $repoRoot "argocd\kargo-application.yaml")
if ($LASTEXITCODE -ne 0) { throw "Could not apply the Kargo Argo CD Application." }

# Argo CD creates kargo-api after it renders the chart. Poll for it instead of
# failing on the first check, then wait for it to become available.
Write-Host "Waiting for Argo CD to create the Kargo API deployment..."
$deadline = (Get-Date).AddMinutes(10)
do {
    kubectl --context $context -n kargo get deployment kargo-api *> $null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 10
} while ((Get-Date) -lt $deadline)
if ($LASTEXITCODE -ne 0) {
    throw "kargo-api was never created. Check the kargo Application in Argo CD (Sync status and Conditions)."
}
kubectl --context $context -n kargo wait --for=condition=available deployment/kargo-api --timeout=600s
if ($LASTEXITCODE -ne 0) { throw "Kargo API did not become available. Check the kargo Application in Argo CD." }

kubectl --context $context apply -f (Join-Path $repoRoot "argocd\kargo-config-application.yaml")
if ($LASTEXITCODE -ne 0) { throw "Could not apply the Kargo config Application." }
kubectl --context $context apply -f (Join-Path $repoRoot "argocd\hello-world-test-application.yaml")
if ($LASTEXITCODE -ne 0) { throw "Could not apply the hello-world-test Application." }
kubectl --context $context apply -f (Join-Path $repoRoot "argocd\hello-world-prod-application.yaml")
if ($LASTEXITCODE -ne 0) { throw "Could not apply the hello-world-prod Application." }

Write-Host ""
Write-Host "Argo CD: http://localhost:31080  admin / admin"
Write-Host "Kargo:   http://localhost:31081  password admin"
Write-Host "Next, create the local secrets (values stay out of Git):"
Write-Host "  .\install\kargo\create-git-secret.ps1 -Token <github-pat>"
Write-Host "  .\install\nexus\create-registry-secrets.ps1 -Registry <host:port> -Username <user> -Password <password>"

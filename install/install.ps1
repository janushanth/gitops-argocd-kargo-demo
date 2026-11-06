# Installs cert-manager and Argo CD on Docker Desktop.
# Argo CD then installs Kargo and syncs the Hello World apps.
# Chart versions and the local admin password match the public Kargo quickstart:
# https://github.com/akuity/kargo/blob/main/hack/quickstart/install.sh
$ErrorActionPreference = "Stop"

$context = "docker-desktop"
$node = kubectl --context $context get nodes -o jsonpath="{.items[0].metadata.name}"
if ($node -ne "docker-desktop") {
    throw "Refusing to install. Context '$context' node is '$node', expected docker-desktop."
}

Write-Host "Installing on context $context (node $node)"

helm install cert-manager cert-manager `
    --kube-context $context `
    --repo https://charts.jetstack.io `
    --version 1.21.2 `
    --namespace cert-manager `
    --create-namespace `
    --set crds.enabled=true `
    --wait

helm install argocd argo-cd `
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

$repoRoot = Split-Path -Parent $PSScriptRoot
kubectl --context $context apply -f (Join-Path $repoRoot "argocd\repository.yaml")
kubectl --context $context apply -f (Join-Path $repoRoot "argocd\kargo-application.yaml")
if ($LASTEXITCODE -ne 0) { throw "Could not apply the Kargo Argo CD Application." }
kubectl --context $context -n kargo wait --for=condition=available deployment/kargo-api --timeout=600s
if ($LASTEXITCODE -ne 0) { throw "Kargo did not become ready. Check the kargo Application in Argo CD." }
kubectl --context $context apply -f (Join-Path $repoRoot "argocd\kargo-config-application.yaml")
kubectl --context $context apply -f (Join-Path $repoRoot "argocd\hello-world-test-application.yaml")
kubectl --context $context apply -f (Join-Path $repoRoot "argocd\hello-world-prod-application.yaml")
if ($LASTEXITCODE -ne 0) { throw "Could not apply the Hello World Argo CD Applications." }

Write-Host ""
Write-Host "Argo CD: http://localhost:31080  admin / admin"
Write-Host "Kargo:   http://localhost:31081  password admin"
Write-Host "Create the Git push secret and the Nexus pull secret before promotion:"
Write-Host "  .\install\kargo\create-git-secret.ps1 -Token <github-pat>"
Write-Host "  .\install\nexus\create-registry-secrets.ps1 -Registry <host:port> -Username <user> -Password <password>"

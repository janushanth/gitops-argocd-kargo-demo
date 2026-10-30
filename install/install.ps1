# Installs cert-manager, Argo CD, and Kargo on Docker Desktop only.
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

helm install kargo `
    oci://ghcr.io/akuity/kargo-charts/kargo `
    --kube-context $context `
    --namespace kargo `
    --create-namespace `
    --set api.service.type=NodePort `
    --set api.service.nodePort=31081 `
    --set api.tls.enabled=false `
    --set 'api.adminAccount.passwordHash=$2a$10$Zrhhie4vLz5ygtVSaif6o.qN36jgs6vjtMBdM6yrU1FOeiAAMMxOm' `
    --set api.adminAccount.tokenSigningKey=iwishtowashmyirishwristwatch `
    --set database.postgres.password=kargo `
    --set externalWebhooksServer.service.type=NodePort `
    --set externalWebhooksServer.service.nodePort=31082 `
    --set externalWebhooksServer.tls.enabled=false `
    --wait

$repoRoot = Split-Path -Parent $PSScriptRoot
kubectl --context $context apply -f (Join-Path $repoRoot "kargo\project.yaml")
kubectl --context $context -n nginx wait --for=jsonpath="{.status.phase}"=Active namespace/nginx --timeout=120s
kubectl --context $context apply -f (Join-Path $repoRoot "kargo")
kubectl --context $context apply -f (Join-Path $repoRoot "argocd")

Write-Host ""
Write-Host "Argo CD: http://localhost:31080  admin / admin"
Write-Host "Kargo:   http://localhost:31081  password admin"
Write-Host "Create the Git push secret before promotion:"
Write-Host "  .\install\kargo\create-git-secret.ps1 -Token <github-pat>"

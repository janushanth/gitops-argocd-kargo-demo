# Creates the Git credential Kargo uses to push promotion commits.
# The token is read from -Token and is not written to this repo.
param(
    [Parameter(Mandatory = $true)]
    [string]$Token
)

$ErrorActionPreference = "Stop"
$context = "docker-desktop"
$node = kubectl --context $context get nodes -o jsonpath="{.items[0].metadata.name}"
if ($node -ne "docker-desktop") {
    throw "Refusing to create the secret. Context '$context' node is '$node', expected docker-desktop."
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
kubectl --context $context apply -f (Join-Path $repoRoot "kargo\project.yaml")
if ($LASTEXITCODE -ne 0) { throw "Could not apply the Kargo Project." }
kubectl --context $context wait --for=jsonpath="{.status.phase}"=Active namespace/hello-world --timeout=120s
if ($LASTEXITCODE -ne 0) { throw "Namespace hello-world was not created." }

$yaml = @"
apiVersion: v1
kind: Secret
metadata:
  name: gitops-repo
  namespace: hello-world
  labels:
    kargo.akuity.io/cred-type: git
stringData:
  repoURL: https://github.com/janushanth/gitops-argocd-kargo-demo.git
  username: janushanth
  password: $($Token.Replace("'", "''"))
  insecureSkipTLSVerify: "true"
"@

$yaml | kubectl --context $context apply -f -
if ($LASTEXITCODE -ne 0) { throw "Git credential secret was not created." }
Write-Host "Git credential secret gitops-repo applied in namespace hello-world."

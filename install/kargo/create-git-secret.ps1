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

$yaml = @"
apiVersion: v1
kind: Secret
metadata:
  name: gitops-repo
  namespace: nginx
  labels:
    kargo.akuity.io/cred-type: git
stringData:
  repoURL: https://github.com/janushanth/gitops-argocd-kargo-demo.git
  username: janushanth
  password: $($Token.Replace("'", "''"))
"@

$yaml | kubectl --context $context apply -f -
Write-Host "Git credential secret gitops-repo applied in namespace nginx."

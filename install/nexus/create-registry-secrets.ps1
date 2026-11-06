# Creates Nexus credentials for image pull and for the Kargo Warehouse.
# Passwords are not written to the git repo.
param(
    [Parameter(Mandatory = $true)]
    [string]$Registry,
    [Parameter(Mandatory = $true)]
    [string]$Username,
    [Parameter(Mandatory = $true)]
    [string]$Password
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$context = "docker-desktop"
$node = kubectl --context $context get nodes -o jsonpath="{.items[0].metadata.name}"
if ($node -ne "docker-desktop") {
    throw "Refusing to create secrets. Context '$context' node is '$node', expected docker-desktop."
}

$namespaces = @("hello-world", "hello-world-test", "hello-world-prod")
foreach ($namespace in $namespaces) {
    kubectl --context $context get namespace $namespace 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Namespace $namespace does not exist yet. Wait until the Argo CD applications are Synced, then run this again."
    }
}

foreach ($namespace in @("hello-world-test", "hello-world-prod")) {
    kubectl --context $context create secret docker-registry nexus-pull `
        --namespace $namespace `
        --docker-server=$Registry `
        --docker-username=$Username `
        --docker-password=$Password `
        --dry-run=client -o yaml | kubectl --context $context apply -f -
    if ($LASTEXITCODE -ne 0) { throw "Could not create nexus-pull in $namespace." }
}

$imageRepo = "$Registry/hello-world"
$yaml = @"
apiVersion: v1
kind: Secret
metadata:
  name: nexus-image
  namespace: hello-world
  labels:
    kargo.akuity.io/cred-type: image
stringData:
  repoURL: $imageRepo
  username: $Username
  password: $Password
  insecureSkipTLSVerify: "true"
"@
$yaml | kubectl --context $context apply -f -
if ($LASTEXITCODE -ne 0) { throw "Could not create the Kargo Nexus image credential." }

Write-Host "Nexus pull secrets created in hello-world-test and hello-world-prod."
Write-Host "Kargo will list tags from $imageRepo."
Write-Host "That value must match repoURL in kargo/warehouse.yaml and imageRepo in the Stage files."

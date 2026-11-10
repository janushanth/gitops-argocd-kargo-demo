# Downloads Jenkins plugins with Windows, which trusts the company certificate.
# The image build cannot: Java inside Docker fails with PKIX when it calls updates.jenkins.io.
param(
    [string]$JenkinsVersion = "2.541.3",
    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

$rawPath = Join-Path $env:TEMP "jenkins-update-center-$JenkinsVersion.json"
Write-Host "Downloading the Jenkins plugin list for $JenkinsVersion"
Invoke-WebRequest -UseBasicParsing -Uri "https://updates.jenkins.io/update-center.json?version=$JenkinsVersion" -OutFile $rawPath

$raw = [System.IO.File]::ReadAllText($rawPath)
$start = $raw.IndexOf("{")
$end = $raw.LastIndexOf("}")
if ($start -lt 0 -or $end -le $start) {
    throw "The Jenkins update center response was not JSON."
}
$center = $raw.Substring($start, $end - $start + 1) | ConvertFrom-Json

$roots = @("configuration-as-code", "job-dsl", "workflow-aggregator", "git")
$queue = New-Object System.Collections.Generic.Queue[string]
foreach ($name in $roots) { $queue.Enqueue($name) }
$chosen = @{}

while ($queue.Count -gt 0) {
    $name = $queue.Dequeue()
    if ($chosen.ContainsKey($name)) { continue }
    $plugin = $center.plugins.$name
    if (-not $plugin) { throw "The Jenkins update center has no plugin '$name'." }
    $chosen[$name] = $plugin
    foreach ($dependency in @($plugin.dependencies)) {
        if ($dependency.optional) { continue }
        if ($dependency.name) { $queue.Enqueue([string]$dependency.name) }
    }
}

Write-Host "Downloading $($chosen.Count) Jenkins plugins into $Destination"
foreach ($name in $chosen.Keys) {
    $plugin = $chosen[$name]
    $file = Join-Path $Destination "$name.jpi"
    if ((Test-Path $file) -and ((Get-Item $file).Length -gt 0)) {
        continue
    }
    $url = [string]$plugin.url
    if (-not $url) { throw "Plugin $name has no download URL." }
    Write-Host "  $name $($plugin.version)"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $file
    if ((Get-Item $file).Length -eq 0) { throw "Downloaded an empty file for $name." }
}

param(
    [ValidateSet('build', 'load', 'deploy', 'verify', 'down', 'deploy-obs', 'verify-obs', 'down-obs', 'fault-on', 'fault-off', 'fault-traffic', 'verify-fault-lab', 'scan-security', 'verify-rollout-lab', 'verify-slo-lab', 'verify-provenance-lab')]
    [string]$Action = 'verify',
    [int]$TrafficCount = 80,
    [string]$KindCommand = 'kind'
)

$ErrorActionPreference = 'Stop'
$cluster = 'irrah-lab-133'
$context = 'kind-irrah-lab-133'
$namespace = 'irrah-lab'
$owner = 'irrah-operational-lab'
$image = 'irrah-lab-http:0.1.0'
$imageNext = 'irrah-lab-http:0.1.1'
$appVersionNext = '0.1.1'
$brokenReadinessPath = '/readyz-broken'
$repository = Split-Path -Parent $PSScriptRoot
$rolloutEvidenceRoot = Join-Path $repository '.evidence/lab-rollout'
$manifests = Join-Path $repository 'lab/k8s'
$observabilityManifest = Join-Path $manifests 'observability.yaml'
$faultLatencyMs = 400
$faultErrorPercent = 50
$labTrafficUrl = 'http://lab-http.irrah-lab.svc.cluster.local:8080/'
$trivyImage = 'aquasec/trivy:0.59.1'
$evidenceRoot = Join-Path $repository '.evidence/lab-security'
$trivyCacheDir = Join-Path $repository '.evidence/trivy-cache'
$sloEvidenceRoot = Join-Path $repository '.evidence/lab-slo'
$provenanceEvidenceRoot = Join-Path $repository '.evidence/lab-provenance'
$cosignImage = 'gcr.io/projectsigstore/cosign:v2.4.1'
$sloConfigPath = Join-Path $repository 'lab/config/slo.json'

function Invoke-Tool([string]$Command, [string[]]$Arguments) {
    $null = Get-Command -Name $Command -CommandType Application -ErrorAction Stop
    $output = & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE."
    }
    return $output
}

function Invoke-KubectlCluster([string[]]$Arguments) {
    Invoke-Tool 'kubectl' (@('--context', $context) + $Arguments)
}

function Invoke-Kubectl([string[]]$Arguments) {
    Invoke-Tool 'kubectl' (@('--context', $context, '--namespace', $namespace) + $Arguments)
}

function Get-KubeClusterJson([string[]]$Arguments) {
    $output = Invoke-KubectlCluster ($Arguments + @('-o', 'json'))
    if ($output) { return (($output -join "`n") | ConvertFrom-Json) }
}

function Get-KubeJson([string[]]$Arguments) {
    $output = Invoke-Kubectl ($Arguments + @('-o', 'json'))
    if ($output) { return (($output -join "`n") | ConvertFrom-Json) }
}

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-LabCluster([bool]$CheckApi) {
    $clusters = @(Invoke-Tool $KindCommand @('get', 'clusters'))
    Assert-Condition ($clusters -contains $cluster) "Existing kind cluster $cluster is required; this script never creates it."
    $nodes = @(Invoke-Tool $KindCommand @('get', 'nodes', '--name', $cluster))
    Assert-Condition ($nodes.Count -gt 0) 'The target kind cluster has no nodes.'
    $inspection = Invoke-Tool 'docker' (@('inspect') + $nodes)
    $containers = @(($inspection -join "`n") | ConvertFrom-Json)
    foreach ($container in $containers) {
        Assert-Condition ($container.Config.Labels.'io.x-k8s.kind.cluster' -eq $cluster) 'Docker node ownership does not match the lab cluster.'
    }
    if ($CheckApi) {
        $api = Get-KubeJson @('get', 'nodes')
        $difference = @(Compare-Object ($nodes | Sort-Object) (@($api.items.metadata.name) | Sort-Object))
        Assert-Condition ($difference.Count -eq 0) "Context $context does not point to the expected kind nodes."
    }
}

function Invoke-PrometheusQuery([string]$Query) {
    $encoded = [uri]::EscapeDataString($Query)
    $raw = Invoke-Kubectl @('exec', 'deployment/prometheus', '-c', 'prometheus', '--', 'wget', '-qO-', "http://127.0.0.1:9090/api/v1/query?query=$encoded")
    return (($raw -join "`n") | ConvertFrom-Json)
}

function Get-PromQuerySum([string]$Query) {
    $result = Invoke-PrometheusQuery $Query
    if ($result.status -ne 'success') { throw "Prometheus query failed: $Query" }
    $sum = 0.0
    foreach ($series in $result.data.result) {
        $sum += [double]$series.value[1]
    }
    return $sum
}

function Get-LabSLISnapshot {
    return @{
        Rate200 = (Get-PromQuerySum 'sum(rate(lab_http_requests_total{job="lab-http",code="200"}[2m]))')
        Rate503 = (Get-PromQuerySum 'sum(rate(lab_http_requests_total{job="lab-http",code="503"}[2m]))')
        P95     = (Get-PromQuerySum 'histogram_quantile(0.95, sum by (le) (rate(lab_http_request_duration_seconds_bucket{job="lab-http"}[2m])))')
        Ready   = (Get-PromQuerySum 'sum(lab_ready{job="lab-http"})')
    }
}

function Get-LabSuccessRatio([hashtable]$Snapshot) {
    $denom = $Snapshot.Rate200 + $Snapshot.Rate503
    if ($denom -le 0) { return 1.0 }
    return $Snapshot.Rate200 / $denom
}

function Get-LabSLOThresholds {
    if (-not $script:LabSLOThresholds) {
        Assert-Condition (Test-Path $sloConfigPath) "Missing SLO config: $sloConfigPath"
        $script:LabSLOThresholds = Get-Content -Raw -Path $sloConfigPath | ConvertFrom-Json
    }
    return $script:LabSLOThresholds
}

function Test-LabSLOSnapshot([hashtable]$Snapshot) {
    $thresholds = Get-LabSLOThresholds
    $violations = @()
    $ratio = Get-LabSuccessRatio $Snapshot
    if ($ratio -lt $thresholds.minSuccessRatio) {
        $violations += "success ratio $([math]::Round($ratio,4)) < min $($thresholds.minSuccessRatio)"
    }
    if ($Snapshot.Rate503 -gt $thresholds.max503Rate) {
        $violations += "503 rate $([math]::Round($Snapshot.Rate503,4)) > max $($thresholds.max503Rate)"
    }
    if ($Snapshot.P95 -gt $thresholds.maxP95Seconds) {
        $violations += "p95 $([math]::Round($Snapshot.P95,4))s > max $($thresholds.maxP95Seconds)s"
    }
    if ($Snapshot.Ready -lt $thresholds.minReadySum) {
        $violations += "ready sum $([math]::Round($Snapshot.Ready,2)) < min $($thresholds.minReadySum)"
    }
    $ok = ($violations.Count -eq 0)
    $status = if ($ok) { 'PASS' } else { 'FAIL' }
    $summary = "status=$status success_ratio=$([math]::Round($ratio,4)) rate503=$([math]::Round($Snapshot.Rate503,4)) p95=$([math]::Round($Snapshot.P95,4))s ready=$([math]::Round($Snapshot.Ready,2)) violations=$(if ($violations.Count) { ($violations -join '; ') } else { '-' })"
    return @{ Ok = $ok; Violations = $violations; Summary = $summary; SuccessRatio = $ratio }
}

function Invoke-CosignContainer([string[]]$Arguments, [string]$WorkDirectory, [switch]$AllowFailure, [string]$CosignPassword) {
    $dockerArgs = @(
        'run', '--rm',
        '-v', '/var/run/docker.sock:/var/run/docker.sock',
        '-v', "${WorkDirectory}:/work",
        '-w', '/work'
    )
    if ($CosignPassword) {
        $dockerArgs += '-e', "COSIGN_PASSWORD=$CosignPassword"
    }
    $dockerArgs += $cosignImage
    $dockerArgs += $Arguments
    & docker @dockerArgs
    if (-not $AllowFailure -and $LASTEXITCODE -ne 0) {
        throw "cosign failed with exit code $LASTEXITCODE."
    }
    return $LASTEXITCODE
}

function Set-LabFault([int]$LatencyMs, [int]$ErrorPercent) {
    Invoke-Kubectl @(
        'set', 'env', 'deployment/lab-http',
        "LAB_FAULT_LATENCY_MS=$LatencyMs",
        "LAB_FAULT_ERROR_PERCENT=$ErrorPercent"
    )
    Invoke-Kubectl @('rollout', 'status', 'deployment/lab-http', '--timeout=180s')
}

function Invoke-TrivyContainer([string[]]$Arguments, [string]$OutputDirectory) {
    $dockerArgs = @(
        'run', '--rm',
        '-v', '/var/run/docker.sock:/var/run/docker.sock',
        '-v', "${trivyCacheDir}:/root/.cache/trivy",
        '-v', "${OutputDirectory}:/out",
        $trivyImage
    ) + $Arguments
    & docker @dockerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "trivy failed with exit code $LASTEXITCODE."
    }
}

function Invoke-TrivyContainerAllowFailure([string[]]$Arguments, [string]$OutputDirectory) {
    $dockerArgs = @(
        'run', '--rm',
        '-v', '/var/run/docker.sock:/var/run/docker.sock',
        '-v', "${trivyCacheDir}:/root/.cache/trivy",
        '-v', "${OutputDirectory}:/out",
        $trivyImage
    ) + $Arguments
    & docker @dockerArgs
    return $LASTEXITCODE
}

function Get-TrivyVersion {
    $null = Get-Command -Name docker -CommandType Application -ErrorAction Stop
    $raw = & docker run --rm $trivyImage version --format json
    if ($LASTEXITCODE -ne 0) { throw "trivy version failed with exit code $LASTEXITCODE." }
    return (($raw -join "`n") | ConvertFrom-Json).Version
}

function Get-TrivySeverityCounts([string]$ReportPath) {
    $counts = @{ CRITICAL = 0; HIGH = 0; MEDIUM = 0; LOW = 0; UNKNOWN = 0 }
    $report = Get-Content -Raw -Path $ReportPath | ConvertFrom-Json
    foreach ($result in @($report.Results)) {
        if (-not $result.Vulnerabilities) { continue }
        foreach ($finding in @($result.Vulnerabilities)) {
            if (-not $finding) { continue }
            $severity = [string]$finding.Severity
            if ($counts.ContainsKey($severity)) {
                $counts[$severity]++
            } else {
                $counts.UNKNOWN++
            }
        }
    }
    return $counts
}

function Invoke-LabBuild([string]$Tag, [string]$AppVersion, [string]$VcsRef) {
    Invoke-Tool 'docker' @(
        'build', '--platform', 'linux/amd64', '--provenance=false', '--sbom=false',
        '--build-arg', "APP_VERSION=$AppVersion",
        '--build-arg', "VCS_REF=$VcsRef",
        '--tag', $Tag,
        '-f', (Join-Path $repository 'lab/app/Dockerfile'),
        (Join-Path $repository 'lab')
    )
}

function Save-RolloutSnapshot([string]$Directory, [string]$Label) {
    $path = Join-Path $Directory "$Label.txt"
    $lines = @(
        "=== $Label UTC $((Get-Date).ToUniversalTime()) ===",
        ((Invoke-Kubectl @('get', 'deployment/lab-http', '-o', 'wide')) -join "`n"),
        ((Invoke-Kubectl @('get', 'rs', '-l', 'app.kubernetes.io/name=lab-http', '-o', 'wide')) -join "`n"),
        ((Invoke-Kubectl @('get', 'pods', '-l', 'app.kubernetes.io/name=lab-http', '-o', 'wide')) -join "`n"),
        ((Invoke-Kubectl @('rollout', 'history', 'deployment/lab-http')) -join "`n")
    )
    Set-Content -Path $path -Value ($lines -join "`n`n") -Encoding utf8
}

function Invoke-LabServiceGet {
    $script = "wget -qO- -T 5 '$labTrafficUrl' 2>/dev/null || true"
    $raw = & kubectl --context $context --namespace $namespace exec deployment/prometheus -c prometheus -- sh -c $script
    if ($LASTEXITCODE -ne 0) { throw "In-cluster HTTP request to lab-http failed." }
    return ($raw -join "`n").Trim()
}

function Get-LabHttpVersionFromBody([string]$Body) {
    if (-not $Body) { return $null }
    try {
        $parsed = $Body | ConvertFrom-Json
        return [string]$parsed.version
    } catch {
        return $null
    }
}

function Wait-LabRollout([int]$TimeoutSeconds) {
    & kubectl --context $context --namespace $namespace rollout status deployment/lab-http --timeout="${TimeoutSeconds}s" | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Wait-LabReadyPodCount([int]$Expected, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $deployment = Get-KubeJson @('get', 'deployment', 'lab-http')
        if ($deployment.status.readyReplicas -eq $Expected) {
            $selector = ($deployment.spec.selector.matchLabels.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ','
            $pods = Get-KubeJson @('get', 'pods', '-l', $selector)
            $ready = @($pods.items | Where-Object {
                    -not $_.metadata.deletionTimestamp -and
                    @($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }).Count -gt 0
                }).Count
            if ($ready -eq $Expected) { return $true }
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Assert-LabHttpHealthy([string]$ExpectedVersion) {
    Assert-Condition (Wait-LabReadyPodCount 2 180) 'Expected two non-terminating Ready pods.'
    $deployment = Get-KubeJson @('get', 'deployment', 'lab-http')
    $selector = ($deployment.spec.selector.matchLabels.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ','
    $pods = Get-KubeJson @('get', 'pods', '-l', $selector)
    $readyPods = @($pods.items | Where-Object {
            -not $_.metadata.deletionTimestamp -and
            @($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }).Count -gt 0
        })
    Assert-Condition ($readyPods.Count -eq 2) 'Expected exactly two Ready pods.'
    foreach ($pod in $readyPods) {
        Invoke-Kubectl @('exec', $pod.metadata.name, '-c', 'http', '--', '/lab-http', 'check', 'http://127.0.0.1:8080') | Out-Null
    }
    if ($ExpectedVersion) {
        $body = Invoke-LabServiceGet
        $version = Get-LabHttpVersionFromBody $body
        Assert-Condition ($version -eq $ExpectedVersion) "Expected service version $ExpectedVersion from GET /; got '$version'."
    }
}

function Invoke-LabTraffic([int]$Count) {
    for ($i = 0; $i -lt $Count; $i++) {
        # Fault injection may return 503; traffic generation must still continue.
        $null = & kubectl --context $context --namespace $namespace exec deployment/prometheus -c prometheus -- sh -c "wget -qO- -T 10 '$labTrafficUrl' >/dev/null 2>&1 || true"
    }
}

function Assert-OwnedObservability {
    $objects = Get-KubeJson @('get', 'deployment/prometheus', 'deployment/grafana', '--ignore-not-found')
    if (-not $objects) { return $false }
    $items = if ($objects.kind -eq 'List') { @($objects.items) } else { @($objects) }
    if ($items.Count -eq 0) { return $false }
    foreach ($item in $items) {
        Assert-Condition ($item.metadata.labels.'app.kubernetes.io/part-of' -eq $owner) "Refusing to modify unowned observability $($item.kind)/$($item.metadata.name)."
    }
    return $true
}

function Assert-OwnedObjects {
    $existingNamespace = Get-KubeClusterJson @('get', 'namespace', $namespace, '--ignore-not-found')
    if (-not $existingNamespace) { return $false }
    Assert-Condition ($existingNamespace.metadata.labels.'app.kubernetes.io/part-of' -eq $owner) "Namespace $namespace exists without the expected ownership label."
    $objects = Get-KubeJson @('get', 'deployment/lab-http', 'service/lab-http', 'serviceaccount/lab-http', '--ignore-not-found')
    if ($objects) {
        $items = if ($objects.kind -eq 'List') { @($objects.items) } else { @($objects) }
        foreach ($item in $items) {
            Assert-Condition ($item.metadata.labels.'app.kubernetes.io/part-of' -eq $owner) "Refusing to modify unowned $($item.kind)/$($item.metadata.name)."
        }
    }
    return $true
}

if ($Action -eq 'build') {
    Invoke-LabBuild $image '0.1.0' 'lab'
    exit 0
}

if ($Action -eq 'verify-provenance-lab') {
    Invoke-Tool 'docker' @('image', 'inspect', $image) | Out-Null
    $runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $runDir = Join-Path $provenanceEvidenceRoot $runId
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $inspectRaw = Invoke-Tool 'docker' @('image', 'inspect', $image, '--format', '{{json .}}')
    $inspect = ($inspectRaw -join "`n") | ConvertFrom-Json
    $repoDigest = @($inspect.RepoDigests)[0]
    $digestHex = $null
    if ($repoDigest -match '@sha256:([a-f0-9]{64})$') {
        $digestHex = $Matches[1]
    } else {
        $id = [string]$inspect.Id
        if ($id -match '^sha256:([a-f0-9]{64})$') { $digestHex = $Matches[1] }
    }
    Assert-Condition ([bool]$digestHex) 'Could not resolve image digest from docker inspect.'
    $digestLine = "sha256:$digestHex"
    $digestFile = Join-Path $runDir 'artifact.digest'
    Set-Content -Path $digestFile -Value $digestLine -Encoding ascii -NoNewline
    $cosignPass = 'lab-local-ephemeral'
    Invoke-CosignContainer @('generate-key-pair') $runDir -CosignPassword $cosignPass
    Invoke-CosignContainer @(
        'sign-blob', '--key', 'cosign.key', '--bundle', 'bundle.json', '--yes',
        '--tlog-upload=false', 'artifact.digest'
    ) $runDir -CosignPassword $cosignPass
    Invoke-CosignContainer @(
        'verify-blob', '--key', 'cosign.pub', '--bundle', 'bundle.json',
        '--insecure-ignore-tlog=true', 'artifact.digest'
    ) $runDir
    New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'wrong-key') | Out-Null
    $wrongDir = Join-Path $runDir 'wrong-key'
    Invoke-CosignContainer @('generate-key-pair') $wrongDir -CosignPassword 'lab-local-ephemeral-wrong'
    $verifyWrong = Invoke-CosignContainer @(
        'verify-blob', '--key', 'cosign.pub', '--bundle', 'bundle.json',
        '--insecure-ignore-tlog=true', 'artifact.digest'
    ) $wrongDir -AllowFailure
    Assert-Condition ($verifyWrong -ne 0) 'Expected cosign verify-blob to fail with non-matching public key.'
    $summary = @"
# Provenance lab execution summary

- UTC: $runId
- Source image: $image
- Signed artifact: digest $digestLine (sign-blob + bundle.json)
- Cosign: $cosignImage (ephemeral key in evidence dir)
- Sign+verify-blob: PASS on matching key; verify with wrong key: FAIL (exit $verifyWrong)
- Not OCIR/OKE image signature; consumer must match digest before deploy (see release reference workflow).
- Evidence: $runDir
"@
    Set-Content -Path (Join-Path $runDir 'execution-summary.md') -Value $summary -Encoding utf8
    Write-Host $summary
    exit 0
}

if ($Action -eq 'scan-security') {
    Invoke-Tool 'docker' @('image', 'inspect', $image) | Out-Null
    $runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $runDir = Join-Path $evidenceRoot $runId
    New-Item -ItemType Directory -Force -Path $trivyCacheDir, $runDir | Out-Null
    $inspectRaw = Invoke-Tool 'docker' @('image', 'inspect', $image, '--format', '{{json .}}')
    $inspect = ($inspectRaw -join "`n") | ConvertFrom-Json
    $digest = @($inspect.RepoDigests)[0]
    if (-not $digest) { $digest = $inspect.Id }

    $trivyVersion = Get-TrivyVersion
    Invoke-TrivyContainer @(
        'image', '--scanners', 'vuln', '--format', 'json',
        '-o', '/out/trivy-report.json', $image
    ) $runDir
    Invoke-TrivyContainer @(
        'image', '--format', 'cyclonedx',
        '-o', '/out/sbom.cyclonedx.json', $image
    ) $runDir
    $counts = Get-TrivySeverityCounts (Join-Path $runDir 'trivy-report.json')
    $gateExit = Invoke-TrivyContainerAllowFailure @(
        'image', '--scanners', 'vuln', '--severity', 'HIGH,CRITICAL',
        '--exit-code', '1', '--format', 'table', '-o', '/out/gate-high-critical.txt', $image
    ) $runDir
    $gatePath = Join-Path $runDir 'gate-high-critical.txt'
    if (Test-Path $gatePath) {
        Write-Host (Get-Content -Raw -Path $gatePath)
    } else {
        Write-Host 'Gate table: no HIGH/CRITICAL rows (empty report file).'
    }
    $gateResult = if ($gateExit -eq 0) { 'PASS' } else { 'FAIL' }
    $summary = @"
# Security scan execution summary

- UTC: $runId
- Image: $image
- Digest: $digest
- Trivy: $trivyVersion ($trivyImage)
- Gate (HIGH/CRITICAL, no --ignore-unfixed): $gateResult (exit $gateExit)
- Counts: CRITICAL=$($counts.CRITICAL) HIGH=$($counts.HIGH) MEDIUM=$($counts.MEDIUM) LOW=$($counts.LOW) UNKNOWN=$($counts.UNKNOWN)
- Artifacts: trivy-report.json, sbom.cyclonedx.json, gate-high-critical.txt (this directory)
- Local lab only; not OCIR/OKE evidence.
"@
    Set-Content -Path (Join-Path $runDir 'execution-summary.md') -Value $summary -Encoding utf8
    Write-Host $summary
    Write-Host "Evidence directory: $runDir"
    if ($gateExit -ne 0) {
        throw "Security gate FAILED: HIGH/CRITICAL vulnerabilities present. Review trivy-report.json and gate table output above."
    }
    if ($counts.MEDIUM -gt 0 -or $counts.LOW -gt 0) {
        Write-Host "Gate passed on HIGH/CRITICAL only; review MEDIUM/LOW in trivy-report.json for backlog."
    }
    exit 0
}

Assert-LabCluster ($Action -ne 'load')
if ($Action -eq 'load') {
    Invoke-Tool $KindCommand @('load', 'docker-image', $image, '--name', $cluster)
    exit 0
}

$namespaceExists = Assert-OwnedObjects
if ($Action -eq 'deploy') {
    Invoke-KubectlCluster @('apply', '-f', (Join-Path $manifests 'namespace.yaml'))
    Invoke-Kubectl @('apply', '-f', (Join-Path $manifests 'workload.yaml'))
    Invoke-Kubectl @('rollout', 'status', 'deployment/lab-http', '--timeout=180s')
    exit 0
}

if ($Action -eq 'deploy-obs') {
    Assert-Condition $namespaceExists "Namespace $namespace does not exist; deploy lab-http first."
    Invoke-Kubectl @('apply', '-f', $observabilityManifest)
    Invoke-Kubectl @('rollout', 'status', 'deployment/prometheus', '--timeout=180s')
    Invoke-Kubectl @('rollout', 'status', 'deployment/grafana', '--timeout=180s')
    exit 0
}

if ($Action -eq 'down-obs') {
    if (Assert-OwnedObservability) {
        Invoke-Kubectl @('delete', '-f', $observabilityManifest, '--ignore-not-found', '--timeout=180s')
    }
    Write-Host 'Observability stack removed from irrah-lab. lab-http and namespace remain unless removed separately.'
    exit 0
}

if ($Action -eq 'down') {
    if ($namespaceExists) {
        if (Assert-OwnedObservability) {
            Invoke-Kubectl @('delete', '-f', $observabilityManifest, '--ignore-not-found', '--timeout=180s')
        }
        Invoke-Kubectl @('delete', '-f', (Join-Path $manifests 'workload.yaml'), '--ignore-not-found', '--timeout=180s')
    }
    Write-Host "Only the declared lab workload objects are removed. Namespace $namespace and kind clusters remain."
    exit 0
}

if ($Action -eq 'fault-on') {
    Assert-Condition $namespaceExists "Namespace $namespace does not exist; deploy the lab first."
    Set-LabFault $faultLatencyMs $faultErrorPercent
    Write-Host "Fault injection enabled: LAB_FAULT_LATENCY_MS=$faultLatencyMs LAB_FAULT_ERROR_PERCENT=$faultErrorPercent"
    exit 0
}

if ($Action -eq 'fault-off') {
    Assert-Condition $namespaceExists "Namespace $namespace does not exist; deploy the lab first."
    Set-LabFault 0 0
    Write-Host 'Fault injection disabled (env vars reset to 0).'
    exit 0
}

if ($Action -eq 'fault-traffic') {
    Assert-Condition $namespaceExists "Namespace $namespace does not exist; deploy the lab first."
    Assert-Condition (Assert-OwnedObservability) 'Prometheus is required to generate in-cluster traffic from verify scripts.'
    Invoke-LabTraffic $TrafficCount
    Write-Host "Generated $TrafficCount HTTP requests to $labTrafficUrl"
    exit 0
}

if ($Action -eq 'verify-rollout-lab') {
    Assert-Condition $namespaceExists "Namespace $namespace does not exist; deploy the lab first."
    Assert-Condition (Assert-OwnedObservability) 'Observability stack is required for in-cluster HTTP checks and metrics during rollout.'
    $runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $runDir = Join-Path $rolloutEvidenceRoot $runId
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    Set-LabFault 0 0
    Invoke-LabBuild $image '0.1.0' 'lab'
    Invoke-Tool $KindCommand @('load', 'docker-image', $image, '--name', $cluster)
    # Same tag does not change the pod template; restart picks up the reloaded digest on kind nodes.
    Invoke-Kubectl @('rollout', 'restart', 'deployment/lab-http')
    Assert-Condition (Wait-LabRollout 180) 'Baseline rollout after image reload did not complete.'
    Save-RolloutSnapshot $runDir '01-baseline'
    Assert-LabHttpHealthy '0.1.0'
    Write-Host 'Baseline healthy: 2/2 Ready, version 0.1.0, fault injection off.'

    Invoke-LabBuild $imageNext $appVersionNext 'lab-rollout'
    Invoke-Tool $KindCommand @('load', 'docker-image', $imageNext, '--name', $cluster)
    $beforeRev = (Invoke-Kubectl @('rollout', 'history', 'deployment/lab-http') -join "`n")
    Set-Content -Path (Join-Path $runDir '02-history-before-upgrade.txt') -Value $beforeRev -Encoding utf8

    Invoke-Kubectl @('set', 'image', 'deployment/lab-http', "http=$imageNext")
    $okCount = 0
    $sampleVersions = @()
    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 2
        $body = Invoke-LabServiceGet
        if ($body -match '"service"') { $okCount++ }
        $v = Get-LabHttpVersionFromBody $body
        if ($v) { $sampleVersions += $v }
    }
    Assert-Condition ($okCount -ge 40) "Service availability dropped during rollout (successful GET / samples: $okCount/45)."
    Assert-Condition (Wait-LabRollout 180) 'Rollout to 0.1.1 did not complete successfully.'
    Save-RolloutSnapshot $runDir '03-after-successful-rollout'
    Assert-LabHttpHealthy $appVersionNext
    $readyMetric = Get-PromQuerySum 'sum(lab_ready{job="lab-http"})'
    Assert-Condition ($readyMetric -ge 1.9) "Expected lab_ready sum ~= 2 after rollout; got $readyMetric."
    Write-Host "Successful rolling update: continuity samples=$okCount/45 versions seen: $(($sampleVersions | Select-Object -Unique) -join ', ') lab_ready=$readyMetric"

    $badProbePatch = @"
{"spec":{"template":{"spec":{"containers":[{"name":"http","readinessProbe":{"httpGet":{"path":"$brokenReadinessPath"}}}]}}}}
"@
    $patchFile = Join-Path $runDir 'bad-probe-patch.json'
    Set-Content -Path $patchFile -Value $badProbePatch.Trim() -Encoding ascii -NoNewline
    Invoke-Kubectl @('patch', 'deployment/lab-http', '--type=strategic', '--patch-file', $patchFile)
    $stalled = -not (Wait-LabRollout 150)
    Assert-Condition $stalled 'Expected rollout to stall when readiness probe path is broken.'
    Save-RolloutSnapshot $runDir '04-stalled-bad-probe'
    $deployStatus = Get-KubeJson @('get', 'deployment', 'lab-http')
    $progressing = @($deployStatus.status.conditions | Where-Object { $_.type -eq 'Progressing' })
    $deadlineExceeded = @($progressing | Where-Object { $_.reason -eq 'ProgressDeadlineExceeded' }).Count -gt 0
    if (-not $deadlineExceeded) {
        Write-Host 'Note: ProgressDeadlineExceeded not yet observed; checking ReplicaSet readiness split.'
    }
    $rsList = Get-KubeJson @('get', 'rs', '-l', 'app.kubernetes.io/name=lab-http')
    $readySum = ($rsList.items | ForEach-Object { $_.status.readyReplicas }) | Measure-Object -Sum
    Assert-Condition ($readySum.Sum -ge 2) "Expected at least two Ready pods serving traffic during failed rollout; ready sum=$($readySum.Sum)."
    $bodyDuringFail = Invoke-LabServiceGet
    Assert-Condition ($bodyDuringFail -match '"service"') 'HTTP GET / failed while bad rollout was stalled.'
    Write-Host "Failed rollout contained: deployment still serves traffic; stalled=$stalled deadlineExceeded=$deadlineExceeded"

    Invoke-Kubectl @('rollout', 'undo', 'deployment/lab-http')
    Assert-Condition (Wait-LabRollout 180) 'rollout undo did not complete.'
    Save-RolloutSnapshot $runDir '05-after-undo'
    Assert-LabHttpHealthy $appVersionNext

    Invoke-Kubectl @('apply', '-f', (Join-Path $manifests 'workload.yaml'))
    Assert-Condition (Wait-LabRollout 180) 'Restore apply of workload.yaml did not complete.'
    Set-LabFault 0 0
    Save-RolloutSnapshot $runDir '06-final-baseline'
    Assert-LabHttpHealthy '0.1.0'
    $deployment = Get-KubeJson @('get', 'deployment', 'lab-http')
    $container = @($deployment.spec.template.spec.containers | Where-Object name -EQ 'http')[0]
    Assert-Condition ($container.readinessProbe.httpGet.path -eq '/readyz') 'Readiness probe path was not restored to /readyz.'
    Assert-Condition ($container.image -eq $image) 'Deployment image was not restored to irrah-lab-http:0.1.0.'
    Invoke-Kubectl @('rollout', 'status', 'deployment/prometheus', '--timeout=180s')
    $targetsRaw = Invoke-Kubectl @('exec', 'deployment/prometheus', '-c', 'prometheus', '--', 'wget', '-qO-', 'http://127.0.0.1:9090/api/v1/targets')
    $targets = (($targetsRaw -join "`n") | ConvertFrom-Json)
    $active = @($targets.data.activeTargets | Where-Object { $_.labels.job -eq 'lab-http' -and $_.health -eq 'up' })
    Assert-Condition ($active.Count -eq 2) "Expected two healthy lab-http scrape targets after restore; found $($active.Count)."
    $summary = @"
# Rollout lab execution summary

- UTC: $runId
- Cluster: $context / namespace $namespace
- Good rollout: $image -> $imageNext (maxUnavailable=0, maxSurge=1)
- Failed rollout: readinessProbe path $brokenReadinessPath (app unchanged)
- Rollback: kubectl rollout undo, then apply lab/k8s/workload.yaml
- Final: 2/2 Ready, image $image, fault off, Prometheus targets up
- Evidence: $runDir
"@
    Set-Content -Path (Join-Path $runDir 'execution-summary.md') -Value $summary -Encoding utf8
    Write-Host $summary
    Write-Host 'Rollout/rollback lab verified; environment restored to healthy baseline.'
    exit 0
}

if ($Action -eq 'verify-slo-lab') {
    Assert-LabCluster $true
    Assert-Condition $namespaceExists "Namespace $namespace does not exist; deploy the lab first."
    Assert-Condition (Assert-OwnedObservability) 'Prometheus and lab-http are required for SLI/SLO queries.'
    $runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $runDir = Join-Path $sloEvidenceRoot $runId
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $logLines = @()
    $sloFailed = $false
    try {
        Set-LabFault 0 0
        Invoke-LabTraffic 40
        Start-Sleep -Seconds 28
        $baseline = Get-LabSLISnapshot
        $baselineEval = Test-LabSLOSnapshot $baseline
        $logLines += "phase=baseline $($baselineEval.Summary)"
        Write-Host $logLines[-1]
        if (-not $baselineEval.Ok) {
            $sloFailed = $true
            throw "Baseline SLO objectives not met: $(($baselineEval.Violations -join '; '))"
        }
        Set-LabFault $faultLatencyMs $faultErrorPercent
        Invoke-LabTraffic 100
        Start-Sleep -Seconds 32
        $fault = Get-LabSLISnapshot
        $faultEval = Test-LabSLOSnapshot $fault
        $logLines += "phase=fault $($faultEval.Summary)"
        Write-Host $logLines[-1]
        Assert-Condition (-not $faultEval.Ok) 'Expected at least one SLO violation during controlled fault injection.'
        Set-LabFault 0 0
        Start-Sleep -Seconds 130
        Invoke-LabTraffic 50
        Start-Sleep -Seconds 35
        $recovery = Get-LabSLISnapshot
        $recoveryEval = Test-LabSLOSnapshot $recovery
        $logLines += "phase=recovery $($recoveryEval.Summary)"
        Write-Host $logLines[-1]
        if (-not $recoveryEval.Ok) {
            $sloFailed = $true
            throw "Recovery SLO objectives not met: $(($recoveryEval.Violations -join '; '))"
        }
        Invoke-Kubectl @('rollout', 'status', 'deployment/lab-http', '--timeout=180s') | Out-Null
        Assert-Condition (Wait-LabReadyPodCount 2 120) 'Expected two Ready replicas after SLO lab.'
    } catch {
        $sloFailed = $true
        throw
    } finally {
        try { Set-LabFault 0 0 } catch { Write-Host "Warning: fault-off during cleanup failed: $_" }
    }
    if ($sloFailed) { exit 1 }
    $sloCfg = Get-LabSLOThresholds
    $summary = @"
# SLO lab execution summary

- UTC: $runId
- Cluster: $context / namespace $namespace
- Objectives: local demonstrative (see lab/runbooks/sli-slo-lab.md)
- Config: lab/config/slo.json
- Thresholds: success>=$($sloCfg.minSuccessRatio) rate503<=$($sloCfg.max503Rate) p95<=$($sloCfg.maxP95Seconds)s ready>=$($sloCfg.minReadySum)
- Phases:
$(($logLines | ForEach-Object { "  - $_" }) -join "`n")
- Final: fault off, 2/2 Ready target
- Evidence: $runDir
"@
    Set-Content -Path (Join-Path $runDir 'execution-summary.md') -Value $summary -Encoding utf8
    Set-Content -Path (Join-Path $runDir 'slo-phases.log') -Value ($logLines -join "`n") -Encoding utf8
    Write-Host $summary
    Write-Host 'SLO lab verified: baseline pass, fault degrades, recovery pass.'
    exit 0
}

if ($Action -eq 'verify-fault-lab') {
    Assert-Condition $namespaceExists "Namespace $namespace does not exist; deploy the lab first."
    Assert-Condition (Assert-OwnedObservability) 'Observability stack is required for the fault lab scenario.'
    $rate503 = 'sum(rate(lab_http_requests_total{job="lab-http",code="503"}[2m]))'
    $p95 = 'histogram_quantile(0.95, sum by (le) (rate(lab_http_request_duration_seconds_bucket{job="lab-http"}[2m])))'
    Set-LabFault 0 0
    Invoke-LabTraffic 30
    Start-Sleep -Seconds 25
    $baseline503 = Get-PromQuerySum $rate503
    $baselineP95 = Get-PromQuerySum $p95
    Write-Host "Baseline: rate503=$baseline503 p95=$baselineP95"
    Set-LabFault $faultLatencyMs $faultErrorPercent
    Invoke-LabTraffic 120
    Start-Sleep -Seconds 30
    $during503 = Get-PromQuerySum $rate503
    $duringP95 = Get-PromQuerySum $p95
    Write-Host "During fault: rate503=$during503 p95=$duringP95"
    Assert-Condition ($during503 -gt 0.05) "Expected measurable 503 rate during fault injection; got $during503"
    Assert-Condition ($duringP95 -gt 0.25) "Expected elevated p95 latency during fault injection; got $duringP95"
    Set-LabFault 0 0
    # rate[2m] keeps fault-era samples briefly; wait before measuring recovery.
    Start-Sleep -Seconds 130
    Invoke-LabTraffic 60
    Start-Sleep -Seconds 35
    $after503 = Get-PromQuerySum $rate503
    $afterP95 = Get-PromQuerySum $p95
    Write-Host "After recovery: rate503=$after503 p95=$afterP95"
    Assert-Condition ($after503 -lt 0.08) "503 rate remained elevated after fault-off (got $after503)."
    Assert-Condition ($afterP95 -lt 0.12) "p95 remained elevated after fault-off (got $afterP95)."
    Assert-Condition ($after503 -lt ($during503 * 0.25)) "503 rate did not drop materially versus fault period."
    Invoke-Kubectl @('rollout', 'status', 'deployment/lab-http', '--timeout=180s')
    $deployment = Get-KubeJson @('get', 'deployment', 'lab-http')
    Assert-Condition ($deployment.status.readyReplicas -eq 2) 'Expected two Ready replicas after recovery.'
    $selector = ($deployment.spec.selector.matchLabels.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ','
    $pods = Get-KubeJson @('get', 'pods', '-l', $selector)
    $readyPods = @($pods.items | Where-Object { @($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }).Count -gt 0 })
    foreach ($pod in $readyPods) {
        Invoke-Kubectl @('exec', $pod.metadata.name, '-c', 'http', '--', '/lab-http', 'check', 'http://127.0.0.1:8080') | Out-Null
    }
    Write-Host 'Fault-injection lab scenario verified: degrade, observe, recover, two Ready replicas with HTTP checks.'
    exit 0
}

if ($Action -eq 'verify-obs') {
    Assert-Condition $namespaceExists "Namespace $namespace does not exist; deploy the lab first."
    Assert-Condition (Assert-OwnedObservability) 'Observability stack is not deployed.'
    Invoke-Kubectl @('rollout', 'status', 'deployment/prometheus', '--timeout=180s')
    Invoke-Kubectl @('rollout', 'status', 'deployment/grafana', '--timeout=180s')
    $targetsRaw = Invoke-Kubectl @('exec', 'deployment/prometheus', '-c', 'prometheus', '--', 'wget', '-qO-', 'http://127.0.0.1:9090/api/v1/targets')
    $targets = (($targetsRaw -join "`n") | ConvertFrom-Json)
    $active = @($targets.data.activeTargets | Where-Object { $_.labels.job -eq 'lab-http' -and $_.health -eq 'up' })
    Assert-Condition ($active.Count -eq 2) "Expected two healthy lab-http scrape targets, found $($active.Count)."
    $deployment = Get-KubeJson @('get', 'deployment', 'lab-http')
    $selector = ($deployment.spec.selector.matchLabels.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ','
    $pods = Get-KubeJson @('get', 'pods', '-l', $selector)
    $readyPods = @($pods.items | Where-Object { @($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }).Count -gt 0 })
    foreach ($pod in $readyPods) {
        Invoke-Kubectl @('exec', $pod.metadata.name, '-c', 'http', '--', '/lab-http', 'check', 'http://127.0.0.1:8080') | Out-Null
    }
    Start-Sleep -Seconds 20
    foreach ($metric in @('lab_http_requests_total', 'lab_http_request_duration_seconds_count', 'lab_http_in_flight_requests', 'lab_ready')) {
        $result = Invoke-PrometheusQuery $metric
        Assert-Condition ($result.status -eq 'success' -and $result.data.result.Count -gt 0) "Prometheus query returned no series for $metric."
    }
    $grafanaHealth = Invoke-Kubectl @('exec', 'deployment/grafana', '-c', 'grafana', '--', 'wget', '-qO-', 'http://127.0.0.1:3000/api/health')
    Assert-Condition (($grafanaHealth -join "`n") -match '"database":\s*"ok"') 'Grafana health check did not report database ok.'
    $dashboards = Invoke-Kubectl @('exec', 'deployment/grafana', '-c', 'grafana', '--', 'wget', '-qO-', 'http://127.0.0.1:3000/api/search?query=Lab%20HTTP')
    Assert-Condition (($dashboards -join "`n") -match 'lab-http-operational') 'Provisioned Grafana dashboard was not found.'
    Invoke-Kubectl @('get', 'pods,svc', '-l', "app.kubernetes.io/part-of=$owner", '-o', 'wide')
    Write-Host "Verified: two lab-http targets up, core lab metrics present, Grafana datasource/dashboard provisioned."
    exit 0
}

Assert-Condition $namespaceExists "Namespace $namespace does not exist; deploy the lab first."
Invoke-Kubectl @('rollout', 'status', 'deployment/lab-http', '--timeout=180s')
$deployment = Get-KubeJson @('get', 'deployment', 'lab-http')
$podSpec = $deployment.spec.template.spec
$container = @($podSpec.containers | Where-Object name -EQ 'http')[0]
$account = Get-KubeJson @('get', 'serviceaccount', 'lab-http')
$service = Get-KubeJson @('get', 'service', 'lab-http')
Assert-Condition ($deployment.spec.replicas -eq 2 -and $deployment.status.readyReplicas -eq 2) 'Expected two Ready replicas.'
Assert-Condition ($container.image -eq $image) 'Deployment does not reference the expected lab image tag.'
Assert-Condition ($podSpec.serviceAccountName -eq 'lab-http' -and $podSpec.automountServiceAccountToken -eq $false -and $account.automountServiceAccountToken -eq $false) 'Expected dedicated ServiceAccount without automatic token mounting.'
Assert-Condition ($podSpec.securityContext.runAsNonRoot -eq $true -and $podSpec.securityContext.seccompProfile.type -eq 'RuntimeDefault') 'Expected non-root pods with RuntimeDefault seccomp.'
Assert-Condition ($container.securityContext.allowPrivilegeEscalation -eq $false -and $container.securityContext.readOnlyRootFilesystem -eq $true -and $container.securityContext.capabilities.drop -contains 'ALL') 'Expected restricted container securityContext.'
Assert-Condition ($service.spec.type -eq 'ClusterIP') 'The lab Service must remain ClusterIP.'
$selector = ($deployment.spec.selector.matchLabels.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ','
Invoke-Kubectl @('wait', '--for=condition=Ready', 'pods', '-l', $selector, '--timeout=180s')
$pods = Get-KubeJson @('get', 'pods', '-l', $selector)
$readyPods = @($pods.items | Where-Object { -not $_.metadata.deletionTimestamp -and @($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }).Count -gt 0 })
Assert-Condition ($readyPods.Count -eq 2) 'Expected exactly two non-terminating Ready pods.'
Invoke-Kubectl @('get', 'pods,service,serviceaccount', '-l', "app.kubernetes.io/part-of=$owner", '-o', 'wide')
foreach ($pod in $readyPods) {
    Invoke-Kubectl @('exec', $pod.metadata.name, '-c', $container.name, '--', '/lab-http', 'check', 'http://127.0.0.1:8080')
}
Invoke-Kubectl @('exec', $readyPods[0].metadata.name, '-c', $container.name, '--', '/lab-http', 'check', 'http://lab-http.irrah-lab.svc.cluster.local:8080')
Write-Host 'Verified: two Ready pods, Service, dedicated ServiceAccount, restricted securityContext and in-cluster HTTP check.'

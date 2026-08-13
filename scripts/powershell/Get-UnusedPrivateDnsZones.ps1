#Requires -Version 7.0
<#
.SYNOPSIS
    READ-ONLY discovery of unused Azure private DNS zones.

.DESCRIPTION
    Identifies private DNS zones that satisfy ALL of the following:

      1. Zero virtual network links.
      2. No record sets other than the SOA record Azure auto-creates at the zone
         apex. Any A, AAAA, CNAME, MX, PTR, SRV or TXT record set disqualifies
         the zone.
      3. Created more than -MinimumAgeDays ago (default 30).

    The script performs THREE independent passes and only reports a zone as
    delete-eligible when all three agree:

      Stage 1  Azure Resource Graph sweep (fast, snapshot data, may lag).
      Stage 2  Authoritative control-plane re-verification per candidate zone
               (az network private-dns link/record-set list). Authoritative.
      Stage 3  Age gate using the ARM resources list API with $expand=createdTime.

    This script NEVER mutates Azure. It issues only GET/POST-query operations and
    contains no create, update or delete call path. Producing this report is not
    authorization to delete anything - see the accompanying change plan at
    docs/change-plans/2026-08-11-private-dns-zone-cleanup-plan.md.

.PARAMETER SubscriptionId
    Subscriptions to sweep. Omit to sweep every subscription that the signed-in
    identity can enumerate and that is in the Enabled state.

.PARAMETER ExpectedTenantId
    Optional guard. If supplied and the active az context is signed in to a
    different tenant, the script stops before querying anything (AGENTS.md §5.3).

.PARAMETER MinimumAgeDays
    A zone created within this many days is reported but NOT marked eligible.
    Guards against deleting zones that are mid-deployment, where infrastructure
    code or policy created the zone but the links and records have not landed yet.

.PARAMETER OutputDirectory
    Directory for the generated report. Defaults to <repo-root>/Output.

.PARAMETER SkipRecordSetVerification
    Diagnostic only. Skips Stage 2. The resulting report is NOT sufficient
    evidence for a deletion decision. Not for use in an approval package.

.EXAMPLE
    ./Get-UnusedPrivateDnsZones.ps1 -ExpectedTenantId '7d689bf5-26f6-44a2-b080-61689eff65a6' -Verbose

.EXAMPLE
    ./Get-UnusedPrivateDnsZones.ps1 -SubscriptionId '65d61542-...','93ad3e04-...' -MinimumAgeDays 90

.NOTES
    Requires  : PowerShell 7+, Azure CLI (core only - no extension needed), and
                Reader on every in-scope subscription.
    Exit codes: 0 eligible zones found | 2 none found | 3 context/auth failure
                | 4 completed with coverage or verification warnings

    Windows / PowerShell pitfalls this script must keep handling:
      1. ConvertFrom-Json of '[]' piped or returned from a function becomes $null
         (empty-array unrolling). Every unused zone has 0 VNet links, so Stage 2
         link list returns []. Treat that as an empty array, not a failed call.
      2. az.cmd splits unquoted --url values on '&'. Stage 3 ARM URLs contain
         &$expand and &$filter; wrap those URLs in quotes before invoking az.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]] $SubscriptionId,

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string] $ExpectedTenantId,

    [Parameter()]
    [ValidateRange(0, 3650)]
    [int] $MinimumAgeDays = 30,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputDirectory = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Output'),

    [Parameter()]
    [switch] $SkipRecordSetVerification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:LastAzError = ''

function Write-Phase {
    param([string] $Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Add-CoverageWarning {
    param([string] $Message)
    $script:Warnings.Add($Message) | Out-Null
    Write-Warning $Message
}

# az.cmd on Windows treats '&' in an unquoted --url as a command separator, so
# ARM query strings like &$expand=...&$filter=... must be wrapped in quotes.
function Protect-AzCmdUrlArguments {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]] $Arguments)

    $protected = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $token = $Arguments[$i]
        $protected.Add($token) | Out-Null
        if ($token -in @('--url', '--uri') -and ($i + 1) -lt $Arguments.Count) {
            $i++
            $url = $Arguments[$i]
            $alreadyQuoted = $url.StartsWith('"') -and $url.EndsWith('"') -and $url.Length -ge 2
            if (-not $alreadyQuoted -and $url.Contains('&')) {
                $url = '"' + $url + '"'
            }
            $protected.Add($url) | Out-Null
        }
    }
    return ,$protected.ToArray()
}

# Converts az --output json text into objects. Empty and single-element JSON
# arrays must remain arrays; PowerShell otherwise unrolls them to $null / a scalar.
function ConvertFrom-AzCliJson {
    [CmdletBinding()]
    param($Raw)

    if ($null -eq $Raw) { return $null }
    $text = if ($Raw -is [System.Array]) { $Raw -join "`n" } else { [string]$Raw }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $parsed = ConvertFrom-Json -InputObject $text -Depth 100 -NoEnumerate
    if ($parsed -is [array]) {
        return ,$parsed
    }
    return $parsed
}

# Invokes an az CLI command, captures stderr and the exit code, and returns the
# parsed JSON payload. Retries on throttling and transient 5xx responses.
function Invoke-AzJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [int] $MaxAttempts = 4,
        [switch] $TolerateFailure
    )

    $azArgs = Protect-AzCmdUrlArguments -Arguments $Arguments

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $stdErrFile = [System.IO.Path]::GetTempFileName()
        try {
            $raw = & az @azArgs --only-show-errors --output json 2>$stdErrFile
            $exitCode = $LASTEXITCODE
            $stdErr = (Get-Content -Path $stdErrFile -Raw -ErrorAction SilentlyContinue) ?? ''

            if ($exitCode -eq 0) {
                $script:LastAzError = ''
                $parsed = ConvertFrom-AzCliJson -Raw $raw
                if ($null -eq $parsed) { return $null }
                if ($parsed -is [array]) { return ,$parsed }
                return $parsed
            }

            $isTransient = $stdErr -match '(?i)throttl|429|timeout|temporarily|50[0-4]|connection reset'
            if ($isTransient -and $attempt -lt $MaxAttempts) {
                $delay = [math]::Pow(2, $attempt)
                Write-Verbose "Transient az failure (exit $exitCode), retrying in ${delay}s: $($stdErr.Trim())"
                Start-Sleep -Seconds $delay
                continue
            }

            $script:LastAzError = $stdErr.Trim()
            if ($TolerateFailure) {
                Write-Verbose "az failed (exit $exitCode): $($script:LastAzError)"
                return $null
            }
            throw "az $($Arguments -join ' ') failed with exit code ${exitCode}: $($script:LastAzError)"
        }
        finally {
            Remove-Item -Path $stdErrFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# --------------------------------------------------------------------------
# Stage 0 - context check (AGENTS.md §3.2: never guess tenant or subscription)
# --------------------------------------------------------------------------
Write-Phase 'Stage 0: Azure context'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error 'Azure CLI (az) was not found on PATH.'
    exit 3
}

try {
    $account = Invoke-AzJson -Arguments @('account', 'show')
}
catch {
    Write-Error "Not signed in to Azure. Run 'az login' first. $_"
    exit 3
}

$signedInAs = if ($account.PSObject.Properties.Name -contains 'user' -and $account.user) { $account.user.name } else { '<non-user principal>' }
Write-Host ("Tenant       : {0}" -f $account.tenantId)
Write-Host ("Signed in as : {0}" -f $signedInAs)

if ($ExpectedTenantId -and $account.tenantId -ne $ExpectedTenantId) {
    Write-Error ("Tenant mismatch. Expected '{0}' but the active context is '{1}'. Stopping before any query." -f $ExpectedTenantId, $account.tenantId)
    exit 3
}

if ($SubscriptionId) {
    $targetSubs = @($SubscriptionId)
    Write-Host ("Scope        : {0} explicitly supplied subscription(s)" -f $targetSubs.Count)
}
else {
    $allSubs = Invoke-AzJson -Arguments @('account', 'list', '--all')
    $targetSubs = @($allSubs | Where-Object { $_.state -eq 'Enabled' } | Select-Object -ExpandProperty id)
    Write-Host ("Scope        : {0} enabled subscription(s) visible to this identity" -f $targetSubs.Count)
    Add-CoverageWarning ("Tenant sweep covers only subscriptions this identity can read ({0} found). An empty result does not prove no unused zones exist elsewhere." -f $targetSubs.Count)
}

if ($targetSubs.Count -eq 0) {
    Write-Error 'No in-scope subscriptions resolved.'
    exit 3
}

# --------------------------------------------------------------------------
# Stage 1 - Resource Graph sweep
# --------------------------------------------------------------------------
Write-Phase 'Stage 1: Resource Graph candidate sweep'

# Uses the Resource Graph REST API through 'az rest' so that no CLI extension has
# to be installed (AGENTS.md §14: do not install an extension without authorization).
$argQuery = @'
resources
| where type =~ 'microsoft.network/privatednszones'
| extend vnetLinks = toint(properties.numberOfVirtualNetworkLinks),
         regLinks  = toint(properties.numberOfVirtualNetworkLinksWithRegistration),
         recordSets = toint(properties.numberOfRecordSets),
         provisioningState = tostring(properties.provisioningState)
| where isnotnull(vnetLinks) and isnotnull(recordSets)
| where vnetLinks == 0
| where recordSets <= 2
| project zoneName = name, subscriptionId, resourceGroup, vnetLinks, regLinks,
          recordSets, provisioningState, zoneId = id
'@
# NOTE on 'recordSets <= 2': this is a deliberately loose PRE-FILTER, not the test.
# Microsoft's docs conflict on whether a pristine private zone's apex holds SOA only
# (baseline 1) or SOA + NS (baseline 2). A bound of 2 cannot silently miss zones
# under either baseline. Eligibility is decided in Stage 2 by record TYPE - a zone
# qualifies only if it holds no record set outside the auto-created apex defaults.

$candidates = [System.Collections.Generic.List[object]]::new()
$argUrl = 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01'

# Resource Graph accepts at most 1000 subscriptions per request.
for ($i = 0; $i -lt $targetSubs.Count; $i += 1000) {
    $batch = $targetSubs[$i..([math]::Min($i + 999, $targetSubs.Count - 1))]
    $skipToken = $null

    do {
        $options = @{ resultFormat = 'objectArray'; '$top' = 1000 }
        if ($skipToken) { $options['$skipToken'] = $skipToken }

        $bodyFile = [System.IO.Path]::GetTempFileName()
        try {
            @{ subscriptions = @($batch); query = $argQuery; options = $options } |
                ConvertTo-Json -Depth 10 -Compress |
                Set-Content -Path $bodyFile -Encoding utf8

            $response = Invoke-AzJson -Arguments @('rest', '--method', 'post', '--url', $argUrl, '--body', "@$bodyFile")
        }
        finally {
            Remove-Item -Path $bodyFile -Force -ErrorAction SilentlyContinue
        }

        if ($response -and $response.PSObject.Properties.Name -contains 'data' -and $response.data) {
            foreach ($row in $response.data) { $candidates.Add($row) | Out-Null }
        }

        $skipToken = if ($response -and $response.PSObject.Properties.Name -contains '$skipToken') { $response.'$skipToken' } else { $null }
    } while ($skipToken)
}

Write-Host ("Stage 1 candidates: {0}" -f $candidates.Count)

if ($candidates.Count -eq 0) {
    Write-Host 'No private DNS zone matched both conditions. Nothing to report.' -ForegroundColor Green
    exit 2
}

# --------------------------------------------------------------------------
# Stage 3 data - creation time per subscription (gathered before Stage 2 so the
# age gate is available even if a Stage 2 verification is inconclusive).
# The ARM 'resources' list API is the only surface exposing createdTime, and only
# via $expand on the LIST endpoint - Get-by-id cannot return it.
# --------------------------------------------------------------------------
Write-Phase 'Stage 3 data: zone creation times'

$createdLookup = @{}
$subsWithCandidates = @($candidates | Select-Object -ExpandProperty subscriptionId -Unique)

foreach ($sub in $subsWithCandidates) {
    $filter = [uri]::EscapeDataString("resourceType eq 'Microsoft.Network/privateDnsZones'")
    $next = 'https://management.azure.com/subscriptions/' + $sub +
            '/resources?api-version=2021-04-01&$expand=createdTime,changedTime&$filter=' + $filter

    while ($next) {
        $page = Invoke-AzJson -Arguments @('rest', '--method', 'get', '--url', $next) -TolerateFailure
        if (-not $page) {
            Add-CoverageWarning "Could not read creation times for subscription $sub. Zones there cannot pass the age gate."
            break
        }

        foreach ($res in @($page.value)) {
            $created = if ($res.PSObject.Properties.Name -contains 'createdTime') { $res.createdTime } else { $null }
            $changed = if ($res.PSObject.Properties.Name -contains 'changedTime') { $res.changedTime } else { $null }
            $createdLookup[$res.id.ToLowerInvariant()] = [pscustomobject]@{ CreatedTime = $created; ChangedTime = $changed }
        }

        $next = if ($page.PSObject.Properties.Name -contains 'nextLink') { $page.nextLink } else { $null }
    }
}

# --------------------------------------------------------------------------
# Stage 2 - authoritative per-zone verification against the control plane
# --------------------------------------------------------------------------
Write-Phase 'Stage 2: control-plane verification'

$ageCutoff = (Get-Date).ToUniversalTime().AddDays(-$MinimumAgeDays)
$results = [System.Collections.Generic.List[object]]::new()
$index = 0

foreach ($zone in $candidates) {
    $index++
    Write-Verbose ("[{0}/{1}] Verifying {2} ({3})" -f $index, $candidates.Count, $zone.zoneName, $zone.subscriptionId)

    $verifiedLinks     = $null
    $verifiedRecords   = $null
    $observedTypes     = @()
    $verificationError = $null

    if (-not $SkipRecordSetVerification) {
        $links = Invoke-AzJson -TolerateFailure -Arguments @(
            'network', 'private-dns', 'link', 'vnet', 'list',
            '--subscription', $zone.subscriptionId,
            '--resource-group', $zone.resourceGroup,
            '--zone-name', $zone.zoneName)

        $records = Invoke-AzJson -TolerateFailure -Arguments @(
            'network', 'private-dns', 'record-set', 'list',
            '--subscription', $zone.subscriptionId,
            '--resource-group', $zone.resourceGroup,
            '--zone-name', $zone.zoneName)

        if ($null -eq $links -or $null -eq $records) {
            $verificationError = if ($script:LastAzError) {
                "Control-plane verification failed: $($script:LastAzError)"
            } else {
                'Control-plane verification failed (az returned no JSON).'
            }
            Add-CoverageWarning ("Verification failed for zone '{0}' in {1}. Marked ineligible." -f $zone.zoneName, $zone.subscriptionId)
        }
        else {
            $verifiedLinks = @($links).Count
            $recordArray = @($records)
            $verifiedRecords = $recordArray.Count
            # type looks like 'Microsoft.Network/privateDnsZones/SOA'
            $observedTypes = @($recordArray | ForEach-Object { ($_.type -split '/')[-1].ToUpperInvariant() } | Sort-Object -Unique)
        }
    }

    # SOA and NS are both treated as auto-created apex defaults, so the verdict is
    # correct whichever baseline this tenant actually exhibits.
    $defaultRecordTypes = @('SOA', 'NS')
    $nonDefault = @($observedTypes | Where-Object { $_ -notin $defaultRecordTypes })

    $createdInfo = $createdLookup[$zone.zoneId.ToLowerInvariant()]
    $createdTime = if ($createdInfo) { $createdInfo.CreatedTime } else { $null }
    $ageDays     = if ($createdTime) { [math]::Floor(((Get-Date).ToUniversalTime() - [datetime]$createdTime).TotalDays) } else { $null }

    $passesAge = ($null -ne $createdTime) -and ([datetime]$createdTime -lt $ageCutoff)

    # Eligibility keys off record TYPE, not the record-set count, so it does not
    # depend on the unresolved SOA-only vs SOA+NS baseline question.
    $eligible = (-not $SkipRecordSetVerification) -and
                ($null -eq $verificationError) -and
                ($verifiedLinks -eq 0) -and
                ($nonDefault.Count -eq 0) -and
                $passesAge

    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($SkipRecordSetVerification)      { $reasons.Add('Stage 2 skipped - not decision-grade') | Out-Null }
    if ($verificationError)              { $reasons.Add($verificationError) | Out-Null }
    if ($verifiedLinks -gt 0)            { $reasons.Add("Has $verifiedLinks VNet link(s) - ARG snapshot was stale") | Out-Null }
    if ($nonDefault.Count -gt 0)         { $reasons.Add("Holds non-default record set(s): $($nonDefault -join ', ')") | Out-Null }
    if ($null -eq $createdTime)          { $reasons.Add('Creation time unavailable - age gate cannot be satisfied') | Out-Null }
    elseif (-not $passesAge)             { $reasons.Add("Created $ageDays day(s) ago - inside the $MinimumAgeDays-day grace period") | Out-Null }

    $results.Add([pscustomobject]@{
        ZoneName            = $zone.zoneName
        SubscriptionId      = $zone.subscriptionId
        ResourceGroup       = $zone.resourceGroup
        ArgVnetLinks        = $zone.vnetLinks
        ArgRecordSets       = $zone.recordSets
        VerifiedVnetLinks   = $verifiedLinks
        VerifiedRecordSets  = $verifiedRecords
        ObservedRecordTypes = ($observedTypes -join ',')
        CreatedTimeUtc      = $createdTime
        AgeDays             = $ageDays
        PassesAgeGate       = $passesAge
        Eligible            = $eligible
        Notes               = ($reasons -join '; ')
        ZoneId              = $zone.zoneId
    }) | Out-Null
}

# --------------------------------------------------------------------------
# Stage 4 - report (AGENTS.md §18.2: timestamped filenames under Output/)
# --------------------------------------------------------------------------
Write-Phase 'Stage 4: report'

if (-not (Test-Path -Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$stamp    = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$csvPath  = Join-Path $OutputDirectory "$stamp-unused-private-dns-zones.csv"
$jsonPath = Join-Path $OutputDirectory "$stamp-unused-private-dns-zones.json"

$results | Sort-Object -Property Eligible, SubscriptionId, ZoneName -Descending |
    Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8

[pscustomobject]@{
    GeneratedUtc          = (Get-Date).ToUniversalTime().ToString('o')
    TenantId              = $account.tenantId
    SubscriptionsSwept    = $targetSubs.Count
    MinimumAgeDays        = $MinimumAgeDays
    Stage2Performed       = (-not $SkipRecordSetVerification.IsPresent)
    CandidatesFromArg     = $candidates.Count
    EligibleForDeletion   = @($results | Where-Object Eligible).Count
    Warnings              = @($script:Warnings)
    Zones                 = $results
} | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding utf8

$eligibleCount = @($results | Where-Object Eligible).Count

Write-Host ""
$results | Format-Table ZoneName, SubscriptionId, ResourceGroup, VerifiedVnetLinks,
                        VerifiedRecordSets, ObservedRecordTypes, AgeDays, Eligible -AutoSize

Write-Host ("`nCandidates from Resource Graph : {0}" -f $candidates.Count)
Write-Host ("Eligible after all three gates : {0}" -f $eligibleCount)
Write-Host ("CSV  : {0}" -f $csvPath)
Write-Host ("JSON : {0}" -f $jsonPath)

if ($script:Warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    $script:Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

Write-Host "`nThis report is evidence only. Deletion is a Class 4 destructive change and" -ForegroundColor Yellow
Write-Host "requires explicit final authorization naming the exact zones (AGENTS.md §5.1)." -ForegroundColor Yellow

if ($script:Warnings.Count -gt 0) { exit 4 }
if ($eligibleCount -eq 0)         { exit 2 }
exit 0

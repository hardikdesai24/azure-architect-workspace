#Requires -Version 7.0
<#
.SYNOPSIS
    READ-ONLY inventory of Azure App Service apps configured for Node.js 22.

.DESCRIPTION
    Identifies Web Apps, Function Apps, and (optionally) deployment slots whose
    configured runtime is Node.js 22 LTS. This supports the Microsoft App Service
    advisory (tracking id 9Z2G-WGG): Node 22 LTS support ends 30 April 2027;
    the upgrade target is Node 24 LTS.

    Two independent passes:

      Stage 1  Azure Resource Graph sweep (fast, snapshot data, may lag).
      Stage 2  Authoritative control-plane verification:
               az webapp config show (linuxFxVersion / nodeVersion)
               az webapp config appsettings list (WEBSITE_NODE_DEFAULT_VERSION)
               az webapp deployment slot list when -IncludeSlots is true.

    This script NEVER mutates Azure. It issues only GET/POST-query operations.
    Producing this report is not authorization to change a runtime.

    Configured runtime is not a live `node -v` result. Custom Docker apps are
    classified as Container and are not treated as Node 22 unless the stack
    string itself contains NODE|22.

.PARAMETER SubscriptionId
    Subscriptions to sweep. Omit to sweep every subscription that the signed-in
    identity can enumerate and that is in the Enabled state.

.PARAMETER ExpectedTenantId
    Optional guard. If supplied and the active az context is signed in to a
    different tenant, the script stops before querying anything (CLAUDE.md §5.3).

.PARAMETER OutputDirectory
    Directory for the generated report. Defaults to <repo-root>/output/node22-upgrade.

.PARAMETER IncludeSlots
    When true (default), inventory Microsoft.Web/sites/slots and list slots
    under each production app that is in the Node/Windows review set.

.PARAMETER IncludeFunctionApps
    When true (default), include sites whose kind contains functionapp.

.PARAMETER SkipCliVerification
    Diagnostic only. Skips Stage 2. Windows Node 22 apps whose app settings are
    absent from ARG will be missed. Not for a stakeholder inventory.

.EXAMPLE
    ./Get-AppServiceNode22Inventory.ps1 -ExpectedTenantId '7d689bf5-26f6-44a2-b080-61689eff65a6' -Verbose

.EXAMPLE
    ./Get-AppServiceNode22Inventory.ps1 -SubscriptionId 'eedbfd35-f6c7-4ac2-9730-4d0c4be52821' -IncludeSlots:$false

.NOTES
    Requires  : PowerShell 7+, Azure CLI (core only - Resource Graph is called
                via az rest so the resource-graph extension is not required),
                and Reader on every in-scope subscription.
    Exit codes: 0 Node 22 apps found | 2 none found | 3 context/auth failure
                | 4 completed with coverage or verification warnings

    Windows / PowerShell pitfalls this script must keep handling:
      1. ConvertFrom-Json of '[]' piped or returned from a function becomes $null
         (empty-array unrolling). Treat empty appsettings/slot lists as [].
      2. az.cmd splits unquoted --url values on '&'.
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
    [ValidateNotNullOrEmpty()]
    [string] $OutputDirectory = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'output\node22-upgrade'),

    [Parameter()]
    [bool] $IncludeSlots = $true,

    [Parameter()]
    [bool] $IncludeFunctionApps = $true,

    [Parameter()]
    [switch] $SkipCliVerification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:LastAzError = ''
$script:SubNameById = @{}

# Apps named in Microsoft's 19 August 2026 Node 22 end-of-support notice.
$script:NoticeAppNames = @(
    'app-hand-hygiene-dev-ncus',
    'app-notification-service-dev-ncus',
    'app-audit-log-dev-ncus',
    'app-ora-dev-ncus',
    'app-portal-dev-ncus',
    'app-pmm-dev-ncus',
    'app-hhs-dev-ncus',
    'app-labor-pool-dev-ncus'
)
$script:NoticeSubscriptionId = 'eedbfd35-f6c7-4ac2-9730-4d0c4be52821'
$script:AdvisoryTrackingId = '9Z2G-WGG'

function Write-Phase {
    param([string] $Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Add-CoverageWarning {
    param([string] $Message)
    $script:Warnings.Add($Message) | Out-Null
    Write-Warning $Message
}

function Get-NotePropertyValue {
    param($Object, [string] $Name)
    if ($null -eq $Object) { return $null }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

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

function Get-KqlFromFile {
    param([Parameter(Mandatory)][string] $Path)

    $lines = Get-Content -Path $Path
    $queryLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $trimmed = $line.TrimStart()
        if ($trimmed.StartsWith('//')) { continue }
        $queryLines.Add($line) | Out-Null
    }
    $text = ($queryLines -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "KQL file '$Path' contained no executable query after comment stripping."
    }
    return $text
}

function Invoke-ResourceGraphQuery {
    param(
        [Parameter(Mandatory)][string] $Query,
        [Parameter(Mandatory)][string[]] $SubscriptionIds
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    $argUrl = 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01'

    for ($i = 0; $i -lt $SubscriptionIds.Count; $i += 1000) {
        $batch = $SubscriptionIds[$i..([math]::Min($i + 999, $SubscriptionIds.Count - 1))]
        $skipToken = $null

        do {
            $options = @{ resultFormat = 'objectArray'; '$top' = 1000 }
            if ($skipToken) { $options['$skipToken'] = $skipToken }

            $bodyFile = [System.IO.Path]::GetTempFileName()
            try {
                @{ subscriptions = @($batch); query = $Query; options = $options } |
                    ConvertTo-Json -Depth 10 -Compress |
                    Set-Content -Path $bodyFile -Encoding utf8

                $response = Invoke-AzJson -Arguments @('rest', '--method', 'post', '--url', $argUrl, '--body', "@$bodyFile")
            }
            finally {
                Remove-Item -Path $bodyFile -Force -ErrorAction SilentlyContinue
            }

            $data = Get-NotePropertyValue -Object $response -Name 'data'
            foreach ($row in @($data)) {
                if ($null -eq $row) { continue }
                if ($row -is [string]) { continue }
                $rows.Add($row) | Out-Null
            }

            $skipToken = Get-NotePropertyValue -Object $response -Name '$skipToken'
            if (-not $skipToken) {
                $skipToken = Get-NotePropertyValue -Object $response -Name 'skipToken'
            }
        } while ($skipToken)
    }

    return $rows
}

function Get-SiteNames {
    param(
        [string] $Type,
        [Parameter(Mandatory)][string] $Name,
        [string] $ResourceId
    )

    $resolvedType = $Type
    if ([string]::IsNullOrWhiteSpace($resolvedType) -and $ResourceId) {
        if ($ResourceId -match '(?i)/slots/') { $resolvedType = 'microsoft.web/sites/slots' }
        else { $resolvedType = 'microsoft.web/sites' }
    }

    $isSlot = $resolvedType -match '(?i)sites/slots$'
    if ($isSlot) {
        $parts = @($Name -split '/', 2)
        return [pscustomobject]@{
            AppName    = $parts[0]
            SlotName   = if ($parts.Count -gt 1) { $parts[1] } else { $Name }
            IsSlot     = $true
        }
    }

    return [pscustomobject]@{
        AppName  = $Name
        SlotName = 'production'
        IsSlot   = $false
    }
}

function Get-PlatformFromKind {
    param([string] $Kind)
    if ([string]::IsNullOrWhiteSpace($Kind)) { return 'Windows' }
    if ($Kind -match '(?i)linux') { return 'Linux' }
    return 'Windows'
}

function Test-IsFunctionApp {
    param([string] $Kind)
    return ($Kind -match '(?i)functionapp')
}

function Get-RuntimeClassification {
    param(
        [string] $LinuxFxVersion,
        [string] $WindowsFxVersion,
        [string] $NodeVersion,
        [string] $NodeAppSetting
    )

    $values = @(
        [pscustomobject]@{ Source = 'linuxFxVersion'; Value = $LinuxFxVersion },
        [pscustomobject]@{ Source = 'windowsFxVersion'; Value = $WindowsFxVersion },
        [pscustomobject]@{ Source = 'nodeVersion'; Value = $NodeVersion },
        [pscustomobject]@{ Source = 'WEBSITE_NODE_DEFAULT_VERSION'; Value = $NodeAppSetting }
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Value) }
    $values = @($values)

    $configured = ($values | ForEach-Object { '{0}={1}' -f $_.Source, $_.Value }) -join '; '
    if ([string]::IsNullOrWhiteSpace($configured)) { $configured = '' }

    foreach ($item in $values) {
        $v = $item.Value.Trim()
        if ($v -match '(?i)^(DOCKER|COMPOSE)\|') {
            return [pscustomobject]@{
                NodeMajor         = 'Container'
                ConfiguredRuntime = $v
                MatchSource       = $item.Source
            }
        }
    }

    foreach ($item in $values) {
        $v = $item.Value.Trim()
        if ($v -match '(?i)NODE\|(\d+)') {
            return [pscustomobject]@{
                NodeMajor         = $Matches[1]
                ConfiguredRuntime = $v
                MatchSource       = $item.Source
            }
        }
        if ($v -match '(?i)^~?(\d+)([.-]|$)') {
            return [pscustomobject]@{
                NodeMajor         = $Matches[1]
                ConfiguredRuntime = $v
                MatchSource       = $item.Source
            }
        }
    }

    $first = if ($values.Count -gt 0) { $values[0].Value } else { '' }
    return [pscustomobject]@{
        NodeMajor         = 'Unknown'
        ConfiguredRuntime = $first
        MatchSource       = if ($values.Count -gt 0) { $values[0].Source } else { '' }
    }
}

function Test-IsNode22Classification {
    param($Classification)
    return ($Classification.NodeMajor -eq '22')
}

function ConvertTo-InventoryRow {
    param($Site, [string] $SubscriptionName)

    $names = Get-SiteNames -Type ([string](Get-NotePropertyValue -Object $Site -Name 'type')) -Name ([string]$Site.name) -ResourceId ([string](Get-NotePropertyValue -Object $Site -Name 'id'))
    $kind = [string](Get-NotePropertyValue -Object $Site -Name 'kind')
    $tags = Get-NotePropertyValue -Object $Site -Name 'tags'
    $tagText = if ($tags) { ($tags.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ';' } else { '' }

    return [pscustomobject]@{
        SubscriptionName   = $SubscriptionName
        SubscriptionId     = [string]$Site.subscriptionId
        ResourceGroup      = [string]$Site.resourceGroup
        AppName            = $names.AppName
        SlotName           = $names.SlotName
        Kind               = $kind
        Location           = [string](Get-NotePropertyValue -Object $Site -Name 'location')
        State              = [string](Get-NotePropertyValue -Object $Site -Name 'siteState')
        Platform           = Get-PlatformFromKind -Kind $kind
        LinuxFxVersion     = [string](Get-NotePropertyValue -Object $Site -Name 'linuxFxVersion')
        WindowsFxVersion   = [string](Get-NotePropertyValue -Object $Site -Name 'windowsFxVersion')
        NodeVersion        = [string](Get-NotePropertyValue -Object $Site -Name 'nodeVersion')
        NodeAppSetting     = [string](Get-NotePropertyValue -Object $Site -Name 'nodeAppSetting')
        ConfiguredRuntime  = ''
        NodeMajorVersion   = ''
        DetectionSource    = 'ARG'
        InMicrosoftNotice  = [bool]($script:NoticeAppNames | Where-Object { $_ -ieq $names.AppName })
        ResourceId         = [string]$Site.id
        DefaultHostName    = [string](Get-NotePropertyValue -Object $Site -Name 'defaultHostName')
        Tags               = $tagText
        ObservedAtUtc      = ''
        Notes              = ''
        IsSlot             = $names.IsSlot
        Type               = [string](Get-NotePropertyValue -Object $Site -Name 'type')
    }
}

function Get-SubscriptionDisplayName {
    param([string] $Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return '' }
    if ($script:SubNameById.ContainsKey($Id)) { return [string]$script:SubNameById[$Id] }
    return ''
}

function Test-ShouldIncludeRow {
    param($Row)
    if (-not $IncludeFunctionApps -and (Test-IsFunctionApp -Kind $Row.Kind)) { return $false }
    if (-not $IncludeSlots -and $Row.IsSlot) { return $false }
    return $true
}

function Get-AppSettingValue {
    param($Settings, [string] $Name)
    foreach ($setting in @($Settings)) {
        $settingName = [string](Get-NotePropertyValue -Object $setting -Name 'name')
        if ($settingName -eq $Name) {
            return [string](Get-NotePropertyValue -Object $setting -Name 'value')
        }
    }
    return ''
}

function Invoke-SiteConfigVerification {
    param($Row)

    $argsConfig = @(
        'webapp', 'config', 'show',
        '--subscription', $Row.SubscriptionId,
        '--resource-group', $Row.ResourceGroup,
        '--name', $Row.AppName
    )
    $argsSettings = @(
        'webapp', 'config', 'appsettings', 'list',
        '--subscription', $Row.SubscriptionId,
        '--resource-group', $Row.ResourceGroup,
        '--name', $Row.AppName
    )
    $argsShow = @(
        'webapp', 'show',
        '--subscription', $Row.SubscriptionId,
        '--resource-group', $Row.ResourceGroup,
        '--name', $Row.AppName
    )

    if ($Row.IsSlot) {
        $argsConfig += @('--slot', $Row.SlotName)
        $argsSettings += @('--slot', $Row.SlotName)
        $argsShow += @('--slot', $Row.SlotName)
    }

    $config = Invoke-AzJson -TolerateFailure -Arguments $argsConfig
    $settings = Invoke-AzJson -TolerateFailure -Arguments $argsSettings
    $show = Invoke-AzJson -TolerateFailure -Arguments $argsShow

    if ($null -eq $config) {
        return [pscustomobject]@{
            Ok     = $false
            Error  = if ($script:LastAzError) { $script:LastAzError } else { 'az webapp config show returned no JSON' }
            Config = $null
            Setting = ''
            Show   = $null
        }
    }

    $nodeSetting = ''
    if ($null -ne $settings) {
        $nodeSetting = Get-AppSettingValue -Settings $settings -Name 'WEBSITE_NODE_DEFAULT_VERSION'
    }

    return [pscustomobject]@{
        Ok      = $true
        Error   = ''
        Config  = $config
        Setting = $nodeSetting
        Show    = $show
    }
}

function Get-SlotChildRows {
    param($ParentRow, [string] $ObservedAtUtc)

    $slots = Invoke-AzJson -TolerateFailure -Arguments @(
        'webapp', 'deployment', 'slot', 'list',
        '--subscription', $ParentRow.SubscriptionId,
        '--resource-group', $ParentRow.ResourceGroup,
        '--name', $ParentRow.AppName)

    $childRows = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $slots) { return ,$childRows.ToArray() }

    foreach ($slot in @($slots)) {
        $slotName = [string](Get-NotePropertyValue -Object $slot -Name 'name')
        if ([string]::IsNullOrWhiteSpace($slotName)) { continue }

        $child = [pscustomobject]@{
            SubscriptionName   = $ParentRow.SubscriptionName
            SubscriptionId     = $ParentRow.SubscriptionId
            ResourceGroup      = $ParentRow.ResourceGroup
            AppName            = $ParentRow.AppName
            SlotName           = $slotName
            Kind               = [string](Get-NotePropertyValue -Object $slot -Name 'kind')
            Location           = [string](Get-NotePropertyValue -Object $slot -Name 'location')
            State              = [string](Get-NotePropertyValue -Object $slot -Name 'state')
            Platform           = Get-PlatformFromKind -Kind ([string](Get-NotePropertyValue -Object $slot -Name 'kind'))
            LinuxFxVersion     = ''
            WindowsFxVersion   = ''
            NodeVersion        = ''
            NodeAppSetting     = ''
            ConfiguredRuntime  = ''
            NodeMajorVersion   = ''
            DetectionSource    = 'CLI'
            InMicrosoftNotice  = $ParentRow.InMicrosoftNotice
            ResourceId         = [string](Get-NotePropertyValue -Object $slot -Name 'id')
            DefaultHostName    = [string](Get-NotePropertyValue -Object $slot -Name 'defaultHostName')
            Tags               = $ParentRow.Tags
            ObservedAtUtc      = $ObservedAtUtc
            Notes              = 'Discovered via az webapp deployment slot list'
            IsSlot             = $true
            Type               = 'microsoft.web/sites/slots'
        }
        $childRows.Add($child) | Out-Null
    }

    return $childRows
}

# --------------------------------------------------------------------------
# Stage 0 - context check (CLAUDE.md §3.2: never guess tenant or subscription)
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

$signedInAs = if ((Get-NotePropertyValue -Object $account -Name 'user')) { $account.user.name } else { '<non-user principal>' }
$observedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
Write-Host ("Tenant       : {0}" -f $account.tenantId)
Write-Host ("Signed in as : {0}" -f $signedInAs)
Write-Host ("Observed at  : {0}" -f $observedAtUtc)
Write-Host ("Advisory     : {0} (Node 22 LTS EOS 2027-04-30)" -f $script:AdvisoryTrackingId)

if ($ExpectedTenantId -and $account.tenantId -ne $ExpectedTenantId) {
    Write-Error ("Tenant mismatch. Expected '{0}' but the active context is '{1}'. Stopping before any query." -f $ExpectedTenantId, $account.tenantId)
    exit 3
}

$allSubs = Invoke-AzJson -Arguments @('account', 'list', '--all')
$enabledSubs = @($allSubs | Where-Object { $_.state -eq 'Enabled' })
$script:SubNameById = @{}
foreach ($sub in $enabledSubs) { $script:SubNameById[$sub.id] = [string]$sub.name }

if ($SubscriptionId) {
    $targetSubs = @($SubscriptionId)
    Write-Host ("Scope        : {0} explicitly supplied subscription(s)" -f $targetSubs.Count)
}
else {
    $targetSubs = @($enabledSubs | Select-Object -ExpandProperty id)
    Write-Host ("Scope        : {0} enabled subscription(s) visible to this identity" -f $targetSubs.Count)
    Add-CoverageWarning ("Tenant sweep covers only subscriptions this identity can read ({0} found). An empty result does not prove no Node 22 app exists elsewhere." -f $targetSubs.Count)
}

if ($targetSubs.Count -eq 0) {
    Write-Error 'No in-scope subscriptions resolved.'
    exit 3
}

# --------------------------------------------------------------------------
# Stage 1 - Resource Graph sweep
# --------------------------------------------------------------------------
Write-Phase 'Stage 1: Resource Graph candidate sweep'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$kqlPath = Join-Path $repoRoot 'queries\resource-graph\app-service-node22-candidates.kql'
if (-not (Test-Path -Path $kqlPath)) {
    Write-Error "KQL file not found: $kqlPath"
    exit 3
}

$candidateQuery = Get-KqlFromFile -Path $kqlPath
$allSitesQuery = @'
resources
| where type =~ 'microsoft.web/sites' or type =~ 'microsoft.web/sites/slots'
| project
    name,
    subscriptionId,
    resourceGroup,
    location,
    kind,
    type,
    linuxFxVersion = tostring(properties.siteConfig.linuxFxVersion),
    windowsFxVersion = tostring(properties.siteConfig.windowsFxVersion),
    nodeVersion = tostring(properties.siteConfig.nodeVersion),
    siteState = tostring(properties.state),
    defaultHostName = tostring(properties.defaultHostName),
    tags,
    id
'@

$argCandidates = Invoke-ResourceGraphQuery -Query $candidateQuery -SubscriptionIds $targetSubs
Write-Host ("Stage 1 Node 22 ARG candidates: {0}" -f $argCandidates.Count)

$allSites = Invoke-ResourceGraphQuery -Query $allSitesQuery -SubscriptionIds $targetSubs
Write-Host ("Stage 1 all App Service sites/slots: {0}" -f $allSites.Count)
if ($allSites.Count -eq 0) {
    Add-CoverageWarning 'Resource Graph returned zero Microsoft.Web/sites rows. Missing Reader access is more likely than an empty estate.'
}

$review = [System.Collections.Generic.List[object]]::new()
$seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($site in $argCandidates) {
    $row = ConvertTo-InventoryRow -Site $site -SubscriptionName (Get-SubscriptionDisplayName -Id ([string]$site.subscriptionId))
    if (-not (Test-ShouldIncludeRow -Row $row)) { continue }
    $row.DetectionSource = 'ARG'
    if ($seenIds.Add($row.ResourceId)) { $review.Add($row) | Out-Null }
}

foreach ($site in $allSites) {
    $row = ConvertTo-InventoryRow -Site $site -SubscriptionName (Get-SubscriptionDisplayName -Id ([string]$site.subscriptionId))
    if (-not (Test-ShouldIncludeRow -Row $row)) { continue }

    $argClass = Get-RuntimeClassification -LinuxFxVersion $row.LinuxFxVersion -WindowsFxVersion $row.WindowsFxVersion -NodeVersion $row.NodeVersion -NodeAppSetting $row.NodeAppSetting
    $needsWindowsSweep = ($row.Platform -eq 'Windows' -and $argClass.NodeMajor -ne 'Container')
    $needsLinuxNodeCheck = ($argClass.NodeMajor -eq '22' -or $row.LinuxFxVersion -match '(?i)NODE\|')
    $onNotice = $row.InMicrosoftNotice

    if (-not ($needsWindowsSweep -or $needsLinuxNodeCheck -or $onNotice)) { continue }
    if ($seenIds.Add($row.ResourceId)) {
        $row.DetectionSource = if ($argClass.NodeMajor -eq '22') { 'ARG' } else { 'ARG' }
        $review.Add($row) | Out-Null
    }
}

Write-Host ("Review set (ARG candidates + Windows/Node/notice apps): {0}" -f $review.Count)

# --------------------------------------------------------------------------
# Stage 2 - authoritative control-plane verification
# --------------------------------------------------------------------------
Write-Phase 'Stage 2: control-plane verification'

$results = [System.Collections.Generic.List[object]]::new()
$slotParentsChecked = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$index = 0

function Add-VerifiedRow {
    param($Row, $Verification)

    $Row.ObservedAtUtc = $observedAtUtc

    if ($SkipCliVerification) {
        $class = Get-RuntimeClassification -LinuxFxVersion $Row.LinuxFxVersion -WindowsFxVersion $Row.WindowsFxVersion -NodeVersion $Row.NodeVersion -NodeAppSetting $Row.NodeAppSetting
        $Row.ConfiguredRuntime = $class.ConfiguredRuntime
        $Row.NodeMajorVersion = $class.NodeMajor
        $Row.DetectionSource = 'ARG'
        $Row.Notes = 'Stage 2 skipped - ARG only'
        $results.Add($Row) | Out-Null
        return
    }

    if (-not $Verification.Ok) {
        $class = Get-RuntimeClassification -LinuxFxVersion $Row.LinuxFxVersion -WindowsFxVersion $Row.WindowsFxVersion -NodeVersion $Row.NodeVersion -NodeAppSetting $Row.NodeAppSetting
        $Row.ConfiguredRuntime = $class.ConfiguredRuntime
        $Row.NodeMajorVersion = $class.NodeMajor
        $Row.Notes = "Control-plane verification failed: $($Verification.Error)"
        Add-CoverageWarning ("Verification failed for '{0}' slot '{1}' in {2}." -f $Row.AppName, $Row.SlotName, $Row.SubscriptionId)
        $results.Add($Row) | Out-Null
        return
    }

    $cfg = $Verification.Config
    $Row.LinuxFxVersion = [string](Get-NotePropertyValue -Object $cfg -Name 'linuxFxVersion')
    $Row.WindowsFxVersion = [string](Get-NotePropertyValue -Object $cfg -Name 'windowsFxVersion')
    $Row.NodeVersion = [string](Get-NotePropertyValue -Object $cfg -Name 'nodeVersion')
    $Row.NodeAppSetting = [string]$Verification.Setting
    if ($Verification.Show) {
        $kind = [string](Get-NotePropertyValue -Object $Verification.Show -Name 'kind')
        if ($kind) {
            $Row.Kind = $kind
            $Row.Platform = Get-PlatformFromKind -Kind $kind
        }
        $state = [string](Get-NotePropertyValue -Object $Verification.Show -Name 'state')
        if ($state) { $Row.State = $state }
        $hostName = [string](Get-NotePropertyValue -Object $Verification.Show -Name 'defaultHostName')
        if ($hostName) { $Row.DefaultHostName = $hostName }
    }

    $class = Get-RuntimeClassification -LinuxFxVersion $Row.LinuxFxVersion -WindowsFxVersion $Row.WindowsFxVersion -NodeVersion $Row.NodeVersion -NodeAppSetting $Row.NodeAppSetting
    $Row.ConfiguredRuntime = $class.ConfiguredRuntime
    $Row.NodeMajorVersion = $class.NodeMajor
    $Row.DetectionSource = if ($Row.DetectionSource -eq 'CLI') { 'CLI' } else { 'Both' }
    if ([string]::IsNullOrWhiteSpace($Row.ConfiguredRuntime) -and $Row.Platform -eq 'Windows') {
        $Row.NodeMajorVersion = 'Unknown'
        $Row.Notes = 'Windows app has no WEBSITE_NODE_DEFAULT_VERSION / nodeVersion; inherited platform default is unverified'
    }
    $results.Add($Row) | Out-Null
}

foreach ($row in $review) {
    $index++
    Write-Verbose ("[{0}/{1}] Verifying {2}/{3} ({4})" -f $index, $review.Count, $row.AppName, $row.SlotName, $row.SubscriptionId)

    $verification = $null
    if (-not $SkipCliVerification) {
        $verification = Invoke-SiteConfigVerification -Row $row
    }
    Add-VerifiedRow -Row $row -Verification $verification

    if ($IncludeSlots -and -not $row.IsSlot -and -not $SkipCliVerification) {
        $parentKey = '{0}|{1}|{2}' -f $row.SubscriptionId, $row.ResourceGroup, $row.AppName
        if ($slotParentsChecked.Add($parentKey)) {
            $children = Get-SlotChildRows -ParentRow $row -ObservedAtUtc $observedAtUtc
            foreach ($child in $children) {
                if ($seenIds.Add($child.ResourceId)) {
                    $childVerification = Invoke-SiteConfigVerification -Row $child
                    Add-VerifiedRow -Row $child -Verification $childVerification
                }
            }
        }
    }
}

# Seed-list completeness: notice apps missing from ARG still get a CLI lookup
# when they exist in the all-sites set; if they do not, record a mismatch row.
$foundNotice = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($row in $results) {
    if ($row.InMicrosoftNotice) { $foundNotice.Add($row.AppName) | Out-Null }
}
foreach ($noticeName in $script:NoticeAppNames) {
    if ($foundNotice.Contains($noticeName)) { continue }
    Add-CoverageWarning ("Microsoft notice app '{0}' was not found in ARG results for the swept subscriptions." -f $noticeName)
    $results.Add([pscustomobject]@{
        SubscriptionName   = Get-SubscriptionDisplayName -Id $script:NoticeSubscriptionId
        SubscriptionId     = $script:NoticeSubscriptionId
        ResourceGroup      = ''
        AppName            = $noticeName
        SlotName           = 'production'
        Kind               = ''
        Location           = ''
        State              = ''
        Platform           = ''
        LinuxFxVersion     = ''
        WindowsFxVersion   = ''
        NodeVersion        = ''
        NodeAppSetting     = ''
        ConfiguredRuntime  = ''
        NodeMajorVersion   = 'Unknown'
        DetectionSource    = 'Notice'
        InMicrosoftNotice  = $true
        ResourceId         = ''
        DefaultHostName    = ''
        Tags               = ''
        ObservedAtUtc      = $observedAtUtc
        Notes              = 'Named in Microsoft notice but not returned by Resource Graph'
        IsSlot             = $false
        Type               = ''
    }) | Out-Null
}

# --------------------------------------------------------------------------
# Optional advisory lookup (read-only; failure is a warning, not a stop)
# --------------------------------------------------------------------------
Write-Phase 'Stage 3: advisory reconciliation'

$advisoryHits = 0
if ($targetSubs -contains $script:NoticeSubscriptionId) {
    $healthUrl = 'https://management.azure.com/subscriptions/' + $script:NoticeSubscriptionId +
        '/providers/Microsoft.ResourceHealth/events?api-version=2022-10-01'
    $health = Invoke-AzJson -TolerateFailure -Arguments @('rest', '--method', 'get', '--url', $healthUrl)
    $events = @(Get-NotePropertyValue -Object $health -Name 'value')
    foreach ($evt in $events) {
        $blob = ($evt | ConvertTo-Json -Depth 6 -Compress)
        if ($blob -match [regex]::Escape($script:AdvisoryTrackingId)) { $advisoryHits++ }
    }
    if ($advisoryHits -gt 0) {
        Write-Host ("Service Health events mentioning {0}: {1}" -f $script:AdvisoryTrackingId, $advisoryHits)
    }
    else {
        Add-CoverageWarning ("Did not find tracking id {0} in Resource Health events for {1}. Confirm in Portal > Service Health > Health advisories." -f $script:AdvisoryTrackingId, $script:NoticeSubscriptionId)
    }
}

# --------------------------------------------------------------------------
# Stage 4 - report
# --------------------------------------------------------------------------
Write-Phase 'Stage 4: report'

if (-not (Test-Path -Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$stamp    = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$csvPath  = Join-Path $OutputDirectory "$stamp-app-service-node22-inventory.csv"
$reviewCsvPath = Join-Path $OutputDirectory "$stamp-app-service-node22-review-set.csv"
$jsonPath = Join-Path $OutputDirectory "$stamp-app-service-node22-inventory.json"
$mdPath   = Join-Path $OutputDirectory "$stamp-app-service-node22-summary.md"

$node22Rows = @($results | Where-Object { $_.NodeMajorVersion -eq '22' })
$noticeMismatch = @($results | Where-Object { $_.InMicrosoftNotice -and $_.NodeMajorVersion -ne '22' })
$node22NotInNotice = @($node22Rows | Where-Object { -not $_.InMicrosoftNotice -and -not $_.IsSlot })
$unknownRows = @($results | Where-Object { $_.NodeMajorVersion -eq 'Unknown' })

$exportRows = @($node22Rows | Select-Object SubscriptionName, SubscriptionId, ResourceGroup, AppName, SlotName,
    Kind, Location, State, Platform, ConfiguredRuntime, NodeMajorVersion, DetectionSource,
    InMicrosoftNotice, ResourceId, DefaultHostName, Tags, ObservedAtUtc, Notes)

$reviewExportRows = @($results | Select-Object SubscriptionName, SubscriptionId, ResourceGroup, AppName, SlotName,
    Kind, Location, State, Platform, ConfiguredRuntime, NodeMajorVersion, DetectionSource,
    InMicrosoftNotice, ResourceId, DefaultHostName, Tags, ObservedAtUtc, Notes)

$exportRows | Sort-Object -Property SubscriptionName, AppName, SlotName |
    Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8

$reviewExportRows | Sort-Object -Property NodeMajorVersion, SubscriptionName, AppName, SlotName |
    Export-Csv -Path $reviewCsvPath -NoTypeInformation -Encoding utf8

[pscustomobject]@{
    GeneratedUtc           = $observedAtUtc
    TenantId               = $account.tenantId
    SignedInAs             = $signedInAs
    AdvisoryTrackingId     = $script:AdvisoryTrackingId
    SubscriptionsSwept     = $targetSubs.Count
    IncludeSlots           = $IncludeSlots
    IncludeFunctionApps    = $IncludeFunctionApps
    Stage2Performed        = (-not $SkipCliVerification.IsPresent)
    ArgNode22Candidates    = $argCandidates.Count
    ArgAllSites            = $allSites.Count
    ReviewSetCount         = $review.Count
    Node22Count            = $node22Rows.Count
    ReviewSetExportedCount = $reviewExportRows.Count
    NoticeMismatchCount    = $noticeMismatch.Count
    AdvisoryEventHits      = $advisoryHits
    Warnings               = @($script:Warnings)
    Rows                   = $results
} | ConvertTo-Json -Depth 20 | Set-Content -Path $jsonPath -Encoding utf8

$bySub = $node22Rows | Group-Object SubscriptionName | Sort-Object Name
$summaryLines = [System.Collections.Generic.List[string]]::new()
$summaryLines.Add('# App Service Node.js 22 inventory') | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add("- Observed at (UTC): $observedAtUtc") | Out-Null
$summaryLines.Add("- Tenant: $($account.tenantId)") | Out-Null
$summaryLines.Add("- Signed in as: $signedInAs") | Out-Null
$summaryLines.Add("- Subscriptions swept: $($targetSubs.Count)") | Out-Null
$summaryLines.Add("- Advisory tracking id: $($script:AdvisoryTrackingId)") | Out-Null
$summaryLines.Add("- Stage 2 CLI verification: $(-not $SkipCliVerification.IsPresent)") | Out-Null
$summaryLines.Add("- ARG Node 22 candidates: $($argCandidates.Count)") | Out-Null
$summaryLines.Add("- ARG all sites/slots: $($allSites.Count)") | Out-Null
$summaryLines.Add("- Confirmed or classified Node major 22: $($node22Rows.Count)") | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add('This inventory reports **configured** runtime (linuxFxVersion / WEBSITE_NODE_DEFAULT_VERSION), not live `node -v`.') | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add('## Node 22 by subscription') | Out-Null
$summaryLines.Add('') | Out-Null
if ($bySub.Count -eq 0) {
    $summaryLines.Add('_None classified as Node 22._') | Out-Null
}
else {
    $summaryLines.Add('| Subscription | Node 22 rows |') | Out-Null
    $summaryLines.Add('|---|---|') | Out-Null
    foreach ($g in $bySub) {
        $summaryLines.Add(('| {0} | {1} |' -f ($g.Name, $g.Count))) | Out-Null
    }
}
$summaryLines.Add('') | Out-Null
$summaryLines.Add('## Microsoft notice seed list') | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add('| App name | Found | Node major | Notes |') | Out-Null
$summaryLines.Add('|---|---|---|---|') | Out-Null
foreach ($noticeName in $script:NoticeAppNames) {
    $match = @($results | Where-Object { $_.AppName -eq $noticeName -and $_.SlotName -eq 'production' } | Select-Object -First 1)
    if ($match.Count -eq 0) {
        $summaryLines.Add(("| `{0}` | No | | Missing from sweep |" -f $noticeName)) | Out-Null
    }
    else {
        $m = $match[0]
        $summaryLines.Add(("| `{0}` | Yes | {1} | {2} |" -f $noticeName, $m.NodeMajorVersion, $m.Notes)) | Out-Null
    }
}
$summaryLines.Add('') | Out-Null
$summaryLines.Add('## Notice mismatches (in email, not Node 22 after verification)') | Out-Null
$summaryLines.Add('') | Out-Null
if ($noticeMismatch.Count -eq 0) {
    $summaryLines.Add('_None._') | Out-Null
}
else {
    foreach ($m in $noticeMismatch) {
        $summaryLines.Add(('- `{0}` / {1}: major={2} runtime=`{3}` notes={4}' -f $m.AppName, $m.SlotName, $m.NodeMajorVersion, $m.ConfiguredRuntime, $m.Notes)) | Out-Null
    }
}
$summaryLines.Add('') | Out-Null
$summaryLines.Add('## Windows apps with unverified Node runtime (manual review)') | Out-Null
$summaryLines.Add('') | Out-Null
if ($unknownRows.Count -eq 0) {
    $summaryLines.Add('_None._') | Out-Null
}
else {
    foreach ($m in ($unknownRows | Sort-Object SubscriptionName, AppName)) {
        $summaryLines.Add(('- `{0}` ({1}) — {2}' -f $m.AppName, $m.SubscriptionName, $m.Notes)) | Out-Null
    }
}
$summaryLines.Add('') | Out-Null
$summaryLines.Add('## Node 22 apps not named in the Microsoft email') | Out-Null
$summaryLines.Add('') | Out-Null
if ($node22NotInNotice.Count -eq 0) {
    $summaryLines.Add('_None._') | Out-Null
}
else {
    foreach ($m in ($node22NotInNotice | Sort-Object SubscriptionName, AppName)) {
        $summaryLines.Add(('- `{0}` ({1} / {2}) runtime=`{3}`' -f $m.AppName, $m.SubscriptionName, $m.ResourceGroup, $m.ConfiguredRuntime)) | Out-Null
    }
}
$summaryLines.Add('') | Out-Null
$summaryLines.Add('## Coverage warnings') | Out-Null
$summaryLines.Add('') | Out-Null
if ($script:Warnings.Count -eq 0) {
    $summaryLines.Add('_None._') | Out-Null
}
else {
    foreach ($w in $script:Warnings) { $summaryLines.Add("- $w") | Out-Null }
}
$summaryLines.Add('') | Out-Null
$summaryLines.Add('## Files') | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add("- CSV (Node 22 only): $csvPath") | Out-Null
$summaryLines.Add("- CSV (full review set): $reviewCsvPath") | Out-Null
$summaryLines.Add("- JSON: $jsonPath") | Out-Null
$summaryLines | Set-Content -Path $mdPath -Encoding utf8

Write-Host ''
$node22Rows | Sort-Object SubscriptionName, AppName, SlotName |
    Format-Table SubscriptionName, ResourceGroup, AppName, SlotName, Platform, ConfiguredRuntime, NodeMajorVersion, InMicrosoftNotice -AutoSize

Write-Host ("`nARG Node 22 candidates     : {0}" -f $argCandidates.Count)
Write-Host ("CLI/ARG rows classified 22 : {0}" -f $node22Rows.Count)
Write-Host ("Notice mismatches          : {0}" -f $noticeMismatch.Count)
Write-Host ("CSV (Node 22 only)     : {0}" -f $csvPath)
Write-Host ("CSV (review set)       : {0}" -f $reviewCsvPath)
Write-Host ("JSON : {0}" -f $jsonPath)
Write-Host ("MD   : {0}" -f $mdPath)

if ($script:Warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    $script:Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

Write-Host "`nThis report is evidence only. Changing linuxFxVersion or WEBSITE_NODE_DEFAULT_VERSION" -ForegroundColor Yellow
Write-Host "is a runtime change and requires a separate change plan (CLAUDE.md §5.1)." -ForegroundColor Yellow

if ($script:Warnings.Count -gt 0) { exit 4 }
if ($node22Rows.Count -eq 0)      { exit 2 }
exit 0

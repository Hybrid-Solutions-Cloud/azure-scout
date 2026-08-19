#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Orchestrates one Azure Scout invocation across several directly accessible tenants.

.DESCRIPTION
    AB#7105. Keeps the existing collection pipeline single-tenant and invokes it once per target
    tenant beneath one umbrella run folder. Each tenant has isolated cache, logs, evidence, and
    reports. A root self-contained overview records the requested scope, per-tenant outcome, and
    relative links to completed React reports. Azure Lighthouse is deliberately not involved.

.NOTES
    Author: Kristopher Turner
    Contact: kris@hybridsolutions.cloud
    Version: 1.0.0
#>

function New-AZSCRunResult {
    [CmdletBinding()]
    param(
        [string]$TenantId,
        [string]$OutputPath,
        [string]$ReactFile,
        [string]$EvidenceFile,
        [string]$JsonFile,
        [int]$SubscriptionCount,
        [int]$ResourceCount,
        [string]$Duration,
        [string]$Status = 'Completed'
    )

    return [pscustomobject]@{
        PSTypeName        = 'AzureScout.RunResult'
        Status            = $Status
        TenantId          = $TenantId
        OutputPath        = $OutputPath
        ReactFile         = $ReactFile
        EvidenceFile      = $EvidenceFile
        JsonFile          = $JsonFile
        SubscriptionCount = $SubscriptionCount
        ResourceCount     = $ResourceCount
        Duration          = $Duration
    }
}

function ConvertTo-AZSCTenantFolderName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$TenantName,
        [Parameter(Mandatory)]
        [string]$TenantId
    )

    $displayName = if ([string]::IsNullOrWhiteSpace($TenantName)) { 'tenant' } else { $TenantName }
    $safeName = ConvertTo-AZSCSafeRunName -Name $displayName
    $safeId = ConvertTo-AZSCSafeRunName -Name $TenantId
    $idToken = if ($safeId.Length -gt 8) { $safeId.Substring(0, 8) } else { $safeId }
    return '{0}_{1}' -f $safeName, $idToken
}

function Resolve-AZSCMultiTenantTarget {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [string[]]$RequestedTenantId,
        [switch]$AllAccessibleTenants
    )

    $accessibleTenants = @(Get-AZSCAccessibleTenant)
    $accessibleById = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($tenant in $accessibleTenants) {
        $id = [string]$tenant.Id
        if (-not [string]::IsNullOrWhiteSpace($id) -and -not $accessibleById.ContainsKey($id)) {
            $accessibleById[$id] = $tenant
        }
    }

    $targetIds = if ($AllAccessibleTenants.IsPresent) {
        @($accessibleTenants | ForEach-Object { [string]$_.Id })
    }
    else {
        @($RequestedTenantId)
    }
    $targetIds = @($targetIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($targetIds.Count -eq 0) {
        if ($AllAccessibleTenants.IsPresent) {
            throw 'No accessible tenants were discovered for the signed-in account.'
        }
        throw 'At least two tenant IDs or -AllAccessibleTenants is required for a multi-tenant run.'
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $targets = foreach ($requestedId in $targetIds) {
        $id = ([string]$requestedId).Trim()
        if (-not $seen.Add($id)) { continue }

        $knownTenant = if ($accessibleById.ContainsKey($id)) { $accessibleById[$id] } else { $null }
        $name = if ($knownTenant -and -not [string]::IsNullOrWhiteSpace([string]$knownTenant.Name)) {
            [string]$knownTenant.Name
        }
        else {
            'Tenant {0}' -f $(if ($id.Length -gt 8) { $id.Substring(0, 8) } else { $id })
        }
        [pscustomobject]@{
            Id         = $id
            Name       = $name
            FolderName = ConvertTo-AZSCTenantFolderName -TenantName $name -TenantId $id
            Discovered = [bool]$knownTenant
        }
    }
    return @($targets)
}

function Get-AZSCMultiTenantSelectionSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$InvocationParameters,
        [switch]$AllAccessibleTenants
    )

    $runType = if ($InvocationParameters.ContainsKey('InventoryAndAssessment') -and
        [bool]$InvocationParameters['InventoryAndAssessment']) { 'Inventory and assessment' }
    elseif ($InvocationParameters.ContainsKey('Assessment') -and @($InvocationParameters['Assessment']).Count -gt 0) { 'Assessment' }
    else { 'Inventory' }

    $enabled = foreach ($name in @(
        'SecurityCenter', 'IncludeCosts', 'QuotaUsage', 'CheckResourceProviders', 'IncludeDevOps',
        'IncludeOkta', 'IncludeOnPremisesIdentity', 'IncludeTags', 'Heavy'
    )) {
        if ($InvocationParameters.ContainsKey($name) -and [bool]$InvocationParameters[$name]) { $name }
    }
    $skipped = foreach ($name in @('SkipAdvisory', 'SkipPolicy', 'SkipAPIs', 'SkipVMDetails', 'SkipDiagram')) {
        if ($InvocationParameters.ContainsKey($name) -and [bool]$InvocationParameters[$name]) { $name }
    }

    return [ordered]@{
        TenantSelection = if ($AllAccessibleTenants.IsPresent) { 'Every accessible tenant' } else { 'Selected tenant IDs' }
        RunType          = $runType
        Scope            = if ($InvocationParameters.ContainsKey('Scope')) { [string]$InvocationParameters['Scope'] } else { 'ArmOnly' }
        Categories       = if ($InvocationParameters.ContainsKey('Category')) { @($InvocationParameters['Category']) } else { @('All') }
        Assessments      = if ($InvocationParameters.ContainsKey('Assessment')) { @($InvocationParameters['Assessment']) } else { @() }
        OutputFormats    = if ($InvocationParameters.ContainsKey('OutputFormat')) { @($InvocationParameters['OutputFormat']) } else { @('All') }
        SubscriptionIds  = if ($InvocationParameters.ContainsKey('SubscriptionID')) { @($InvocationParameters['SubscriptionID']) } else { @() }
        ManagementGroups = if ($InvocationParameters.ContainsKey('ManagementGroup')) { @($InvocationParameters['ManagementGroup']) } else { @() }
        EnabledOptions   = @($enabled)
        SkippedOptions   = @($skipped)
    }
}

function Update-AZSCMultiTenantSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Summary)

    $Summary.Counts.Total = @($Summary.Tenants).Count
    foreach ($state in @('Pending', 'Running', 'Completed', 'Failed')) {
        $Summary.Counts[$state] = @($Summary.Tenants | Where-Object { $_.Status -eq $state }).Count
    }
    $Summary.Counts.Resources = [int64](
        @($Summary.Tenants | Measure-Object -Property ResourceCount -Sum).Sum
    )
    $Summary.Counts.Subscriptions = [int64](
        @($Summary.Tenants | Measure-Object -Property SubscriptionCount -Sum).Sum
    )
}

function Write-AZSCAtomicTextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop
    }
    $temporaryPath = Join-Path $parent ('.{0}.{1}.tmp' -f (Split-Path $Path -Leaf), [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $Content, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Export-AZSCMultiTenantOverview {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Summary,
        [Parameter(Mandatory)][string]$OutputPath
    )

    Update-AZSCMultiTenantSummary -Summary $Summary
    $json = $Summary | ConvertTo-Json -Depth 20
    Write-AZSCAtomicTextFile -Path (Join-Path $OutputPath 'run-summary.json') -Content $json

    $safeJson = $json -replace '</', '<\/'
    $templatePath = Join-Path $PSScriptRoot 'report/templates/report-multi-tenant.html.template'
    $template = Get-Content -LiteralPath $templatePath -Raw -ErrorAction Stop
    $html = $template.Replace('/*__SCOUT_MULTI_TENANT_DATA__*/', $safeJson)
    $reportPath = Join-Path $OutputPath 'report-react.html'
    Write-AZSCAtomicTextFile -Path $reportPath -Content $html
    Write-AZSCAtomicTextFile -Path (Join-Path $OutputPath 'index.html') -Content $html
    return $reportPath
}

function Invoke-AZSCMultiTenantRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$InvocationParameters,
        [string[]]$RequestedTenantId,
        [switch]$AllAccessibleTenants,
        [Parameter(DontShow)]
        [scriptblock]$TenantRunner
    )

    if ($InvocationParameters.ContainsKey('FromCollect') -and $InvocationParameters['FromCollect']) {
        throw '-FromCollect is an offline single-run operation and cannot be combined with a multi-tenant scan.'
    }
    if ($InvocationParameters.ContainsKey('PermissionAudit') -and [bool]$InvocationParameters['PermissionAudit']) {
        throw '-PermissionAudit does not produce tenant React reports and cannot be combined with a multi-tenant scan.'
    }
    if ($InvocationParameters.ContainsKey('Automation') -and [bool]$InvocationParameters['Automation']) {
        throw 'Multi-tenant scanning currently supports directly signed-in user accounts, not Automation managed identities.'
    }
    if ($InvocationParameters.ContainsKey('StorageAccount') -and $InvocationParameters['StorageAccount']) {
        throw 'Multi-tenant storage upload is not yet supported because tenant artifacts require isolated blob prefixes.'
    }
    if ($InvocationParameters.ContainsKey('Force') -and [bool]$InvocationParameters['Force']) {
        throw 'Use -RunName for a named multi-tenant umbrella folder; -Force is not supported because it removes run isolation.'
    }
    if ($AllAccessibleTenants.IsPresent -and $InvocationParameters.ContainsKey('AppId') -and $InvocationParameters['AppId']) {
        throw '-AllAccessibleTenants requires a signed-in user account. For a multi-tenant app registration, pass the consented tenant IDs explicitly.'
    }

    $initialContext = Get-AzContext -ErrorAction SilentlyContinue
    $summary = $null
    try {
        $loginParameters = @{
            AzureEnvironment = if ($InvocationParameters.ContainsKey('AzureEnvironment')) { $InvocationParameters['AzureEnvironment'] } else { 'AzureCloud' }
        }
        foreach ($name in @('DeviceLogin', 'AppId', 'Secret', 'CertificatePath', 'CertificatePassword')) {
            if ($InvocationParameters.ContainsKey($name)) { $loginParameters[$name] = $InvocationParameters[$name] }
        }
        if (-not $AllAccessibleTenants.IsPresent -and @($RequestedTenantId).Count -gt 0) {
            $loginParameters.TenantID = [string]$RequestedTenantId[0]
        }
        $null = Connect-AZSCLoginSession @loginParameters

        $targets = @(Resolve-AZSCMultiTenantTarget -RequestedTenantId $RequestedTenantId `
            -AllAccessibleTenants:$AllAccessibleTenants)
        $reportDir = if ($InvocationParameters.ContainsKey('ReportDir')) { [string]$InvocationParameters['ReportDir'] } else { $null }
        $runName = if ($InvocationParameters.ContainsKey('RunName')) { [string]$InvocationParameters['RunName'] } else { $null }
        $layout = Set-AZSCReportPath -ReportDir $reportDir -RunName $runName -ScopeId 'multi-tenant'
        $rootPath = [string]$layout.DefaultPath

        $context = Get-AzContext -ErrorAction SilentlyContinue
        $account = if ($context -and $context.Account) { [string]$context.Account.Id } else { 'unknown account' }
        $tenantEntries = [System.Collections.Generic.List[object]]::new()
        foreach ($target in $targets) {
            $tenantEntries.Add([pscustomobject]@{
                TenantId          = $target.Id
                TenantName        = $target.Name
                Folder            = $target.FolderName
                Status            = 'Pending'
                StartedAt         = $null
                CompletedAt       = $null
                Duration          = $null
                SubscriptionCount = 0
                ResourceCount     = 0
                ReactReport       = $null
                Error             = $null
            })
        }
        $summary = [pscustomobject]@{
            Schema      = 'azure-scout/multi-tenant-run/v1'
            RunId       = Split-Path $rootPath -Leaf
            RootPath    = $rootPath
            Account     = $account
            StartedAt   = (Get-Date).ToString('o')
            CompletedAt = $null
            Status      = 'Running'
            Selection   = Get-AZSCMultiTenantSelectionSummary -InvocationParameters $InvocationParameters `
                -AllAccessibleTenants:$AllAccessibleTenants
            Counts      = [ordered]@{
                Total = $targets.Count; Pending = $targets.Count; Running = 0; Completed = 0
                Failed = 0; Subscriptions = 0; Resources = 0
            }
            Tenants     = $tenantEntries
        }
        $overviewPath = Export-AZSCMultiTenantOverview -Summary $summary -OutputPath $rootPath

        if (-not $TenantRunner) {
            $TenantRunner = { param($Arguments) Invoke-AzureScout @Arguments }
        }

        for ($index = 0; $index -lt $targets.Count; $index++) {
            $target = $targets[$index]
            $entry = $tenantEntries[$index]
            $entry.Status = 'Running'
            $entry.StartedAt = (Get-Date).ToString('o')
            $null = Export-AZSCMultiTenantOverview -Summary $summary -OutputPath $rootPath

            $tenantStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $tenantPath = Join-Path $rootPath $target.FolderName
                $null = New-Item -ItemType Directory -Path $tenantPath -ErrorAction Stop
                $childParameters = @{}
                foreach ($key in $InvocationParameters.Keys) { $childParameters[$key] = $InvocationParameters[$key] }
                foreach ($key in @('AllAccessibleTenants', 'RunName', 'ReportDir', 'Force')) { $childParameters.Remove($key) }
                $childParameters.TenantID = @([string]$target.Id)
                $childParameters.ReportDir = $tenantPath
                $childParameters.Force = $true
                $childParameters.NoWizard = $true
                $childParameters.PassThru = $true

                Write-Host ''
                Write-Host ('Tenant {0}/{1}: {2} ({3})' -f ($index + 1), $targets.Count, $target.Name, $target.Id) -ForegroundColor Cyan
                $childOutput = @(& $TenantRunner $childParameters)
                $runResult = @($childOutput | Where-Object { $_ -and $_.PSTypeNames -contains 'AzureScout.RunResult' }) |
                    Select-Object -Last 1

                $reactFile = if ($runResult -and $runResult.ReactFile) { [string]$runResult.ReactFile } else {
                    Get-ChildItem -LiteralPath $tenantPath -Filter 'report-react.html' -File -Recurse -ErrorAction SilentlyContinue |
                        Select-Object -First 1 -ExpandProperty FullName
                }
                $entry.SubscriptionCount = if ($runResult) { [int]$runResult.SubscriptionCount } else { 0 }
                $entry.ResourceCount = if ($runResult) { [int]$runResult.ResourceCount } else { 0 }
                if ($reactFile) {
                    $entry.ReactReport = ([System.IO.Path]::GetRelativePath($rootPath, $reactFile) -replace '\\', '/')
                }
                $entry.Status = 'Completed'
            }
            catch {
                $entry.Status = 'Failed'
                $entry.Error = $_.Exception.Message
                Write-Warning ("Tenant '{0}' failed and the remaining tenants will continue: {1}" -f $target.Name, $_.Exception.Message)
            }
            finally {
                $tenantStopwatch.Stop()
                $entry.Duration = $tenantStopwatch.Elapsed.ToString('dd\:hh\:mm\:ss\.fff')
                $entry.CompletedAt = (Get-Date).ToString('o')
                $null = Export-AZSCMultiTenantOverview -Summary $summary -OutputPath $rootPath
            }
        }

        $summary.CompletedAt = (Get-Date).ToString('o')
        $summary.Status = if (@($tenantEntries | Where-Object Status -eq 'Failed').Count -gt 0) {
            'CompletedWithErrors'
        }
        else { 'Completed' }
        $overviewPath = Export-AZSCMultiTenantOverview -Summary $summary -OutputPath $rootPath

        Write-Host ''
        Write-Host 'Multi-tenant run complete.' -ForegroundColor Green
        Write-Host '  Overview : ' -NoNewline -ForegroundColor DarkGray
        Write-Host $overviewPath -ForegroundColor Cyan

        return [pscustomobject]@{
            PSTypeName = 'AzureScout.MultiTenantRunResult'
            Status     = $summary.Status
            OutputPath = $rootPath
            Overview   = $overviewPath
            Summary    = Join-Path $rootPath 'run-summary.json'
            Tenants    = @($tenantEntries)
        }
    }
    finally {
        if ($initialContext) {
            try { $null = Set-AzContext -Context $initialContext -ErrorAction Stop }
            catch { Write-Warning "The multi-tenant run finished, but the original Azure context could not be restored: $($_.Exception.Message)" }
        }
    }
}

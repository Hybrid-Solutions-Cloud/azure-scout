#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---- AB#6922: which report formats are live, and which are on hold ----------------------------
#
# The React single-page report is the product's deliverable. It hosts inventory and every
# assessment behind one adaptive shell, and it exports to PDF / Word / Markdown / CSV from the
# page itself -- so the standalone document renderers are redundant while they are being rebuilt.
# Maintaining six half-finished renderers in parallel is what let all six ship below deliverable
# quality; concentrating on one is the correction.
#
# LIFTING THE HOLD IS A ONE-LINE EDIT: remove a name from $ScoutHeldRenderers. Nothing else in the
# codebase decides this, and the renderers themselves are untouched and still tested.
#
# Json / JsonEvidence are NOT held: they are machine-readable data, not documents. The corpus
# harness, the drift history and downstream tooling consume them.
$script:ScoutAllRenderers = @(
    'PowerBi', 'Html', 'Pptx', 'Excel', 'Json', 'JsonEvidence', 'React', 'Pdf', 'Word',
    'EChartsDashboard', 'GovernanceReport'
)
$script:ScoutHeldRenderers = @(
    'PowerBi', 'Html', 'Pptx', 'Excel', 'Pdf', 'Word', 'EChartsDashboard', 'GovernanceReport'
)

function Assert-ScoutAssessmentCollectProvenance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Collect,
        [Parameter(Mandatory)] [string[]] $RequiredCategories,
        [string[]] $RequiredIngestors = @()
    )

    $metadataProperty = $Collect.PSObject.Properties['_meta']
    $metadata = if ($metadataProperty) { $metadataProperty.Value } else { $null }
    $categoryProperty = if ($metadata) { $metadata.PSObject.Properties['categories'] } else { $null }
    $collectedCategories = @(
        if ($categoryProperty) {
            $categoryProperty.Value | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        }
    )

    $missingCategories = @()
    if ($collectedCategories.Count -eq 0) {
        $missingCategories = @($RequiredCategories)
    }
    elseif ($RequiredCategories -contains '*') {
        if ($collectedCategories -notcontains '*') { $missingCategories = @('*') }
    }
    elseif ($collectedCategories -notcontains '*') {
        $missingCategories = @($RequiredCategories | Where-Object { $collectedCategories -notcontains $_ })
    }

    $healthProperty = if ($metadata) { $metadata.PSObject.Properties['collectionHealth'] } else { $null }
    $blockingHealth = @(
        if ($healthProperty) {
            foreach ($health in @($healthProperty.Value)) {
                if (
                    $null -eq $health -or
                    -not $health.PSObject.Properties['Status'] -or
                    [string]$health.Status -notin @('Unavailable', 'Failed')
                ) { continue }

                $dataset = if ($health.PSObject.Properties['Dataset']) { [string]$health.Dataset } else { 'Unknown source' }

                # A scoped ARM-child denial is partial evidence loss, not failure of the broad
                # Resources dataset. Invoke-Collect carries explicit availability flags for the
                # affected child datasets; dependent rules close their gate and become
                # NotAssessed while unrelated rules continue to score.
                $source = if ($health.PSObject.Properties['Source']) { [string]$health.Source } else { '' }
                $sourceDataset = if ($health.PSObject.Properties['SourceDataset']) { [string]$health.SourceDataset } else { '' }
                if ($source -eq 'ARM Child' -and -not [string]::IsNullOrWhiteSpace($sourceDataset)) {
                    continue
                }

                if ($dataset -eq 'Advisories' -and $RequiredIngestors -contains 'AdvisorScores') {
                    $health
                    continue
                }

                $collectorProperty = $health.PSObject.Properties['Collectors']
                $collectors = @(
                    if ($collectorProperty) {
                        $collectorProperty.Value | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
                    }
                )
                if ($collectors.Count -eq 0 -or $RequiredCategories -contains '*') {
                    $health
                    continue
                }

                if (@($collectors | Where-Object {
                            $collectorCategory = ([string]$_ -split '/', 2)[0]
                            $RequiredCategories -contains $collectorCategory
                        }).Count -gt 0) {
                    $health
                }
            }
        }
    )

    if ($missingCategories.Count -eq 0 -and $blockingHealth.Count -eq 0) { return }

    $details = [System.Collections.Generic.List[string]]::new()
    if ($missingCategories.Count -gt 0) {
        $details.Add('missing required categories: {0}' -f (@($missingCategories | Sort-Object -Unique) -join ', '))
    }
    if ($blockingHealth.Count -gt 0) {
        $details.Add('unavailable required datasets: {0}' -f (@($blockingHealth | ForEach-Object {
                        if ($_.PSObject.Properties['Dataset']) { [string]$_.Dataset } else { 'Unknown source' }
                    } | Sort-Object -Unique) -join ', '))
    }

    $message = (
        'Invoke-ScoutAssessmentCore: the saved collect cannot safely score the selected assessment ({0}). ' +
        'Create a new collect for this assessment instead of scoring missing evidence.'
    ) -f ($details -join '; ')
    $sourceException = [System.InvalidOperationException]::new($message)
    $sourceException.Data['AzureScoutFailureKind'] = 'AssessmentSourceUnavailable'
    throw $sourceException
}

<#
.SYNOPSIS
    Azure Scout assessment entry point — collect, assess, and report.

.DESCRIPTION
    The assessment-platform orchestrator (distinct from the inventory cmdlet
    Invoke-AzureScout). Orchestrates the three-layer JSON-on-disk contract:
        COLLECT  -> collect.json
        ASSESS   -> findings.json
        REPORT   -> deliverables

    Every layer runs independently from its JSON input, so you can collect once
    and assess later, or re-render reports from an existing findings set without
    re-scanning. Read-only throughout.

.EXAMPLE
    Invoke-AzureScout -Assessment 'CAF: Azure Landing Zone' -OutputFormat React,Json,JsonEvidence

.EXAMPLE
    Invoke-AzureScout -Assessment 'Assess: Management'   # governance/policy/update-manager, scored
    Invoke-AzureScout -Assessment 'Assess: Monitor' -OutputFormat React

.EXAMPLE
    Invoke-AzureScout -Assessment 'CAF: Azure Landing Zone' -CollectOnly
    Invoke-AzureScout -Assessment 'CAF: Azure Landing Zone' -FromCollect ./output/20260720_101500/collect.json -OutputFormat React

.NOTES
    Tracks ADO Epic AB#5023 (Feature AB#5024, Story AB#5026) and Epic AB#5056.

    `-Scope`: a live assessment Collect is ARG/ARM only — there is no Entra/Graph
    collection path there, so 'EntraOnly' throws with a redirect to
    `Invoke-AzureScout -Scope EntraOnly` (the v1 inventory tool) rather than
    silently running a collect that can never gather anything. 'ArmOnly' and
    'All' are accepted and behave identically (both run the ARM collect) —
    kept for forward compatibility rather than removed. The internal InventoryOnly path is an
    exception: it receives already-collected Entra rows and never calls Graph.

    `-ManagementGroupId` now actually scopes the ARG collect (`Search-AzGraph
    -ManagementGroup`, threaded through `Invoke-Collect` and
    `Invoke-ArgQueryPack`), not just the AzGovViz ingest.

    `-Category` (or each assessment's manifest `Collect` list) now actually
    filters which Resource Graph queries `Invoke-Collect` runs, instead of
    always collecting the full ~25-query set.

    AB#405: reports coarse phase-level progress (collect, each ingestor, each
    assessment being scored, each report renderer) through `Write-ScoutProgress`
    (src/Write-ScoutProgress.ps1) when that function is loaded in the calling
    session. Every call is guarded with `Get-Command ... -ErrorAction
    SilentlyContinue`, so this is a soft dependency only -- a session that never
    loaded that helper runs exactly as it did before progress reporting existed.
#>
function Invoke-ScoutAssessmentCore {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'Return shape genuinely varies by branch (void on -Help, Test-ScoutPermission''s result array on -CheckPermissions, a collect.json path string on -CollectOnly, the run-folder path string otherwise) -- a single OutputType would be misleading.')]
    param(
        # AB#6795 -- 'Estate' (Rules = @(), a full-inventory pull with no scoring) was removed
        # from the assessment registry entirely; it is not this platform's job to double as the
        # inventory tool. 'CAF: Azure Landing Zone' is the existing pre-checked default everywhere
        # else (Get-ScoutAvailableAssessment, the wizard), so a bare -CollectOnly / -FromCollect
        # call with no explicit -Assessment now defaults to the same entry an interactive run would.
        [string[]] $Assessment = @('CAF: Azure Landing Zone'),   # one, many, or 'All'
        [ValidateSet('All', 'ArmOnly', 'EntraOnly')]
        [string]   $Scope = 'All',              # EntraOnly throws for live assessments; InventoryOnly reuses in-memory rows
        [string[]] $Category,                    # existing category filter still works
        # AB#6922: the React single-page report is the product's deliverable; every other
        # rendered format is ON HOLD and will be regenerated FROM it (see $script:ScoutHeldRenderers
        # below). The names stay in the ValidateSet so existing scripts still bind rather than
        # failing with a parameter-validation error -- a held format warns and is skipped.
        [ValidateSet('PowerBi', 'Html', 'Pptx', 'Excel', 'Json', 'JsonEvidence', 'React', 'Pdf', 'Word', 'EChartsDashboard', 'All')]
        [string[]] $OutputFormat = @('React'),
        [string]   $OutputPath = './output',
        [switch]   $PermissionAudit,
        [switch]   $CollectOnly,                 # stop after collect.json
        [string]   $FromCollect,                 # skip collect, assess an existing collect.json
        [string]   $ManagementGroupId,
        # AB#5543 — extraction data from an inventory pass that already ran in this invocation.
        # Passed through to Invoke-Collect so a combined run shapes the assessment scalars from
        # rows already in memory instead of querying Azure a second time.
        [object]   $FromInventory,
        # Render React/JsonEvidence from an inventory pass already in memory. This deliberately
        # skips assessment rules and forces Invoke-Collect's no-live-fallback shaping path.
        [switch]   $InventoryOnly,
        # AB#6827 (Feature AB#6749) -- opt-in, same shape as Invoke-AzureScout's own switch. Only
        # threaded to Import-ScoutDevOpsCapability when a chosen assessment's `Ingest` list asks
        # for 'DevOpsCapability'; every other assessment pays nothing for it.
        [switch]   $IncludeDevOps,
        [string[]] $DevOpsOrganization,
        [string]   $DevOpsPat,
        [string]   $TenantID,
        # AB#6930 -- operator-supplied report identity (clientName, engagementName,
        # classification, etc.). Threaded verbatim to every Export-Report call below; unset keys
        # fall back to Export-React's neutral defaults (never a vendor name or URL). See
        # Get-ScoutReportIdentityDefault in src/report/renderers/Export-React.ps1.
        [hashtable] $ReportIdentity = @{},
        # AB#6928 follow-up -- which view lens the React report opens on first (see Export-Report/
        # Export-React's own doc comments). Threaded to every Export-Report call below.
        [ValidateSet('Executive', 'Consultant', 'Data')]
        [string] $DefaultReportMode = 'Consultant',
        [Parameter(DontShow)]
        [string] $ReservedRunPath
    )

    # AB#405: soft dependency -- every call below is skipped entirely when this
    # helper isn't loaded in the session, so the assessment core has zero hard
    # dependency on it.
    $scoutProgressAvailable = [bool](Get-Command Write-ScoutProgress -ErrorAction SilentlyContinue)
    function Write-ScoutAssessmentProgress {
        param([string] $Status, [int] $PercentComplete = -1, [switch] $Completed)
        if (-not $scoutProgressAvailable) { return }
        try {
            $params = @{ Activity = 'Scout Assessment'; Id = 1 }
            if ($Completed) { $params.Completed = $true } else { $params.Status = $Status; $params.PercentComplete = $PercentComplete }
            Write-ScoutProgress @params
        }
        catch { Write-Verbose "Invoke-ScoutAssessmentCore: Write-ScoutProgress failed, continuing without progress UX: $_" }
    }

    function Write-ScoutAssessmentLog {
        param(
            [Parameter(Mandatory)] [string] $Message,
            [ValidateSet('DEBUG', 'VERBOSE')] [string] $Level = 'DEBUG'
        )
        if (Get-Command -Name 'Write-AZSCLog' -ErrorAction SilentlyContinue) {
            Write-AZSCLog -Level $Level -Message $Message
        }
    }

    $manifest = Import-PowerShellDataFile "$PSScriptRoot/../manifests/assessments.psd1"
    if ($InventoryOnly) { $Assessment = @() }
    elseif ($Assessment -contains 'All') { $Assessment = @($manifest.Keys) }
    # AB#6762 -- fifteen entries were renamed with an `Assess: ` prefix to stop the wizard menu
    # colliding with the fifteen identically-named inventory categories. A scripted
    # `-Assessment Compute` predates that rename and must keep working, so the legacy name is
    # mapped here (with a warning naming the new value) before anything indexes the manifest.
    $Assessment = @(Resolve-ScoutAssessmentName -Name $Assessment -Manifest $manifest)
    $requiredCategories = @($Assessment | ForEach-Object { $manifest[$_].Collect } | Select-Object -Unique)
    $requiredIngestors = @($Assessment | ForEach-Object { $manifest[$_].Ingest } | Select-Object -Unique)

    if ($PermissionAudit) {
        return Test-ScoutPermission -Assessment $Assessment -Manifest $manifest
    }

    # Validate paths/scope before allocating a deliverable folder. Permission-only and invalid
    # invocations must not leave empty assessment-report directories behind.
    $fromCollectData = $null
    if ($FromCollect) {
        $fromCollectData = Get-Content -LiteralPath $FromCollect -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 100
        if (-not $InventoryOnly -and -not $CollectOnly) {
            Assert-ScoutAssessmentCollectProvenance -Collect $fromCollectData `
                -RequiredCategories $requiredCategories -RequiredIngestors $requiredIngestors
        }
    }
    elseif ($Scope -eq 'EntraOnly' -and -not ($InventoryOnly -and $FromInventory)) {
        throw "The assessment core collects ARM/Resource Graph data only -- the assessment platform's Collect layer has no Entra ID collection path. Use 'Invoke-AzureScout -Scope EntraOnly' for Entra ID inventory instead."
    }

    # Atomically reserve a run-owned folder. Test-Path followed by New-Item -Force allowed two
    # concurrent callers to select and share the same directory.
    if ($ReservedRunPath) {
        $runPath = [System.IO.Path]::GetFullPath($ReservedRunPath)
        $outputRoot = [System.IO.Path]::GetFullPath($OutputPath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        $runLeaf = Split-Path $runPath -Leaf
        if (-not $runPath.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $runLeaf -notmatch '^assessment-report(?:_\d+)?$') {
            throw "ReservedRunPath must be an assessment-report directory beneath OutputPath."
        }
        if (-not (Test-Path -LiteralPath $runPath -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $runPath -ErrorAction Stop
        }
        elseif (@(Get-ChildItem -LiteralPath $runPath -Force -ErrorAction Stop).Count -gt 0) {
            throw "ReservedRunPath '$runPath' is not empty."
        }
    }
    else {
        $null = New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop
        $runPath = $null
        for ($suffix = 0; $suffix -lt 1000; $suffix++) {
            $leaf = if ($suffix -eq 0) { 'assessment-report' } else { 'assessment-report_{0:d2}' -f $suffix }
            $candidate = Join-Path $OutputPath $leaf
            try {
                $null = New-Item -ItemType Directory -Path $candidate -ErrorAction Stop
                $runPath = [System.IO.Path]::GetFullPath($candidate)
                break
            }
            catch {
                if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw }
            }
        }
        if (-not $runPath) { throw "Could not reserve a unique assessment report directory beneath '$OutputPath'." }
    }
    $runId = Split-Path $runPath -Leaf

    # ---- COLLECT ----
    $collectTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $collectSource = if ($FromCollect) { 'file' } elseif ($FromInventory) { 'inventory-memory' } else { 'live' }
    Write-ScoutAssessmentLog -Level 'VERBOSE' -Message "Assessment collect started: source=$collectSource."
    if ($FromCollect) {
        $collect = $fromCollectData
    }
    else {
        # There is no Entra/Graph collection path in this platform's Collect layer
        # (Invoke-Collect is ARG/ARM only) — 'EntraOnly' could never actually
        # collect anything, so fail fast with the honest redirect instead of
        # silently returning an empty/misleading run. 'ArmOnly' and 'All' are
        # functionally identical today (both just run the ARM collect) and stay
        # accepted for forward compatibility.
        $categories = if ($InventoryOnly) {
            @('*')
        }
        elseif ($CollectOnly -and $Category) {
            @($Category | Select-Object -Unique)
        }
        elseif ($Category) {
            # A public category filter may broaden a scored assessment, but it must never remove
            # evidence required by the selected rule sets. Replacing the manifest categories
            # allowed omitted Networking/Security data to become empty arrays and false Passes.
            @($requiredCategories + $Category | Select-Object -Unique)
        }
        else {
            $requiredCategories
        }
        Write-ScoutAssessmentProgress -Status 'Collecting Azure resource data' -PercentComplete 5
        $collectArgs = @{
            Categories        = $categories
            Scope             = $Scope
            ManagementGroupId = $ManagementGroupId
            TenantID          = $TenantID
        }
        # AB#5543 — reuse the inventory pass when this run already made one.
        if ($FromInventory) { $collectArgs.FromInventory = $FromInventory }
        if ($InventoryOnly) { $collectArgs.OfflineFromInventory = $true }
        # AB#6792 — the policy-compliance sweep is opt-in on Invoke-Collect (it is an extra
        # Azure call type relative to every other assessment's collect) and is switched on only
        # when a chosen assessment actually scores compliance state.
        $wantsCompliance = [bool](@($Assessment | Where-Object { $manifest.ContainsKey($_) -and $manifest[$_] -is [hashtable] -and $manifest[$_].ContainsKey('Compliance') -and $manifest[$_].Compliance }).Count)
        if ($wantsCompliance) { $collectArgs.IncludePolicyCompliance = $true }
        # AB#6803 (Feature AB#6747, Epic AB#6454) -- same opt-in shape as -IncludePolicyCompliance
        # above: `arcSites`/`azureLocalVirtualMachineInstances` cost a materially heavier ARM REST
        # sweep than every other assessment's collect (see Invoke-Collect's -IncludeAzureLocalArm
        # doc comment), so only an assessment that actually scores them pays for it.
        $wantsAzureLocalArm = [bool](@($Assessment | Where-Object { $manifest.ContainsKey($_) -and $manifest[$_] -is [hashtable] -and $manifest[$_].ContainsKey('RequiresAzureLocalArm') -and $manifest[$_].RequiresAzureLocalArm }).Count)
        if ($wantsAzureLocalArm) { $collectArgs.IncludeAzureLocalArm = $true }
        $collect = Invoke-Collect @collectArgs

        # ingest third-party collectors declared by the chosen assessments
        $ingestors = if ($InventoryOnly) { @() } else { $Assessment | ForEach-Object { $manifest[$_].Ingest } | Select-Object -Unique }
        foreach ($i in $ingestors) {
            Write-ScoutAssessmentProgress -Status "Ingesting: $i" -PercentComplete 20
            $ingestTimer = [System.Diagnostics.Stopwatch]::StartNew()
            Write-ScoutAssessmentLog -Message "Assessment ingest started: name=$i."
            switch ($i) {
                # Native governance collector (AB#5041) — ARG + ambient-token ARM
                # REST, no AzGovViz dependency. Default for every assessment that
                # needs management-group / policy / role / budget / lock data.
                'Governance'    { $collect = Import-Governance   -Collect $collect -ManagementGroupId $ManagementGroupId }
                # AzGovViz stays available as an opt-in heavy collector, but nothing
                # in the manifest references it by default any more.
                'AzGovViz'      { $collect = Import-AzGovViz     -Collect $collect -OutputPath $runPath -ManagementGroupId $ManagementGroupId }
                # AB#6774 -- ArgQueryPack is retired. All six of its queries duplicated data
                # Invoke-Collect had just collected, and it overwrote the good copies with
                # worse ones (no divide-by-zero guard on two of them, untyped projections on a
                # third), while a fourth was fetched and never merged at all. Any manifest
                # entry still naming it is ignored rather than erroring, because the value is
                # in a data file a customer may have copied.
                'ArgQueryPack'  { Write-Verbose 'Invoke-ScoutAssessmentCore: the ArgQueryPack ingest is retired (AB#6774) -- Invoke-Collect already produces all six of its datasets. Ignoring.' }
                # AB#6777 -- in a combined run the advisor rows are already in memory from the
                # inventory pass, so hand them over instead of re-fetching per subscription
                # through a slower API.
                'AdvisorScores' {
                    $advisorArgs = @{ Collect = $collect }
                    $advisorInventoryUnavailable = @(
                        if ($FromInventory -and $FromInventory.PSObject.Properties['CollectionHealth']) {
                            $FromInventory.CollectionHealth | Where-Object {
                                $_ -and $_.PSObject.Properties['Dataset'] -and
                                [string]$_.Dataset -eq 'Advisories' -and
                                $_.PSObject.Properties['Status'] -and
                                [string]$_.Status -in @('Unavailable', 'Failed')
                            }
                        }
                    ).Count -gt 0
                    $advisorInventoryNotAssessed = @(
                        if ($FromInventory -and $FromInventory.PSObject.Properties['CollectionHealth']) {
                            $FromInventory.CollectionHealth | Where-Object {
                                $_ -and $_.PSObject.Properties['Dataset'] -and
                                [string]$_.Dataset -eq 'Advisories' -and
                                $_.PSObject.Properties['Status'] -and
                                [string]$_.Status -eq 'NotAssessed'
                            }
                        }
                    ).Count -gt 0
                    if ($advisorInventoryNotAssessed) {
                        $advisorArgs.NotAssessed = $true
                    }
                    elseif ($FromInventory -and $FromInventory.PSObject.Properties['Advisories'] -and -not $advisorInventoryUnavailable) {
                        # Property presence, not row count, proves the inventory query ran. An
                        # empty successful result is a complete answer and must not trigger a
                        # second per-subscription Advisor sweep.
                        $advisorArgs.FromInventory = @($FromInventory.Advisories)
                    }
                    elseif ($advisorInventoryUnavailable) {
                        Write-Warning 'Invoke-ScoutAssessmentCore: the inventory Advisor query was unavailable; attempting the independent per-subscription Advisor API fallback.'
                    }
                    $collect = Import-AdvisorScores @advisorArgs
                }
                # AB#6826 (Feature AB#6749) -- Get-ScoutCostInventory wired into the collect
                # pipeline for the first time (previously built, never called -- see the
                # FinOps question-set enumeration's own "what this means" section). No new
                # switch: cost data is either reachable (Az.CostManagement installed, billing
                # RBAC in place) or it is not, and the ingestor itself computes `available`.
                'CostInventory' {
                    $costArgs = @{ Collect = $collect }
                    if ($FromInventory -and $FromInventory.PSObject.Properties['Costs']) {
                        $costArgs.FromInventory = @($FromInventory.Costs)
                    }
                    $collect = Import-ScoutCostInventory @costArgs
                }
                # AB#6827 (Feature AB#6749) -- same opt-in gate Invoke-AzureScout's own
                # -IncludeDevOps already uses; the DevOps Capability assessment is the first
                # -Assessment-only caller of the five ADO REST collectors, which previously fed
                # only the Excel inventory path.
                'DevOpsCapability' {
                    $devopsArgs = @{ Collect = $collect; IncludeDevOps = $IncludeDevOps.IsPresent }
                    if ($DevOpsOrganization) { $devopsArgs.DevOpsOrganization = $DevOpsOrganization }
                    if ($DevOpsPat) { $devopsArgs.DevOpsPat = $DevOpsPat }
                    if ($TenantID) { $devopsArgs.TenantID = $TenantID }
                    if ($FromInventory -and $FromInventory.PSObject.Properties['Resources']) {
                        $devopsArgs.FromInventory = @($FromInventory.Resources)
                    }
                    $collect = Import-ScoutDevOpsCapability @devopsArgs
                }
            }
            $ingestTimer.Stop()
            Write-ScoutAssessmentLog -Message (
                'Assessment ingest finished: name={0}; elapsed={1}' -f
                    $i, $ingestTimer.Elapsed.ToString('dd\:hh\:mm\:ss\.fff')
            )
        }
        if ($InventoryOnly) {
            $entraRows = if ($FromInventory -and $FromInventory.PSObject.Properties['EntraResources']) {
                @($FromInventory.EntraResources)
            }
            else { @() }
            $collect | Add-Member -NotePropertyName entraResources -NotePropertyValue $entraRows -Force
        }
        $collect | ConvertTo-Json -Depth 100 | Out-File "$runPath/collect.json"
    }
    $collectTimer.Stop()
    Write-ScoutAssessmentLog -Level 'VERBOSE' -Message (
        'Assessment collect finished: source={0}; elapsed={1}' -f
            $collectSource, $collectTimer.Elapsed.ToString('dd\:hh\:mm\:ss\.fff')
    )
    if ($CollectOnly) { return "$runPath/collect.json" }

    # ---- ASSESS ----
    # AB#6879 (Feature AB#6878, clause R-01). Findings are accumulated BOTH into the flat
    # $allFindings -- which the roll-up and every existing caller still read -- and into
    # $findingsByAssessment, keyed by assessment name, so the report phase can render one
    # detailed set PER ASSESSMENT.
    #
    # Phase 0 measured what the single merged document costs: a run selecting LandingZone and
    # Cloud Governance emitted ONE assessment_report.docx, and three unrelated tenants produced
    # documents within 258 bytes of each other. See pmo/research/baseline/.
    $allFindings = @()
    $findingsByAssessment = [ordered]@{}
    $assessmentIndex = 0
    foreach ($name in $Assessment) {
        $assessmentIndex++
        Write-ScoutAssessmentProgress -Status "Assessing: $name" -PercentComplete (35 + [Math]::Min(30, [Math]::Round(($assessmentIndex / [Math]::Max(1, @($Assessment).Count)) * 30)))
        $ruleTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Write-ScoutAssessmentLog -Level 'VERBOSE' -Message "Assessment rules started: assessment=$name."
        $spec = $manifest[$name]
        if (-not $spec.Rules) {
            $ruleTimer.Stop()
            Write-ScoutAssessmentLog -Level 'VERBOSE' -Message (
                'Assessment rules finished: assessment={0}; status=Skipped; findings=0; elapsed={1}' -f
                    $name, $ruleTimer.Elapsed.ToString('dd\:hh\:mm\:ss\.fff')
            )
            continue
        }        # inventory-only assessment
        # AB#6792/#6793/#6794 (Feature AB#6744) -- a `Compliance = $true` entry scores Azure
        # Policy compliance state Scout already collected, not a YAML rule set. It still needs a
        # matching Rules glob (for the AB#6763 menu gate, see compliance.initiative.yaml), so the
        # `-not $spec.Rules` guard above still applies to it; this branch replaces Get-RuleSet /
        # Invoke-Assessment with the compliance engine instead of running them on an empty
        # `rules: []` marker file and reporting a hollow zero-finding "pass".
        if ($spec.ContainsKey('Compliance') -and $spec.Compliance) {
            $findings = Invoke-ScoutComplianceAssessment -Collect $collect -Assessment $name
            $allFindings += $findings
            $findingsByAssessment[$name] = @($findings)
            $ruleTimer.Stop()
            Write-ScoutAssessmentLog -Level 'VERBOSE' -Message (
                'Assessment rules finished: assessment={0}; status=Completed; findings={1}; elapsed={2}' -f
                    $name, @($findings).Count, $ruleTimer.Elapsed.ToString('dd\:hh\:mm\:ss\.fff')
            )
            continue
        }
        $ruleSet   = Get-RuleSet -Patterns $spec.Rules
        # $spec is a Hashtable straight out of assessments.psd1, and most assessment
        # entries don't define a Benchmark key at all (only LandingZone does). Dot-
        # accessing a Hashtable key that is entirely absent throws PropertyNotFound
        # under Set-StrictMode -Version Latest, so check ContainsKey first rather
        # than relying on truthiness of a property access that may never resolve.
        $benchmark = if ($spec.ContainsKey('Benchmark') -and $spec.Benchmark) {
            Get-Content "$PSScriptRoot/assess/benchmarks/$($spec.Benchmark)" -Raw | ConvertFrom-Json -Depth 100
        } else { $null }
        $findings = Invoke-Assessment -Collect $collect -RuleSet $ruleSet -Benchmark $benchmark -Assessment $name
        $allFindings += $findings
        $findingsByAssessment[$name] = @($findings)
        $ruleTimer.Stop()
        Write-ScoutAssessmentLog -Level 'VERBOSE' -Message (
            'Assessment rules finished: assessment={0}; status=Completed; findings={1}; elapsed={2}' -f
                $name, @($findings).Count, $ruleTimer.Elapsed.ToString('dd\:hh\:mm\:ss\.fff')
        )
    }
    $scored = Get-Score -Findings $allFindings
    $scored | ConvertTo-Json -Depth 100 | Out-File "$runPath/findings.json"

    # ---- DRIFT (cross-run) ----
    # Compare this run against the immediately previous run and append it to a
    # findings-history log shared across every run under $OutputPath (keyed by
    # $runId), so the React report's Drift tab can show New/Resolved/Regressed
    # deltas (AB#5053). History lives under $OutputPath (not $runPath) so it
    # persists across dated run folders. Never fatal — a drift failure must not
    # sink an otherwise-good assessment.
    $drift = $null
    if (-not $InventoryOnly) {
        try {
            $drift = Get-ScoutDrift -Findings $scored -HistoryPath (Join-Path $OutputPath '.scout-history') -RunId $runId
        }
        catch {
            Write-Warning "Invoke-ScoutAssessmentCore: drift tracking skipped: $($_.Exception.Message)"
        }
    }

    # ---- REPORT ----
    # AB#6863. GovernanceReport was missing from this list. Export-Report dispatches it and the
    # renderer is fully implemented and tested, but no production caller ever reached it through
    # the All path -- so the only surface carrying the 1-10 CAF Govern domain maturity score never
    # rendered on a default run. A renderer that exists, passes its tests and is unreachable is
    # indistinguishable from one that was never written.
    # AB#6922 -- the React report is the deliverable; every other RENDERED format is on hold.
    #
    # 'All' therefore expands to the React report plus the machine-readable data exports. Json /
    # JsonEvidence are deliberately NOT held: they are data, not documents -- the corpus harness,
    # the drift history and downstream tooling read them, so holding them would break automation
    # that has nothing to do with the reporting rebuild.
    #
    # A held format that is asked for EXPLICITLY warns and is skipped rather than silently
    # producing nothing (a silent skip is how a blank dashboard shipped past a green suite once
    # already). The ValidateSet still accepts the names, so existing scripts bind and get a clear
    # message instead of a parameter-binding failure.
    $requested = if ($OutputFormat -contains 'All') { $script:ScoutAllRenderers } else { $OutputFormat }
    $held = @($requested | Where-Object { $script:ScoutHeldRenderers -contains $_ })
    if ($held.Count -gt 0 -and $OutputFormat -notcontains 'All') {
        Write-Warning ("Invoke-ScoutAssessmentCore: {0} report format(s) are on hold and will not be rendered: {1}. The React report is the supported deliverable (-OutputFormat React); export to PDF/Word/Markdown/CSV from it. See AB#6922." -f $held.Count, ($held -join ', '))
    }
    $reporters = @($requested | Where-Object { $script:ScoutHeldRenderers -notcontains $_ })
    if ($reporters.Count -eq 0) {
        Write-Warning 'Invoke-ScoutAssessmentCore: every requested report format is on hold; rendering the React report instead so the run still produces a deliverable.'
        $reporters = @('React')
    }
    $reporterIndex = 0
    foreach ($r in $reporters) {
        $reporterIndex++
        Write-ScoutAssessmentProgress -Status "Rendering: $r" -PercentComplete (70 + [Math]::Min(29, [Math]::Round(($reporterIndex / [Math]::Max(1, @($reporters).Count)) * 29)))
        $rendererTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Write-ScoutAssessmentLog -Level 'VERBOSE' -Message "Assessment renderer started: renderer=$r."
        # Pipe to Out-Null: some renderers (Export-React) RETURN the path they
        # wrote, and that must not leak into this function's output stream — the
        # only thing the assessment core returns is $runPath. Without this,
        # a run that includes 'React' returns @(reportPath, runPath) and every
        # caller that expects a single run-folder path (incl. Invoke-ScoutPipeline)
        # breaks.
        Export-Report -Renderer $r -Findings $scored -Collect $collect -OutputPath $runPath -Drift $drift -ReportIdentity $ReportIdentity -DefaultReportMode $DefaultReportMode | Out-Null
        $rendererTimer.Stop()
        Write-ScoutAssessmentLog -Level 'VERBOSE' -Message (
            'Assessment renderer finished: renderer={0}; elapsed={1}' -f
                $r, $rendererTimer.Elapsed.ToString('dd\:hh\:mm\:ss\.fff')
        )
    }

    # ---- PER-ASSESSMENT DATA (AB#6879, clause R-01/R-02 -- SUPERSEDED for rendered documents) ----
    # Owner decision, 2026-08-04 (AB#6928 follow-up): "we have one master file that allows them to
    # dig into the data and go into inventory, go into the assessments chosen ... each in the same
    # overall react page, but separate pages inside that" -- then "ok. I am good with a single file
    # then." The run-root React report already renders every selected assessment as its own
    # section (Export-React groups findings by the `Assessment` property into `payload.
    # assessments[]`), so a SEPARATE report-react.html per assessment folder is now a duplicate of
    # data already in the master file, not a second deliverable.
    #
    # This SUPERSEDES clause R-01 ("a report set per assessment") for RENDERED documents only.
    # R-01's underlying reason -- Phase 0's measurement that a single merged document made three
    # unrelated tenants produce reports within 258 bytes of each other -- no longer applies: the
    # merged React report's per-assessment sections carry each assessment's own score/areas/
    # findings, so the "which assessment did what" signal R-01 existed to restore is now IN the
    # one file, not achieved by writing more files.
    #
    # What is KEPT: each assessment's own findings.json under assessments/<slug>/ (machine-
    # readable data, cheap to write, and the corpus harness / drift history / downstream tooling
    # may read it independently of any rendered document -- same reasoning AB#6922 already applied
    # to Json/JsonEvidence at the run-root level). What is DROPPED: rendering into that folder.
    # 'React' is filtered out of the per-assessment renderer list explicitly (not by relying on
    # $reporters being empty) so a future non-held renderer requested via -OutputFormat still
    # writes its per-assessment copy exactly as before -- only the master-file-duplicating React
    # render is removed.
    if (@($findingsByAssessment.Keys).Count -gt 1) {
        $assessmentRoot = Join-Path $runPath 'assessments'
        $perAssessmentReporters = @($reporters | Where-Object { $_ -ne 'React' })
        foreach ($name in $findingsByAssessment.Keys) {
            $perFindings = @($findingsByAssessment[$name])
            if ($perFindings.Count -eq 0) { continue }

            # Slug: lowercase, non-alphanumerics collapsed to a single dash. 'Assess: Cloud
            # Governance' -> 'assess-cloud-governance'. Folder names must not carry ':' on Windows.
            $slug = ($name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
            $perPath = Join-Path $assessmentRoot $slug
            $null = New-Item -ItemType Directory -Path $perPath -Force

            # Scored INDEPENDENTLY. The per-assessment findings.json must show that assessment's
            # own score, not the run-wide one -- reusing $scored would print the same number in
            # every folder and defeat the point of splitting them. Written unconditionally: this
            # is the machine-readable data AB#6928 kept, independent of which (if any) document
            # renderer is requested below.
            $perScored = Get-Score -Findings $perFindings
            $perScored | ConvertTo-Json -Depth 100 | Out-File "$perPath/findings.json"

            if ($perAssessmentReporters.Count -eq 0) { continue }
            Write-ScoutAssessmentProgress -Status "Rendering: $name"
            foreach ($r in $perAssessmentReporters) {
                # Never fatal. One assessment's renderer failing must not cost the operator the
                # other assessments' reports, nor the merged set already written above.
                try {
                    Export-Report -Renderer $r -Findings $perScored -Collect $collect -OutputPath $perPath -Drift $drift -ReportIdentity $ReportIdentity -DefaultReportMode $DefaultReportMode | Out-Null
                }
                catch {
                    Write-Warning "Invoke-ScoutAssessmentCore: '$r' failed for assessment '$name': $($_.Exception.Message)"
                }
            }
        }

        # ---- EXECUTIVE ROLL-UP DATA (AB#6880, clause R-03 -- SUPERSEDED for rendered documents) ----
        # Same owner decision as above: the run-root React report's per-assessment sections ARE
        # the cross-assessment comparison ("how did we do overall, and which of these is the
        # worst") the roll-up existed to provide -- reading every section of one file rather than
        # a separate deck. rollup.json (machine-readable, same reasoning as findings.json above)
        # is still written. The renderer loop below only ever named 'Pptx'/'Pdf' -- both already
        # held under AB#6922 -- so it was not rendering React before this change either; the
        # explicit exclusion here is defensive documentation, not a functional change, in case a
        # future lift of the Pptx/Pdf hold (AB#6922 is a one-line-edit hold, not a removal) would
        # otherwise silently reintroduce a duplicate roll-up document.
        $execPath = Join-Path $runPath 'executive'
        $null = New-Item -ItemType Directory -Path $execPath -Force

        $execScores = foreach ($name in $findingsByAssessment.Keys) {
            $af = @($findingsByAssessment[$name])
            if ($af.Count -eq 0) { continue }
            $s = Get-Score -Findings $af
            $frameworkScores = @($s.Frameworks | Where-Object { $null -ne $_.Score })
            $assessmentScore = if ($frameworkScores.Count -gt 0) {
                [math]::Round((($frameworkScores | Measure-Object -Property Score -Average).Average), 0)
            }
            else { $null }
            [pscustomobject]@{
                Assessment = $name
                Score      = $assessmentScore
                FrameworkScores = @($s.Frameworks | ForEach-Object {
                    [pscustomobject]@{ Framework = $_.Framework; Score = $_.Score }
                })
                Findings   = $af.Count
                Failed     = @($af | Where-Object { $_.Status -eq 'Fail' }).Count
                Manual     = @($af | Where-Object { $_.Status -eq 'Manual' }).Count
            }
        }
        @($execScores) | ConvertTo-Json -Depth 20 | Out-File "$execPath/rollup.json"

        Write-ScoutAssessmentProgress -Status 'Rendering: executive roll-up'
        foreach ($r in @('Pptx', 'Pdf')) {
            if ($reporters -notcontains $r -or $r -eq 'React') { continue }
            try {
                Export-Report -Renderer $r -Findings $scored -Collect $collect -OutputPath $execPath -Drift $drift -ReportIdentity $ReportIdentity -DefaultReportMode $DefaultReportMode | Out-Null
            }
            catch {
                Write-Warning "Invoke-ScoutAssessmentCore: '$r' failed for the executive roll-up: $($_.Exception.Message)"
            }
        }
    }

    Write-ScoutAssessmentProgress -Completed
    return $runPath
}

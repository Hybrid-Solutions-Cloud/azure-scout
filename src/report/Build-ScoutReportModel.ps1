#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Build the single report model every renderer consumes (AB#6852/AB#6855, Feature AB#6449,
    Epic AB#6450).

.DESCRIPTION
    Before this, five renderers each walked the scored Findings object and each derived its own
    view of the run -- which is exactly why Word, PDF and PPTX lost Evidence and Remediation
    entirely, why Power BI never exported evidence at all, and why the 1-10 CAF Govern domain
    maturity score existed on precisely one HTML page. Adding narrative to five renderers
    independently would have multiplied that divergence by the size of the new surface.

    This function derives ONCE, from data already collected, and emits a versioned
    report-model.json. Renderers become presentation only.

    Nothing here calls Azure. Every number comes from the Collect object the run already
    produced and the Findings object Get-Score already scored.

    THE HONESTY CONSTRAINTS THIS MODEL INHERITS (audit DQ8, AB#6839/#6844/#6845):

      * A domain with a zero scoring denominator is NotAssessed -- never a fabricated 0, never
        silently dropped, and excluded from the composite mean with the exclusion recorded on
        the composite itself so a renderer can state it.
      * A key risk indicator whose supporting count could not be collected carries
        SupportingCount = $null, never 0. "We did not look" and "we looked and found none" are
        different sentences.
      * Evidence truncation (AB#6864) is carried onto every gap-register row, so a renderer
        listing affected resources says "25 of 198" rather than presenting a partial list as
        complete.
      * The triage Verdict on an evidence row is a HEURISTIC suggestion and says so --
        VerdictSource is always 'heuristic' here. It is a starting point for the human triage
        pass the reference workbook records, not a substitute for it. Nothing in this model
        may read as though a person confirmed it.

.NOTES
    Tracks ADO Tasks AB#6852 (the model) and AB#6855 (evidence projection + triage verdict),
    beneath User Story AB#6443. Design: docs/design/reporting-engine-v2.md.
#>

$Script:ScoutReportModelSchemaVersion = '2.0'

#region Shape-agnostic accessors

function Get-ScoutModelProp {
    <#
    .SYNOPSIS
        Read an optional property off an object that may be $null, a Hashtable, or a
        pscustomobject -- without throwing under Set-StrictMode -Version Latest.
    #>
    param($Obj, [Parameter(Mandatory)][string] $Name, $Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    $p = $Obj.PSObject.Properties[$Name]
    if ($p -and $null -ne $p.Value) { return $p.Value }
    return $Default
}

function Test-ScoutModelPath {
    <#
    .SYNOPSIS
        Does this dotted path EXIST on the object, regardless of whether its value is empty?

    .NOTES
        Presence and value have to be asked separately, and this function is why.

        An empty collection cannot survive a PowerShell function's return: the output stream
        enumerates it to nothing, so the caller gets $null and a collected-but-genuinely-empty
        array becomes indistinguishable from one that was never collected. That is precisely
        the distinction the inventory tiles exist to preserve — "no resource locks in this
        estate" and "Scout never looked for resource locks" must not render the same.

        The unary comma preserves emptiness but then double-wraps a NON-empty array for every
        caller that writes @(...), and `Write-Output -NoEnumerate` hands back a List[object]
        wrapper on PowerShell 7. Neither is a contract worth having on a general accessor. So
        the accessor stays simple and returns values, and presence is answered here by walking
        the property bag rather than by inspecting what came back.
    #>
    param($Obj, [Parameter(Mandatory)][string] $Path)
    $cur = $Obj
    foreach ($seg in $Path.Split('.')) {
        if ($null -eq $cur) { return $false }
        if ($cur -is [System.Collections.IDictionary]) {
            if (-not $cur.Contains($seg)) { return $false }
            $cur = $cur[$seg]
            continue
        }
        $p = $cur.PSObject.Properties[$seg]
        if (-not $p) { return $false }
        $cur = $p.Value
    }
    return ($null -ne $cur)
}

function Get-ScoutModelPath {
    <#
    .SYNOPSIS
        Walk a dotted path ('networking.virtualNetworks') returning $null at the first missing
        segment rather than throwing.
    #>
    param($Obj, [Parameter(Mandatory)][string] $Path)
    $cur = $Obj
    foreach ($seg in $Path.Split('.')) {
        if ($null -eq $cur) { return $null }
        $cur = Get-ScoutModelProp -Obj $cur -Name $seg
    }
    return $cur
}

#endregion

#region Maturity rubric

function Get-ScoutMaturityRubric {
    <#
    .SYNOPSIS
        The five named maturity bands the 1-10 domain score is read against.

    .NOTES
        This is Scout's own scale, not a Microsoft-published one -- CAF Govern publishes no
        maturity model at all. See docs/design/governance-domain-maturity-scale.md, and note
        that it is deliberately NOT the WAF 5-level model Get-MaturityLevel.ps1 buckets into;
        the two must never share an axis on one chart.
    #>
    return @(
        [pscustomobject]@{ Min = 1; Max = 2; Level = 'Initial / Reactive'; Description = 'No controls in place; critical gaps; immediate risk to confidentiality, integrity or availability.' }
        [pscustomobject]@{ Min = 3; Max = 4; Level = 'Emerging'; Description = 'Minimal controls; significant gaps; urgent attention needed within the next 30 days.' }
        [pscustomobject]@{ Min = 5; Max = 6; Level = 'Defined'; Description = 'Partial controls in place; some gaps remain; structured improvement programme required.' }
        [pscustomobject]@{ Min = 7; Max = 8; Level = 'Managed'; Description = 'Good controls with only minor gaps; routine refinement sufficient.' }
        [pscustomobject]@{ Min = 9; Max = 10; Level = 'Optimised'; Description = 'Comprehensive controls; well-governed; aligned to industry-leading practice.' }
    )
}

function Get-ScoutMaturityBand {
    param([AllowNull()] $Score)
    if ($null -eq $Score) { return 'Not assessed' }
    foreach ($band in Get-ScoutMaturityRubric) {
        if ($Score -ge $band.Min -and $Score -le $band.Max) { return $band.Level }
    }
    return 'Not assessed'
}

function ConvertTo-ScoutModelScale {
    <#
    .SYNOPSIS
        0-100 -> 1-10, delegating to ConvertTo-ScoutGovernanceScale when it has been loaded so
        the two can never drift apart, and falling back to the identical arithmetic when this
        file is dot-sourced on its own by a narrow unit test.
    #>
    param([AllowNull()][Nullable[double]] $PercentScore)
    if ($null -eq $PercentScore) { return $null }
    if (Get-Command ConvertTo-ScoutGovernanceScale -ErrorAction SilentlyContinue) {
        return ConvertTo-ScoutGovernanceScale -PercentScore $PercentScore
    }
    return [Math]::Max(1, [Math]::Min(10, [Math]::Round($PercentScore / 10.0, 0, [System.MidpointRounding]::AwayFromZero)))
}

#endregion

#region Inventory tiles

# Declarative map of the estate counts the executive summary leads with. Each entry names a
# dotted path into the Collect object; a path that resolves to nothing yields a tile with a
# $null Value, NOT 0 -- "this run did not collect virtual networks" and "this tenant has no
# virtual networks" are different statements and the report must not merge them.
$Script:ScoutReportInventoryMap = @(
    @{ Label = 'Subscriptions'; Path = 'subscriptions' }
    @{ Label = 'Management groups'; Path = 'governance.managementGroups' }
    @{ Label = 'Virtual networks'; Path = 'networking.virtualNetworks' }
    @{ Label = 'Subnets'; Path = 'networking.subnets' }
    @{ Label = 'Private endpoints'; Path = 'networking.privateEndpoints' }
    @{ Label = 'Storage accounts'; Path = 'domains.storage.storageAccounts' }
    @{ Label = 'Key vaults'; Path = 'domains.security.keyVaults' }
    @{ Label = 'Virtual machines'; Path = 'compute.virtualMachines' }
    @{ Label = 'Policy assignments'; Path = 'governance.policyAssignments' }
    @{ Label = 'Role assignments'; Path = 'governance.roleAssignments' }
    @{ Label = 'Resource locks'; Path = 'governance.resourceLocks' }
    @{ Label = 'SQL databases'; Path = 'domains.databases.sqlDatabases' }
    @{ Label = 'AKS clusters'; Path = 'domains.containers.aksClusters' }
    @{ Label = 'Web apps'; Path = 'domains.web.webApps' }
    @{ Label = 'Arc-enabled servers'; Path = 'domains.hybrid.arcServers' }
)

function Get-ScoutInventoryTile {
    <#
    .SYNOPSIS
        Estate counts for the executive summary, from the Collect object only.

    .NOTES
        A tile whose path is absent carries Value = $null and Collected = $false. Renderers
        must show those as "not collected", never as a zero -- the same distinction the audit
        spends §3.3 and §7 on.
    #>
    param($Collect)
    $tiles = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Script:ScoutReportInventoryMap) {
        # Presence is asked of the object, not inferred from what the accessor returned — see
        # Test-ScoutModelPath for why those are different questions.
        $collected = Test-ScoutModelPath -Obj $Collect -Path $entry.Path
        $value = if ($collected) { Get-ScoutModelPath -Obj $Collect -Path $entry.Path } else { $null }
        $tiles.Add([pscustomobject]@{
                Label     = $entry.Label
                Path      = $entry.Path
                Value     = if ($collected) { @($value).Count } else { $null }
                Collected = $collected
            })
    }
    return , $tiles.ToArray()
}

#endregion

#region Evidence projection and triage verdict (AB#6855)

# The property names Azure objects use for the same concept, in the order they are tried.
$Script:ScoutEvidenceFieldMap = @{
    ResourceId    = @('id', 'resourceId', 'ResourceId', 'Id')
    ResourceName  = @('name', 'resourceName', 'displayName', 'Name')
    ResourceType  = @('type', 'resourceType', 'Type')
    ResourceGroup = @('resourceGroup', 'resourceGroupName', 'ResourceGroup')
    SubscriptionId = @('subscriptionId', 'subscription', 'SubscriptionId')
    SubscriptionName = @('subscriptionName', 'SubscriptionName')
    Location      = @('location', 'Location')
}

function Resolve-ScoutEvidenceField {
    param($Row, [Parameter(Mandatory)][string] $Field)
    foreach ($candidate in $Script:ScoutEvidenceFieldMap[$Field]) {
        $v = Get-ScoutModelProp -Obj $Row -Name $candidate
        if ($null -ne $v -and "$v".Trim()) { return "$v" }
    }
    return $null
}

function Get-ScoutSubscriptionIdFromArmId {
    param([AllowNull()][string] $ResourceId)
    if ([string]::IsNullOrWhiteSpace($ResourceId)) { return $null }
    $m = [regex]::Match($ResourceId, '/subscriptions/([0-9a-fA-F-]{36}|[^/]+)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-ScoutResourceGroupFromArmId {
    param([AllowNull()][string] $ResourceId)
    if ([string]::IsNullOrWhiteSpace($ResourceId)) { return $null }
    $m = [regex]::Match($ResourceId, '/resourceGroups/([^/]+)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-ScoutTriageVerdict {
    <#
    .SYNOPSIS
        Suggest a triage verdict for one evidence row, using the four-value vocabulary the
        reference gap workbook uses.

    .DESCRIPTION
        The reference engagement's workbook is only useful because every raw row carries a
        verdict: it is what turns "149 non-group Owner assignments" into "141 deliberate
        vending service principals plus 8 humans". A raw count without that column is noise,
        and a report built on raw counts alarms people about controls nobody chose to evaluate.

        This is a HEURISTIC first pass over naming and placement, nothing more. It exists to
        sort a long list so a human triages the interesting rows first. Every row it returns
        carries VerdictSource = 'heuristic' precisely so no renderer can present it as a
        confirmed judgement -- the reference workbook's verdicts were made by people who knew
        the estate, and this cannot be that.

    .OUTPUTS
        One of: 'Real - investigate', 'Platform-required - deliberate pattern',
        'Sandbox - out of scope by design', 'Inherited from legacy'.
    #>
    param(
        [AllowNull()][string] $ResourceId,
        [AllowNull()][string] $ResourceName,
        [AllowNull()][string] $SubscriptionName,
        [AllowNull()][string] $ResourceGroup
    )
    $haystack = (@($ResourceId, $ResourceName, $SubscriptionName, $ResourceGroup) |
        Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() }) -join ' '

    if (-not $haystack) { return 'Real - investigate' }

    # Sandbox / test placements are excluded from production guard-rails by design in every
    # CAF Enterprise-Scale topology, so flagging them as findings is noise.
    if ($haystack -match '(^|[^a-z])(sandbox|sbx|vendingtest|testharness|scratch)([^a-z]|$)') {
        return 'Sandbox - out of scope by design'
    }
    # Azure-managed and platform-vended resources: the customer cannot change these, and a
    # report that demands they do is one the reader stops trusting.
    if ($haystack -match '(databricks-rg|databricks-rsg|-mngd-dbw|managed-rg|mc_|aks-managed|networkwatcherrg|defaultresourcegroup|logflow|flowlog|nsgflow|microsoft\.\w+/managed)') {
        return 'Platform-required - deliberate pattern'
    }
    if ($haystack -match '(spn-(dv|pr|np|int|ppe|prd)-alz-|deploy-vm-monitoring|deploy-vmss-|deploy-mdfc-config)') {
        return 'Platform-required - deliberate pattern'
    }
    # Anything sitting outside a subscription scope entirely (a tenant-root or legacy
    # management-group assignment) is likely to disappear with the legacy estate.
    if ($ResourceId -and $ResourceId -match '^/providers/microsoft\.management/managementgroups/' -and
        $haystack -match '(legacy|tenantroot|cloudmgmt|decommission)') {
        return 'Inherited from legacy'
    }
    return 'Real - investigate'
}

function ConvertTo-ScoutEvidenceRow {
    <#
    .SYNOPSIS
        Project a finding's raw matched Azure objects to the resource grain the per-subscription
        findings table and the Excel gap workbook both need (AB#6855).

    .NOTES
        Absent fields are $null, never a fabricated empty string, so a renderer can tell "this
        object carried no resource group" from "the resource group is blank".
    #>
    param(
        [Parameter(Mandatory)] $Finding,
        [Parameter(Mandatory)][string] $GapId,
        $SubscriptionLookup = @{}
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($raw in @(Get-ScoutModelProp -Obj $Finding -Name 'Evidence' -Default @())) {
        if ($null -eq $raw) { continue }

        # Newtonsoft JObject tokens (what Resolve-JsonPath hands back) do not expose their
        # fields as PSObject properties. Round-trip them through the JSON they already are.
        $row = $raw
        if ($raw.GetType().FullName -like 'Newtonsoft.Json.Linq.*') {
            try { $row = $raw.ToString() | ConvertFrom-Json -Depth 20 } catch { $row = $raw }
        }
        # A scalar match (a bare string or number) carries no resource identity at all.
        if ($row -is [string] -or $row -is [ValueType]) {
            $rows.Add([pscustomobject]@{
                    GapId = $GapId; RuleId = Get-ScoutModelProp $Finding 'Id'
                    SubscriptionId = $null; SubscriptionName = $null; ResourceGroup = $null
                    ResourceName = "$row"; ResourceId = $null; ResourceType = $null; Location = $null
                    Observation = Get-ScoutModelProp $Finding 'Title'
                    Verdict = 'Real - investigate'; VerdictSource = 'heuristic'
                })
            continue
        }

        $resourceId = Resolve-ScoutEvidenceField -Row $row -Field 'ResourceId'
        $subId = Resolve-ScoutEvidenceField -Row $row -Field 'SubscriptionId'
        if (-not $subId) { $subId = Get-ScoutSubscriptionIdFromArmId -ResourceId $resourceId }
        $rg = Resolve-ScoutEvidenceField -Row $row -Field 'ResourceGroup'
        if (-not $rg) { $rg = Get-ScoutResourceGroupFromArmId -ResourceId $resourceId }

        $subName = Resolve-ScoutEvidenceField -Row $row -Field 'SubscriptionName'
        if (-not $subName -and $subId -and $SubscriptionLookup.ContainsKey($subId)) {
            $subName = $SubscriptionLookup[$subId]
        }

        $resourceName = Resolve-ScoutEvidenceField -Row $row -Field 'ResourceName'

        $rows.Add([pscustomobject]@{
                GapId            = $GapId
                RuleId           = Get-ScoutModelProp $Finding 'Id'
                SubscriptionId   = $subId
                SubscriptionName = $subName
                ResourceGroup    = $rg
                ResourceName     = $resourceName
                ResourceId       = $resourceId
                ResourceType     = Resolve-ScoutEvidenceField -Row $row -Field 'ResourceType'
                Location         = Resolve-ScoutEvidenceField -Row $row -Field 'Location'
                Observation      = Get-ScoutModelProp $Finding 'Title'
                Verdict          = Get-ScoutTriageVerdict -ResourceId $resourceId -ResourceName $resourceName `
                    -SubscriptionName $subName -ResourceGroup $rg
                VerdictSource    = 'heuristic'
            })
    }
    return , $rows.ToArray()
}

#endregion

#region Severity helpers

$Script:ScoutModelSeverityRank = @{ critical = 0; high = 1; medium = 2; low = 3 }

function Get-ScoutModelSeverityRank {
    param($Severity)
    if ($Severity) {
        $key = "$Severity".Trim().ToLowerInvariant()
        if ($Script:ScoutModelSeverityRank.ContainsKey($key)) { return $Script:ScoutModelSeverityRank[$key] }
    }
    return 99      # unknown/absent sorts LAST, never first (AB#5089)
}

function Get-ScoutModelSeverityLabel {
    param($Severity)
    if ($Severity -and "$Severity".Trim()) { return "$Severity".ToUpperInvariant() }
    return 'UNKNOWN'
}

#endregion

#region Gap register, KRIs and roadmap

function New-ScoutGapRegister {
    <#
    .SYNOPSIS
        One row per open gap: what was observed, what closes it, how bad it is, and the action.

    .NOTES
        A gap row is built from a Fail or Partial finding. Manual and NotAssessed findings are
        NOT gaps -- a control nobody could evaluate is a coverage gap, reported separately, and
        collapsing it into the register would assert a failure the data never showed.
    #>
    param($Findings, $SubscriptionLookup = @{})

    $open = @(@($Findings) | Where-Object { (Get-ScoutModelProp $_ 'Status') -in 'Fail', 'Partial' })
    $sorted = @($open | Sort-Object `
        @{ Expression = { Get-ScoutModelSeverityRank (Get-ScoutModelProp $_ 'Severity') } }, `
        @{ Expression = { Get-ScoutModelProp $_ 'Area' } }, `
        @{ Expression = { Get-ScoutModelProp $_ 'Id' } })

    $register = [System.Collections.Generic.List[object]]::new()
    $n = 0
    foreach ($f in $sorted) {
        $n++
        $gapId = 'G{0:D2}' -f $n
        $count = Get-ScoutModelProp $f 'EvidenceCount' -Default 0
        $truncated = [bool](Get-ScoutModelProp $f 'EvidenceTruncated' -Default $false)
        $cap = Get-ScoutModelProp $f 'EvidenceCap'

        $register.Add([pscustomobject]@{
                GapId                = $gapId
                RuleId               = Get-ScoutModelProp $f 'Id'
                Framework            = Get-ScoutModelProp $f 'Framework'
                Domain               = Get-ScoutModelProp $f 'Area'
                Title                = Get-ScoutModelProp $f 'Title'
                CurrentStateObserved = ('{0:N0} {1} matched this condition.' -f $count, $(if ($count -eq 1) { 'resource' } else { 'resources' }))
                EvidenceCount        = $count
                EvidenceShown        = @(Get-ScoutModelProp $f 'Evidence' -Default @()).Count
                EvidenceTruncated    = $truncated
                EvidenceCap          = $cap
                TargetState          = Get-ScoutModelProp $f 'TargetState'
                Severity             = Get-ScoutModelSeverityLabel (Get-ScoutModelProp $f 'Severity')
                ClosureAction        = Get-ScoutModelProp $f 'Remediation'
                Owner                = Get-ScoutModelProp $f 'Owner'
                Effort               = Get-ScoutModelProp $f 'Effort'
                Phase                = Get-ScoutModelProp $f 'Phase'
                Evidence             = ConvertTo-ScoutEvidenceRow -Finding $f -GapId $gapId -SubscriptionLookup $SubscriptionLookup
            })
    }
    return , $register.ToArray()
}

function New-ScoutKeyRiskIndicator {
    <#
    .SYNOPSIS
        The material risks, each stated WITH the number that supports it.

    .NOTES
        The reference report's KRI table is the section executives read, and every row of it
        carries a count ("60 of 198 storage accounts"). A KRI without its supporting number is
        an opinion. Rows whose count could not be collected carry SupportingCount = $null and
        must be rendered as "not collected", never as 0.

        GOOD rows are deliberately included: the reference table lists strengths alongside
        risks, because a report that only lists failures reads as an indictment rather than an
        assessment, and the reader discounts all of it.
    #>
    param($Findings, [int] $Top = 15)

    $kris = [System.Collections.Generic.List[object]]::new()

    $open = @(@($Findings) | Where-Object { (Get-ScoutModelProp $_ 'Status') -in 'Fail', 'Partial' })
    $ranked = @($open | Sort-Object `
        @{ Expression = { Get-ScoutModelSeverityRank (Get-ScoutModelProp $_ 'Severity') } }, `
        @{ Expression = { -1 * [int](Get-ScoutModelProp $_ 'EvidenceCount' -Default 0) } })

    foreach ($f in @($ranked | Select-Object -First $Top)) {
        $count = Get-ScoutModelProp $f 'EvidenceCount' -Default 0
        $kris.Add([pscustomobject]@{
                RiskArea        = Get-ScoutModelProp $f 'Title'
                Domain          = Get-ScoutModelProp $f 'Area'
                CurrentState    = ('{0:N0} {1} in scope matched this condition.' -f $count, $(if ($count -eq 1) { 'resource' } else { 'resources' }))
                SupportingCount = $count
                Severity        = Get-ScoutModelSeverityLabel (Get-ScoutModelProp $f 'Severity')
                RuleId          = Get-ScoutModelProp $f 'Id'
            })
    }

    # Strengths: a control that passed with evidence behind it is worth stating.
    $passing = @(@($Findings) |
        Where-Object {
            (Get-ScoutModelProp $_ 'Status') -eq 'Pass' -and
            [int](Get-ScoutModelProp $_ 'EvidenceCount' -Default 0) -gt 0
        } |
        Sort-Object @{ Expression = { -1 * [int](Get-ScoutModelProp $_ 'EvidenceCount' -Default 0) } } |
        Select-Object -First 3)

    foreach ($f in $passing) {
        $count = Get-ScoutModelProp $f 'EvidenceCount' -Default 0
        $kris.Add([pscustomobject]@{
                RiskArea        = Get-ScoutModelProp $f 'Title'
                Domain          = Get-ScoutModelProp $f 'Area'
                CurrentState    = ('Control satisfied across {0:N0} {1} in scope.' -f $count, $(if ($count -eq 1) { 'resource' } else { 'resources' }))
                SupportingCount = $count
                Severity        = 'GOOD'
                RuleId          = Get-ScoutModelProp $f 'Id'
            })
    }

    # A control that could not be evaluated is a coverage gap, and hiding it would let the
    # report read as though the estate was fully examined (audit DQ8).
    $notAssessed = @(@($Findings) | Where-Object { (Get-ScoutModelProp $_ 'Status') -eq 'NotAssessed' })
    if ($notAssessed.Count -gt 0) {
        $kris.Add([pscustomobject]@{
                RiskArea        = 'Controls that could not be evaluated'
                Domain          = 'Coverage'
                CurrentState    = ('{0:N0} {1} returned no data — the source was gated or not collected, so neither a pass nor a fail can be claimed.' -f $notAssessed.Count, $(if ($notAssessed.Count -eq 1) { 'control' } else { 'controls' }))
                SupportingCount = $notAssessed.Count
                Severity        = 'UNKNOWN'
                RuleId          = $null
            })
    }

    return , $kris.ToArray()
}

function New-ScoutRoadmap {
    <#
    .SYNOPSIS
        Three 30-day phases built from the gap register.

    .NOTES
        A gap's phase comes from its rule when the rule declares one (AB#6853). When it does
        not, severity decides: CRITICAL/HIGH land in Phase 1, MEDIUM in Phase 2, everything
        else in Phase 3. That default is stated on the model as PhaseSource so a renderer can
        distinguish an authored sequence from a derived one.
    #>
    param($GapRegister)

    $phaseMeta = @(
        [pscustomobject]@{ Phase = 1; Name = 'Foundation'; DayRange = 'Days 0-30' }
        [pscustomobject]@{ Phase = 2; Name = 'Hardening'; DayRange = 'Days 30-60' }
        [pscustomobject]@{ Phase = 3; Name = 'Optimisation & Verification'; DayRange = 'Days 60-90' }
    )

    $phases = [System.Collections.Generic.List[object]]::new()
    foreach ($meta in $phaseMeta) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($gap in @($GapRegister)) {
            $declared = Get-ScoutModelProp $gap 'Phase'
            $resolved = if ($null -ne $declared) { [int]$declared }
            elseif ($gap.Severity -in 'CRITICAL', 'HIGH') { 1 }
            elseif ($gap.Severity -eq 'MEDIUM') { 2 }
            else { 3 }
            if ($resolved -ne $meta.Phase) { continue }
            $items.Add([pscustomobject]@{
                    GapId       = $gap.GapId
                    Domain      = $gap.Domain
                    Action      = $gap.ClosureAction
                    Owner       = $gap.Owner
                    Effort      = $gap.Effort
                    Severity    = $gap.Severity
                    Window      = $meta.DayRange
                    PhaseSource = if ($null -ne $declared) { 'rule' } else { 'derived-from-severity' }
                })
        }
        $phases.Add([pscustomobject]@{
                Phase    = $meta.Phase
                Name     = $meta.Name
                DayRange = $meta.DayRange
                Items    = $items.ToArray()
            })
    }
    return , $phases.ToArray()
}

#endregion

#region Maturity domains

function New-ScoutMaturityDomain {
    <#
    .SYNOPSIS
        One row per assessed area: the 1-10 score, its band, and the status counts behind it.
    #>
    param($Areas, $Narrative = $null)

    $domains = [System.Collections.Generic.List[object]]::new()
    foreach ($a in @(@($Areas) | Sort-Object Framework, Area)) {
        $pct = Get-ScoutModelProp $a 'Score'
        $notAssessed = ($null -eq $pct)
        $score = ConvertTo-ScoutModelScale -PercentScore $pct
        $key = "$(Get-ScoutModelProp $a 'Area')"
        $narr = Get-ScoutModelProp $Narrative $key

        $domains.Add([pscustomobject]@{
                Framework          = Get-ScoutModelProp $a 'Framework'
                Domain             = $key
                PercentScore       = $pct
                Score              = $score
                Band               = Get-ScoutMaturityBand -Score $score
                NotAssessed        = $notAssessed
                Pass               = Get-ScoutModelProp $a 'Pass' -Default 0
                Partial            = Get-ScoutModelProp $a 'Partial' -Default 0
                Fail               = Get-ScoutModelProp $a 'Fail' -Default 0
                Manual             = Get-ScoutModelProp $a 'Manual' -Default 0
                Unknown            = Get-ScoutModelProp $a 'Unknown' -Default 0
                Error              = Get-ScoutModelProp $a 'Error' -Default 0
                WhyThisMatters     = Get-ScoutModelProp $narr 'whyThisMatters'
                TargetScore        = Get-ScoutModelProp $narr 'targetScore'
                WhatIsWorking      = $null      # bound by the narrative pass (AB#6854)
                WhatNeedsAttention = $null
                CurrentState       = $null
            })
    }
    return , $domains.ToArray()
}

function New-ScoutCompositeScore {
    <#
    .SYNOPSIS
        The headline maturity number: the unweighted mean of the ASSESSED domains only.

    .NOTES
        NotAssessed domains are excluded from the mean, and the count of exclusions is carried
        on the result so a renderer can state it. Averaging a fabricated 0 into the composite
        would drag the headline down to describe controls nobody evaluated -- the exact
        false-read the audit's three-state decision (DQ8) exists to prevent.
    #>
    param($Domains)

    $assessed = @(@($Domains) | Where-Object { -not $_.NotAssessed -and $null -ne $_.Score })
    $excluded = @(@($Domains) | Where-Object { $_.NotAssessed }).Count

    if ($assessed.Count -eq 0) {
        return [pscustomobject]@{
            Current = $null; Target = $null; Gap = $null; Band = 'Not assessed'
            AssessedDomainCount = 0; ExcludedDomainCount = $excluded
        }
    }

    $current = [Math]::Round((($assessed | Measure-Object -Property Score -Sum).Sum / $assessed.Count), 1)
    $targets = @($assessed | Where-Object { $null -ne $_.TargetScore })
    $target = if ($targets.Count -eq $assessed.Count -and $targets.Count -gt 0) {
        [Math]::Round((($targets | Measure-Object -Property TargetScore -Sum).Sum / $targets.Count), 1)
    } else { $null }

    return [pscustomobject]@{
        Current             = $current
        Target              = $target
        Gap                 = if ($null -ne $target) { [Math]::Round($target - $current, 1) } else { $null }
        Band                = Get-ScoutMaturityBand -Score ([Math]::Round($current))
        AssessedDomainCount = $assessed.Count
        ExcludedDomainCount = $excluded
    }
}

function New-ScoutFocusArea {
    <#
    .SYNOPSIS
        Domains ranked by urgency — lowest maturity first, ties broken by open-gap count.
    #>
    param($Domains, $GapRegister)

    $gapsByDomain = @{}
    foreach ($g in @($GapRegister)) {
        $d = "$($g.Domain)"
        if (-not $gapsByDomain.ContainsKey($d)) { $gapsByDomain[$d] = 0 }
        $gapsByDomain[$d]++
    }

    $ranked = @(@($Domains) |
        Where-Object { -not $_.NotAssessed } |
        Sort-Object `
            @{ Expression = { $_.Score } }, `
            @{ Expression = { -1 * $(if ($gapsByDomain.ContainsKey("$($_.Domain)")) { $gapsByDomain["$($_.Domain)"] } else { 0 }) } })

    $out = [System.Collections.Generic.List[object]]::new()
    $rank = 0
    foreach ($d in $ranked) {
        $rank++
        $status = if ($d.Score -le 4) { 'CRITICAL' } elseif ($d.Score -le 6) { 'WARNING' } elseif ($d.Score -le 8) { 'FAIR' } else { 'GOOD' }
        $priority = if ($d.Score -le 4) { 'IMMEDIATE' } elseif ($d.Score -le 6) { 'URGENT' } elseif ($d.Score -le 8) { 'MEDIUM' } else { 'LOW' }
        $out.Add([pscustomobject]@{
                Rank     = $rank
                Domain   = $d.Domain
                Score    = $d.Score
                Band     = $d.Band
                OpenGaps = $(if ($gapsByDomain.ContainsKey("$($d.Domain)")) { $gapsByDomain["$($d.Domain)"] } else { 0 })
                Status   = $status
                Priority = $priority
            })
    }
    return , $out.ToArray()
}

#endregion

function Build-ScoutReportModel {
    <#
    .SYNOPSIS
        Build the versioned report model every renderer consumes.

    .PARAMETER Findings
        The scored object from Get-Score (GeneratedOn/Frameworks/Areas/Gaps/Manual/Errors/Findings).

    .PARAMETER Collect
        The raw collect object. Read for inventory tiles, subscription detail and _meta only —
        never re-queried, never re-collected.

    .PARAMETER Narrative
        Optional authored narrative keyed by domain name (AB#6854). Absent means the model
        carries $null narrative fields and renderers omit those sections rather than inventing
        prose.

    .PARAMETER OutputPath
        Optional directory. When supplied, report-model.json is written into it.

    .OUTPUTS
        The report model object. Also written to $OutputPath/report-model.json when requested.
    #>
    param(
        $Findings,
        $Collect,
        $Narrative = $null,
        [string] $OutputPath,
        [string] $RunId
    )

    $meta = Get-ScoutModelProp $Collect '_meta'

    # Subscription id -> name, so evidence rows carrying only an ARM id can still name the
    # subscription a resource lives in.
    $subscriptions = @(Get-ScoutModelProp $Collect 'subscriptions' -Default @())
    $subLookup = @{}
    foreach ($s in $subscriptions) {
        $id = Get-ScoutModelProp $s 'id'
        $name = Get-ScoutModelProp $s 'name'
        if ($id -and $name) { $subLookup["$id"] = "$name" }
    }

    $areas = @(Get-ScoutModelProp $Findings 'Areas' -Default @())
    $allFindings = @(Get-ScoutModelProp $Findings 'Findings' -Default @())
    $frameworks = @(Get-ScoutModelProp $Findings 'Frameworks' -Default @())

    $domains = New-ScoutMaturityDomain -Areas $areas -Narrative $Narrative
    $gapRegister = New-ScoutGapRegister -Findings $allFindings -SubscriptionLookup $subLookup

    $model = [pscustomobject]@{
        SchemaVersion = $Script:ScoutReportModelSchemaVersion
        Meta          = [pscustomobject]@{
            GeneratedOn       = Get-ScoutModelProp $Findings 'GeneratedOn' -Default ((Get-Date).ToString('o'))
            RunId             = $RunId
            Scope             = Get-ScoutModelProp $meta 'scope'
            ManagementGroupId = Get-ScoutModelProp $meta 'managementGroupId'
        }
        Engagement    = [pscustomobject]@{
            TenantId             = Get-ScoutModelProp $meta 'tenantId'
            AssessmentDate       = (Get-ScoutModelProp $Findings 'GeneratedOn' -Default ((Get-Date).ToString('o')))
            Classification       = 'CONFIDENTIAL — For Internal Use Only'
            FrameworksReferenced = @($frameworks | ForEach-Object {
                    [pscustomobject]@{
                        Framework = Get-ScoutModelProp $_ 'Framework'
                        Score     = Get-ScoutModelProp $_ 'Score'
                        Version   = Get-ScoutModelProp $_ 'Version'
                    }
                })
        }
        Scope         = [pscustomobject]@{
            ManagementGroupId = Get-ScoutModelProp $meta 'managementGroupId'
            SubscriptionCount = $subscriptions.Count
            Subscriptions     = @($subscriptions | ForEach-Object {
                    [pscustomobject]@{
                        Id    = Get-ScoutModelProp $_ 'id'
                        Name  = Get-ScoutModelProp $_ 'name'
                        State = Get-ScoutModelProp $_ 'state'
                    }
                })
        }
        Inventory     = [pscustomobject]@{ Tiles = (Get-ScoutInventoryTile -Collect $Collect) }
        Maturity      = [pscustomobject]@{
            Rubric    = (Get-ScoutMaturityRubric)
            Domains   = $domains
            Composite = (New-ScoutCompositeScore -Domains $domains)
        }
        KeyRiskIndicators = (New-ScoutKeyRiskIndicator -Findings $allFindings)
        FocusAreas        = (New-ScoutFocusArea -Domains $domains -GapRegister $gapRegister)
        GapRegister       = $gapRegister
        Roadmap           = [pscustomobject]@{
            Phases       = (New-ScoutRoadmap -GapRegister $gapRegister)
            ExitCriteria = @(
                'Every gap in the register is closed, formally risk-accepted with a named owner, or re-scoped.'
                'No control in the assessed scope remains in the "could not be evaluated" state without a documented reason.'
                'The assessment is re-run and the composite maturity score is recomputed against the target.'
            )
        }
        Coverage      = [pscustomobject]@{
            ManualReviewItems  = @(Get-ScoutModelProp $Findings 'Manual' -Default @()).Count
            ErrorItems         = @(Get-ScoutModelProp $Findings 'Errors' -Default @()).Count
            NotAssessedItems   = @(@($allFindings) | Where-Object { (Get-ScoutModelProp $_ 'Status') -eq 'NotAssessed' }).Count
            AssessedDomains    = @(@($domains) | Where-Object { -not $_.NotAssessed }).Count
            NotAssessedDomains = @(@($domains) | Where-Object { $_.NotAssessed }).Count
        }
        Appendices    = [pscustomobject]@{
            Findings = $allFindings
            Manual   = @(Get-ScoutModelProp $Findings 'Manual' -Default @())
            Errors   = @(Get-ScoutModelProp $Findings 'Errors' -Default @())
        }
    }

    # AB#6854 — compose the prose LAST, because every sentence in it is derived from the
    # domains and the gap register above. Soft dependency: a caller that has not dot-sourced
    # Build-ScoutNarrative.ps1 gets the model with no Narrative property and $null domain
    # CurrentState, and the renderers fall back to their table-only sections.
    if (Get-Command Add-ScoutNarrativeToModel -ErrorAction SilentlyContinue) {
        $model = Add-ScoutNarrativeToModel -Model $model
    }

    if ($OutputPath) {
        if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
        $model | ConvertTo-Json -Depth 100 | Out-File (Join-Path $OutputPath 'report-model.json') -Encoding utf8
    }

    return $model
}

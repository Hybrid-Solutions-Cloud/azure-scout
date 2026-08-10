#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Render the self-contained React single-page report from scored findings.

.DESCRIPTION
    Same renderer contract as every other Export-* renderer: consumes the scored Findings
    object produced by Get-Score (GeneratedOn/Frameworks/Areas/Gaps/Manual/Errors/Findings)
    plus the raw Collect object. AB#6922 made this the product's deliverable -- everything the
    approved design (D:\tmp\azure-scout-react-mockups\unified-hcs.html) needs is built HERE so
    the front end (report-react.html.template) never re-derives anything from a thinner shape.

    The full payload contract (window.__SCOUT_DATA__) is:

        identity, meta, ran, inventory, subscriptions, assessments, resourceIndex, drift,
        costProjection (AB#7093 -- transparent trailing-30-day cost run-rate extrapolation)

    See each builder function below for the exact shape it produces. Everything is inlined
    into one report-react.html file -- CSS/JS/data all embedded -- so the report opens and
    works fully offline, same as every other renderer.

.PARAMETER Findings
    The scored Findings object from Get-Score (merged run, or a single assessment's own score
    when this is called for a per-assessment folder -- see Invoke-ScoutAssessmentCore).

.PARAMETER Collect
    The raw Collect object.

.PARAMETER OutputPath
    Folder to write report-react.html into. Created if missing. Also used to derive `meta.runId`
    (its own leaf folder name is the run's timestamp id -- see Invoke-ScoutAssessmentCore).

.PARAMETER Drift
    Optional. The drift object from Get-ScoutDrift. Embedded as-is; $null when omitted.

.PARAMETER ReportIdentity
    Optional hashtable of report identity fields (AB#6930) -- clientName, engagementName,
    reportTitle, classification, etc. Unset fields fall back to neutral defaults (never a
    vendor name or URL) via Get-ScoutReportIdentityDefault.

.OUTPUTS
    [string] the full path to the written report-react.html file.

.NOTES
    Tracks ADO Story AB#5053 and Feature AB#6928 (AB#6929 payload / AB#6930 identity).
#>
function Export-React {
    param(
        $Findings,
        $Collect,
        [string] $OutputPath,
        $Drift = $null,
        [hashtable] $ReportIdentity = @{},
        # AB#6928 follow-up (single-master-file decision) -- which of the front end's three view
        # lenses opens first when there is nothing persisted in the browser's localStorage yet
        # (the front end's own loadPersisted() always prefers a returning visitor's stored
        # choice; this only sets the FIRST-OPEN default). NOT a build-time filter -- all three
        # modes always ship in the one file; a `-ReportModes` switch that emitted only some of
        # them was discussed and explicitly deferred as speculative.
        [ValidateSet('Executive', 'Consultant', 'Data')]
        [string] $DefaultReportMode = 'Consultant'
    )

    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    # ---- shared safe-access helpers -----------------------------------------------------------

    # Walks a dotted path one segment at a time, returning $null the moment any segment is
    # absent instead of throwing -- $Collect/$Findings may be a plain deserialized
    # PSCustomObject missing keys this renderer doesn't require, and Set-StrictMode -Version
    # Latest throws on a missing-property dot-access.
    function Get-ReactSafeProp {
        param($Object, [string[]] $Path)
        $cur = $Object
        foreach ($seg in $Path) {
            if ($null -eq $cur) { return $null }
            $prop = $cur.PSObject.Properties[$seg]
            if (-not $prop) { return $null }
            $cur = $prop.Value
        }
        return $cur
    }

    # Reads a property off a PSCustomObject/Hashtable evidence row without assuming its shape --
    # every evidence row below is read this way rather than by dot-access, because Evidence rows
    # come from a dozen different collectors and no two of them share a field-name convention.
    function Get-ReactRowProp {
        param($Row, [string] $Name)
        if ($null -eq $Row) { return $null }
        if ($Row -is [System.Collections.IDictionary]) {
            if ($Row.Contains($Name)) { return $Row[$Name] }
            return $null
        }
        # A handful of Newtonsoft JToken shapes (observed on real rule output: a JSONPath query
        # that resolves to an object's own child PROPERTIES rather than array elements/objects)
        # slip past ConvertFrom-ReactJToken's normalisation with a .PSObject that PowerShell's
        # adapter cannot build a `Properties` collection for. Evidence identity is a best-effort
        # read, never a hard requirement -- degrading a genuinely unreadable row to "no value for
        # this field" is the right failure mode, not aborting the whole report.
        try {
            $p = $Row.PSObject.Properties[$Name]
            if ($p) { return $p.Value }
        }
        catch { return $null }
        return $null
    }

    # AB#6929 -- subscription id is embedded in almost every ARM resource id
    # ("/subscriptions/<guid>/..."), so a row carrying only an `id`/`ResourceId`/`keyVaultId`/
    # `targetResourceId` field can still be attributed without a direct subscriptionId column.
    $armSubRegex = [regex]'(?i)/subscriptions/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})'
    $armRgRegex  = [regex]'(?i)/resource[gG]roups/([^/]+)'
    function Get-ReactArmSubscriptionId {
        param([string] $ArmId)
        if ([string]::IsNullOrWhiteSpace($ArmId)) { return $null }
        $m = $armSubRegex.Match($ArmId)
        if ($m.Success) { return $m.Groups[1].Value }
        return $null
    }
    function Get-ReactArmResourceGroup {
        param([string] $ArmId)
        if ([string]::IsNullOrWhiteSpace($ArmId)) { return $null }
        $m = $armRgRegex.Match($ArmId)
        if ($m.Success) { return $m.Groups[1].Value }
        return $null
    }

    # ---- meta / ran ----------------------------------------------------------------------------

    $metaSrc = Get-ReactSafeProp $Collect @('_meta')
    $subscriptions = @(Get-ReactSafeProp $Collect @('subscriptions'))

    # `ran` drives the adaptive nav -- which top-level sections the shell even offers -- AND the
    # derived reportTitle default just below, so it is computed here, ahead of the identity block.
    # `entra`: the Collect layer (Invoke-Collect) is ARM/Resource Graph only -- there is no
    # Entra/Graph collection path in this platform (see Invoke-ScoutAssessmentCore's own NOTES),
    # so this is always false for a Collect built by this pipeline. Left as an explicit field
    # (not just omitted) so a future Entra-aware Collect only has to flip this, not add a key.
    #
    # `@(Get-ReactSafeProp ...)` alone is NOT a safe truthiness check here: `@($null)` is an array
    # of ONE null element (`.Count` = 1), so a Collect that never carried the property at all --
    # e.g. a bare `_meta`-only object from a CollectOnly run with no ARM access -- would still
    # read as "has inventory data". Test-ReactHasRow treats absent/null as zero explicitly.
    function Test-ReactHasRow {
        param($Value)
        return ($null -ne $Value -and @($Value).Count -gt 0)
    }
    $inventoryHasData = [bool]((Test-ReactHasRow (Get-ReactSafeProp $Collect @('subscriptions'))) -or
        (Test-ReactHasRow (Get-ReactSafeProp $Collect @('networking', 'virtualNetworks'))) -or
        (Test-ReactHasRow (Get-ReactSafeProp $Collect @('compute', 'virtualMachines'))))
    $allFindingsRows = @(Get-ReactSafeProp $Findings @('Findings'))
    $ran = [ordered]@{
        inventory   = $inventoryHasData
        entra       = $false
        assessments = [bool]($allFindingsRows.Count -gt 0)
    }

    # AB#6930 default identity -- kept in its own function so tests can assert the neutral
    # fallback set without invoking the whole renderer.
    #
    # reportTitle (owner directive, AB#6928 follow-up 2026-08-04): the document is now ONE master
    # file carrying inventory plus whichever assessments were selected -- naming it after a single
    # assessment ("Azure Landing Zone Assessment") is a leftover from the per-assessment era and
    # is wrong the moment a run scopes to inventory only, or to a different assessment, or both.
    # Derived from the SAME `ran` flags that drive the adaptive nav, so the title always matches
    # what the reader is actually looking at. `-Ran` is passed in rather than read from a closure
    # variable so Get-ScoutReportIdentityDefault stays callable standalone in tests.
    function Get-ScoutReportIdentityDefault {
        param($Ran)
        $derivedTitle = if ($Ran -and $Ran.inventory -and $Ran.assessments) { 'Azure Inventory and Assessment' }
                        elseif ($Ran -and $Ran.assessments) { 'Azure Assessment' }
                        else { 'Azure Inventory' }
        [pscustomobject]@{
            preparingOrganisation = ''
            clientName            = 'Client Organization'
            engagementName        = 'Cloud Governance & Well-Architected Assessment'
            reportTitle            = $derivedTitle
            reportSubtitle          = 'Cloud Governance & Well-Architected Review'
            classification         = 'Confidential — Client Use Only'
            preparedBy             = ''
            preparedFor            = ''
            author                 = ''
            reviewer               = ''
            reportDate             = (Get-Date).ToString('yyyy-MM-dd')
            assessmentPeriod       = ''
            scopeStatement         = 'All Azure subscriptions and management groups in tenant scope at the time of collection.'
            documentReference      = ''
            version                = '1.0 (Draft)'
            handlingFooter         = ''
            logoDataUri            = ''
        }
    }
    $identityDefault = Get-ScoutReportIdentityDefault -Ran $ran
    $identity = [ordered]@{}
    foreach ($p in $identityDefault.PSObject.Properties) {
        # An explicitly supplied -ReportIdentity value ALWAYS wins over the derived default --
        # including reportTitle, so a caller who wants "Azure Landing Zone Assessment" (or
        # anything else) back is never overruled by the ran-derived guess.
        $override = if ($ReportIdentity -and $ReportIdentity.ContainsKey($p.Name) -and $ReportIdentity[$p.Name]) { $ReportIdentity[$p.Name] } else { $null }
        $identity[$p.Name] = if ($override) { $override } else { $p.Value }
    }
    # "Confidential — do not distribute outside Acme Corp", falling back to the classification
    # alone when clientName is unset (never a dangling "outside —"). Mirrors the mockup's
    # fallbackHandlingFooter() in D:\tmp\azure-scout-react-mockups\_build\identity.cjs.
    if (-not $identity.handlingFooter) {
        $identity.handlingFooter = if ($ReportIdentity -and $ReportIdentity.ContainsKey('clientName') -and $ReportIdentity['clientName']) {
            "$($identity.classification) — do not distribute outside $($identity.clientName)"
        } else {
            $identity.classification
        }
    }

    # Root management group's displayName (parent == '') stands in for "tenant display name" --
    # Collect carries no dedicated tenant-name field. Falls back to the first subscription's
    # name, then blank; never throws when governance data wasn't collected.
    $mgRows = @(Get-ReactSafeProp $Collect @('governance', 'managementGroups'))
    $rootMg = $mgRows | Where-Object { $null -ne (Get-ReactRowProp $_ 'parent') -and [string](Get-ReactRowProp $_ 'parent') -eq '' } | Select-Object -First 1
    $tenantDisplayName = if ($rootMg) { Get-ReactRowProp $rootMg 'displayName' }
                          elseif ($subscriptions.Count -gt 0) { Get-ReactRowProp $subscriptions[0] 'name' }
                          else { '' }

    # productName/Version/Url read from the module's own manifest rather than hardcoded, so a
    # version bump or the pending org move (AB#-tracked in the mockup's identity.cjs) is a
    # one-line edit there, not two. Falls back to the mockup's known-good literals if the
    # manifest can't be read standalone (e.g. under Pester without the module imported).
    # Read the manifest that sits beside THIS file first, and only then fall back to a loaded
    # module. Get-Module reports what the session happens to have imported, which is not
    # necessarily the code being executed -- an operator with an older AzureScout still loaded
    # (or several versions available) had the report stamped with that version instead of the
    # one that produced it. The manifest three directories up is the running copy by
    # construction, in both the repo layout and an installed module's layout.
    # There is deliberately NO hardcoded version fallback: a literal here goes stale silently
    # and stamps every report with a lie, which is exactly what a hardcoded '3.3.4' did.
    $manifestPath = Join-Path $PSScriptRoot '../../../AzureScout.psd1'
    $manifestData = try { Import-PowerShellDataFile -Path $manifestPath -ErrorAction Stop } catch { $null }
    $productVersion = if ($manifestData -and $manifestData.ModuleVersion) { $manifestData.ModuleVersion }
                      else {
                          $loaded = Get-Module -Name AzureScout -ErrorAction SilentlyContinue | Select-Object -First 1
                          if ($loaded) { $loaded.Version.ToString() } else { 'unknown' }
                      }
    # Single source of truth: the manifest's own ProjectUri, so the pending org move is one
    # edit in the manifest rather than a literal to hunt for here.
    $productUrl = if ($manifestData -and $manifestData.PrivateData -and
                      $manifestData.PrivateData.PSData -and $manifestData.PrivateData.PSData.ProjectUri) {
                      $manifestData.PrivateData.PSData.ProjectUri
                  } else { 'https://thisismydemo.cloud/azure-scout/' }

    $runId = if ($OutputPath) { Split-Path $OutputPath -Leaf } else { '' }

    $meta = [ordered]@{
        scope              = Get-ReactSafeProp $metaSrc @('scope')
        managementGroupId  = Get-ReactSafeProp $metaSrc @('managementGroupId')
        generatedOn        = (Get-ReactSafeProp $Findings @('GeneratedOn'))
        runId              = $runId
        tenantDisplayName  = $tenantDisplayName
        productName        = 'Azure Scout'
        productVersion     = $productVersion
        productUrl         = $productUrl
        # Lower-cased to match the front end's own state.mode / data-mode vocabulary
        # ('executive'/'consultant'/'data') verbatim -- see report-react.html.template's
        # loadPersisted(), which should prefer this over its current hardcoded 'executive'
        # whenever localStorage has nothing stored yet.
        defaultMode        = $DefaultReportMode.ToLowerInvariant()
    }

    # ---- resourceGroup -> subscriptionId backfill map -------------------------------------------
    # AB#6929 -- built from every ARM-id-bearing evidence row across the WHOLE findings set before
    # any per-finding normalisation runs, so a sibling row that carries a full ARM id can donate
    # its subscription to another row in the SAME resource group that only carries a bare
    # `resourceGroup` name (the majority of the cost-cleanup / NSG-rule / disk shapes -- see the
    # evidence shape catalogue below).
    $rgToSub = @{}
    function Register-ReactRgMapping {
        param([string] $ResourceGroup, [string] $SubscriptionId)
        if ([string]::IsNullOrWhiteSpace($ResourceGroup) -or [string]::IsNullOrWhiteSpace($SubscriptionId)) { return }
        $key = $ResourceGroup.ToLowerInvariant()
        if (-not $rgToSub.ContainsKey($key)) { $rgToSub[$key] = $SubscriptionId }
    }

    # subscription NAME -> id, for evidence shapes that only carry a friendly name (Advisor rows:
    # `Subscription` = "This Is My Demo - MVP Subscription", never a guid).
    $subNameToId = @{}
    foreach ($s in $subscriptions) {
        $sName = Get-ReactRowProp $s 'name'; $sId = Get-ReactRowProp $s 'id'
        if ($sName -and $sId) { $subNameToId[$sName] = $sId }
    }

    # AB#6929 -- a resource NAME -> {resourceId,subscriptionId,resourceGroup} index built once
    # from the WHOLE raw Collect object (not just what happens to appear as evidence). A finding's
    # Evidence is a filtered/failed slice of the estate (e.g. a subnet-utilisation row carries no
    # subscriptionId or resourceGroup at all -- {vnet,subnet,prefix,total,used,ipUtilizationPct}),
    # but the SAME vnet almost always exists elsewhere in Collect (networking.virtualNetworks) WITH
    # both. This closes the gap the evidence-only rg->sub map above cannot: no sibling evidence row
    # ever donates a subscription for a resource group that is never itself named as evidence.
    $collectNameIndex = @{}
    function Add-ReactCollectNameIndexRow {
        param($Row)
        if ($null -eq $Row -or $Row -isnot [pscustomobject]) { return }
        $n = Get-ReactRowProp $Row 'name'
        if (-not $n) { $n = Get-ReactRowProp $Row 'displayName' }
        if (-not $n) { return }
        $rid = Get-ReactRowProp $Row 'id'
        if (-not $rid) { $rid = Get-ReactRowProp $Row 'ResourceId' }
        $sub = Get-ReactRowProp $Row 'subscriptionId'
        if (-not $sub) { $sub = Get-ReactRowProp $Row 'SubscriptionId' }
        if (-not $sub -and $rid) { $sub = Get-ReactArmSubscriptionId $rid }
        $rg = Get-ReactRowProp $Row 'resourceGroup'
        if (-not $rg) { $rg = Get-ReactRowProp $Row 'ResourceGroup' }
        if (-not $rg -and $rid) { $rg = Get-ReactArmResourceGroup $rid }
        if (-not $rid -and -not $sub -and -not $rg) { return }   # nothing worth indexing
        $key = $n.ToLowerInvariant()
        if (-not $collectNameIndex.ContainsKey($key)) {
            $collectNameIndex[$key] = [pscustomobject]@{ ResourceId = $rid; SubscriptionId = $sub; ResourceGroup = $rg }
        }
        Register-ReactRgMapping -ResourceGroup $rg -SubscriptionId $sub
    }
    function Add-ReactCollectNameIndexNode {
        param($Node)
        if ($null -eq $Node) { return }
        if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string] -and $Node -isnot [System.Collections.IDictionary]) {
            foreach ($row in @($Node)) { Add-ReactCollectNameIndexRow -Row $row }
            return
        }
        if ($Node -is [System.Collections.IDictionary]) {
            foreach ($k in $Node.Keys) { Add-ReactCollectNameIndexNode -Node $Node[$k] }
            return
        }
        if ($Node -is [pscustomobject]) {
            foreach ($p in ($Node.PSObject.Properties | Where-Object { $_.Name -ne '_meta' })) { Add-ReactCollectNameIndexNode -Node $p.Value }
        }
    }
    if ($Collect) {
        foreach ($p in ($Collect.PSObject.Properties | Where-Object { $_.Name -ne '_meta' })) {
            Add-ReactCollectNameIndexNode -Node $p.Value
        }
    }

    # A rule-set-generated diagnostic/policy/RBAC COVERAGE row -- exactly {type,total,withDiag,
    # coveragePct} -- names a resource TYPE's coverage, never one resource instance. Excluded from
    # resourceIndex (there is no single resource to click through to) even though its `type`
    # string is still shown as the evidence row's resourceName inside the finding itself.
    function Test-ReactCoverageRow {
        param($Row)
        if ($null -eq $Row -or $Row -isnot [pscustomobject]) { return $false }
        $names = @($Row.PSObject.Properties.Name | Sort-Object)
        return (($names -join ',') -eq 'coveragePct,total,type,withDiag')
    }

    # Flattens one raw evidence row to its identity fields WITHOUT yet resolving the
    # resourceGroup->subscription backfill (that needs the map fully built first, so this is
    # split into a "harvest" pass and a "resolve" pass below).
    function Get-ReactEvidenceIdentity {
        param($Row)
        # Defensive re-normalisation: the caller (ConvertTo-ReactEvidenceList) already converts
        # $Row before calling this, but a JOIN row's OWN Left/Right members are read via
        # Get-ReactRowProp below and must be normalised too -- ConvertFrom-ReactJToken is
        # idempotent (a no-op on an already-native value), so calling it again here costs nothing
        # on the common path and closes the gap on every path that reaches this function directly.
        $Row = ConvertFrom-ReactJToken -Value $Row
        # Cross-resource join rows (Resolve-RuleJoin output): {JoinMode,Key,Left,Right,...}.
        # Prefer Left (the primary side of the join); fall back to Right when Left is $null
        # (a rightOnly join match).
        $joinLeft = ConvertFrom-ReactJToken -Value (Get-ReactRowProp $Row 'Left')
        $joinRight = ConvertFrom-ReactJToken -Value (Get-ReactRowProp $Row 'Right')
        $isJoinRow = $null -ne (Get-ReactRowProp $Row 'JoinMode')
        $identitySource = if ($isJoinRow) { if ($joinLeft) { $joinLeft } else { $joinRight } } else { $Row }

        $name = $null
        foreach ($n in @('name', 'keyVaultName', 'nsg', 'displayName')) {
            $v = Get-ReactRowProp $identitySource $n
            if ($v) { $name = $v; break }
        }
        # Subnet rows carry no `name` at all -- {vnet,subnet,prefix,total,used,ipUtilizationPct}.
        # Checked BEFORE the bare `vnet` fallback below: a row with both `vnet` and `subnet` must
        # resolve to "vnet/subnet", not just "vnet" (which would collide with the vnet's OWN
        # resourceIndex entry and silently merge two different resources).
        if (-not $name) {
            $vnet = Get-ReactRowProp $identitySource 'vnet'; $subnet = Get-ReactRowProp $identitySource 'subnet'
            if ($vnet -and $subnet) { $name = "$vnet/$subnet" }
            elseif ($vnet) { $name = $vnet }
        }
        # Advisor rows: {..., ImpactedValue, ...} names the flagged resource.
        if (-not $name) { $name = Get-ReactRowProp $identitySource 'ImpactedValue' }
        # Diagnostic-coverage summary rows carry no resource identity at all -- {type,total,
        # withDiag,coveragePct} describes a resource TYPE's coverage, not one resource.
        if (-not $name) { $name = Get-ReactRowProp $identitySource 'type' }
        if (-not $name -and $isJoinRow) {
            # Both sides null is not reachable in practice, but degrade to the join Key (an ARM
            # id) rather than an empty string.
            $name = Get-ReactRowProp $Row 'Key'
        }

        $resourceId = $null
        foreach ($n in @('id', 'ResourceId', 'keyVaultId', 'targetResourceId', 'sourceResourceId')) {
            $v = Get-ReactRowProp $identitySource $n
            if ($v) { $resourceId = $v; break }
        }
        if (-not $resourceId -and $isJoinRow) { $resourceId = Get-ReactRowProp $Row 'Key' }

        $subscriptionId = $null
        foreach ($n in @('subscriptionId', 'SubscriptionId')) {
            $v = Get-ReactRowProp $identitySource $n
            if ($v) { $subscriptionId = $v; break }
        }
        if (-not $subscriptionId -and $resourceId) { $subscriptionId = Get-ReactArmSubscriptionId $resourceId }
        if (-not $subscriptionId) {
            $subName = Get-ReactRowProp $identitySource 'Subscription'
            if ($subName -and $subNameToId.ContainsKey($subName)) { $subscriptionId = $subNameToId[$subName] }
        }

        $resourceGroup = $null
        foreach ($n in @('resourceGroup', 'ResourceGroup')) {
            $v = Get-ReactRowProp $identitySource $n
            if ($v) { $resourceGroup = $v; break }
        }
        if (-not $resourceGroup -and $resourceId) { $resourceGroup = Get-ReactArmResourceGroup $resourceId }

        # A subnet row's only identity is its parent vnet's NAME (the row itself carries no
        # subscriptionId/resourceGroup at all) -- consult the whole-Collect name index built above
        # so "vnet-gh-runners-eus2" resolves to the same subscription/resource group the vnet's
        # own inventory row carries, even when no OTHER evidence row for that vnet happens to
        # appear in this findings set. Looked up by the VNET name specifically (not the combined
        # "vnet/subnet" resourceName) -- the index is built from Collect's virtualNetworks list,
        # which is keyed by vnet name alone.
        $lookupName = if ($isJoinRow) { $null } else { Get-ReactRowProp $identitySource 'vnet' }
        if (-not $lookupName) { $lookupName = $name }
        if ((-not $subscriptionId -or -not $resourceGroup -or -not $resourceId) -and $lookupName) {
            $hit = $collectNameIndex[$lookupName.ToLowerInvariant()]
            if ($hit) {
                if (-not $subscriptionId -and $hit.SubscriptionId) { $subscriptionId = $hit.SubscriptionId }
                if (-not $resourceGroup -and $hit.ResourceGroup) { $resourceGroup = $hit.ResourceGroup }
                if (-not $resourceId -and $lookupName -eq $name -and $hit.ResourceId) { $resourceId = $hit.ResourceId }
            }
        }

        [pscustomobject]@{
            ResourceName   = $name
            ResourceId     = $resourceId
            SubscriptionId = $subscriptionId
            ResourceGroup  = $resourceGroup
            Row            = $Row
            IsJoinRow      = $isJoinRow
            JoinLeft       = $joinLeft
            JoinRight      = $joinRight
            IsCoverageRow  = (Test-ReactCoverageRow -Row $identitySource)
        }
    }

    # Builds the human-readable `detail` string from whatever's left on the row after the
    # identity fields are pulled out. Only scalar-typed properties are surfaced -- nested
    # `properties` bags and array-typed fields (e.g. PolicyDefinitionGroupName) are skipped so
    # `detail` stays a short, printable line, not a second copy of the ARM payload.
    $identityFieldNames = @(
        'name', 'id', 'ResourceId', 'resourceId', 'keyVaultId', 'keyVaultName', 'nsg', 'displayName',
        'vnet', 'subnet', 'ImpactedValue', 'type', 'subscriptionId', 'SubscriptionId', 'Subscription',
        'resourceGroup', 'ResourceGroup', 'properties', 'targetResourceId', 'sourceResourceId',
        'Left', 'Right', 'JoinMode', 'Key', 'LeftLabel', 'RightLabel'
    )
    function Get-ReactEvidenceDetail {
        param($Identity)
        if ($Identity.IsJoinRow) {
            $mode = Get-ReactRowProp $Identity.Row 'JoinMode'
            $leftLabel = Get-ReactRowProp $Identity.Row 'LeftLabel'
            $rightLabel = Get-ReactRowProp $Identity.Row 'RightLabel'
            $joinDetail = switch ($mode) {
                'leftOnly'  { "$leftLabel present, no matching $rightLabel" }
                'rightOnly' { "$rightLabel present, no matching $leftLabel" }
                default     { "$leftLabel / $rightLabel ($mode)" }
            }
            return $joinDetail
        }
        $row = $Identity.Row
        $props = if ($row -is [System.Collections.IDictionary]) { $row.Keys } else { $row.PSObject.Properties.Name }
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($n in $props) {
            if ($identityFieldNames -contains $n) { continue }
            $v = Get-ReactRowProp $row $n
            if ($null -eq $v) { continue }
            if ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) { continue }
            if ($v -is [System.Collections.IDictionary] -or ($v.PSObject -and $v.PSObject.TypeNames -contains 'System.Management.Automation.PSCustomObject' -and $v -isnot [string])) { continue }
            [void]$parts.Add("$n=$v")
            if ($parts.Count -ge 6) { break }
        }
        return ($parts -join '; ')
    }

    # A LIVE run's Evidence rows come straight out of Resolve-JsonPath, which is built on the
    # Newtonsoft JSONPath engine and returns Newtonsoft.Json.Linq.JObject/JArray/JValue tokens --
    # NOT deserialized PSCustomObjects. (A run re-read from a written findings.json, as every
    # test/corpus fixture in this repo does, has already round-tripped through ConvertFrom-Json
    # and never hits this path.) Get-ReactRowProp's PSObject.Properties[...] lookup throws on a
    # JObject, so every row is normalised to a plain PSCustomObject/array up front via one JSON
    # round-trip -- cheap relative to the rest of this renderer, and it means every other helper
    # in this file only ever has to reason about one shape.
    function ConvertFrom-ReactJToken {
        param($Value)
        if ($null -eq $Value) { return $null }
        $typeName = $Value.GetType().FullName
        if ($typeName -notlike 'Newtonsoft.Json.Linq.*') { return $Value }
        # AB#6928 (94%-junk-evidence root cause). Branch on .NET's OWN GetType().FullName --
        # 'Newtonsoft.Json.Linq.JObject' / 'JArray' / 'JValue' / 'JProperty' -- NOT Newtonsoft's own
        # `.Type` (JTokenType) property. `$Value.Type` reads as an EMPTY STRING through PowerShell's
        # member adapter for a real JObject (confirmed with a live reproducer: `.Type=` printed
        # blank for a genuine 7-property VM object) -- every JObject/JArray then silently fell into
        # the "not Object/Array" scalar branch below and got sent through `.ToObject([object])`,
        # which for a JObject returns a `System.Object[]`. That `System.Object[]` is exactly the
        # ".NET array metadata" evidence (Length/LongLength/Rank/IsReadOnly/...) the owner's review
        # measured at 94% of all evidence rows on tppoc -- this was never a rare edge case, it was
        # the DEFAULT path for every ordinary evidence row a rule's JSONPath returns. GetType() has
        # been the reliable signal throughout every reproducer used to find this; PowerShell's own
        # type name is unambiguous where Newtonsoft's own enum property is not.
        $typeShortName = $typeName.Substring($typeName.LastIndexOf('.') + 1)
        # A rule whose JSONPath query resolves to a wildcard over an object's OWN properties
        # (rather than array elements) hands Resolve-JsonPath back JProperty tokens -- a bare
        # "name":"pa3" pair, not the whole { name, properties } resource. Wrapping it into a
        # single-key object keeps the rest of the identity-resolution pipeline working (it can
        # still read that one key) instead of throwing on a shape none of it expects.
        if ($typeShortName -eq 'JProperty') {
            $wrapped = [pscustomobject]@{}
            $wrapped | Add-Member -NotePropertyName $Value.Name -NotePropertyValue (ConvertFrom-ReactJToken -Value $Value.Value)
            return $wrapped
        }
        # A scalar leaf (JValue: String/Integer/Boolean/...) is NOT a JSON container -- ToString()
        # on it renders the raw .NET value (e.g. an UNQUOTED string), which is not valid JSON on
        # its own and would make ConvertFrom-Json throw below, silently falling through to the
        # unconverted JToken (the exact bug this function exists to prevent). `.Value` returns the
        # boxed native scalar directly.
        if ($typeShortName -eq 'JValue') { return $Value.Value }
        if ($typeShortName -notin @('JObject', 'JArray')) { return $Value }
        # JObject/JArray: a full JSON round-trip is the one Newtonsoft operation confirmed to
        # produce correct, native PowerShell PSCustomObject/array shapes for these two container
        # types (ToString(Formatting.None) always emits well-formed JSON for a container, unlike
        # a JValue leaf).
        try { return ($Value.ToString([Newtonsoft.Json.Formatting]::None) | ConvertFrom-Json -Depth 100) }
        catch { return $Value }
    }

    # ---- resolve one finding's Evidence into the normalised {resourceName,resourceId,
    # subscriptionId,detail} shape the contract requires, harvesting rg->sub mappings as it goes.
    function ConvertTo-ReactEvidenceList {
        param($RawEvidence)
        $RawEvidence = ConvertFrom-ReactJToken -Value $RawEvidence
        # Evidence is sometimes a bare object instead of an array (a rule that resolved to
        # exactly one match via Resolve-JsonPath's -NoEnumerate contract, or a hand-built
        # fixture) -- wrap it so every caller can iterate uniformly.
        $rows = if ($null -eq $RawEvidence) { @() }
                elseif ($RawEvidence -is [string]) { @() }   # a bare scalar carries no resource identity
                elseif ($RawEvidence -is [System.Collections.IEnumerable]) { @($RawEvidence) }
                else { @($RawEvidence) }

        $out = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach ($row in $rows) {
            $row = ConvertFrom-ReactJToken -Value $row
            if ($null -eq $row) { continue }
            $ident = Get-ReactEvidenceIdentity -Row $row
            Register-ReactRgMapping -ResourceGroup $ident.ResourceGroup -SubscriptionId $ident.SubscriptionId
            $out.Add($ident)
        }
        return $out
    }

    # ---- walk every finding once: normalise evidence, harvest rg->sub map -----------------------
    # Two passes are required because the rg->sub backfill (pass 2) needs the WHOLE map built
    # first -- a row late in the findings list may be the only one that donates a subscription
    # id for a resource group whose other rows appear earlier.
    $normalisedByFindingIndex = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($f in $allFindingsRows) {
        $evList = ConvertTo-ReactEvidenceList -RawEvidence (Get-ReactSafeProp $f @('Evidence'))
        $normalisedByFindingIndex.Add([pscustomobject]@{ Finding = $f; Evidence = $evList })
    }
    foreach ($entry in $normalisedByFindingIndex) {
        foreach ($ident in $entry.Evidence) {
            if (-not $ident.SubscriptionId -and $ident.ResourceGroup) {
                $key = $ident.ResourceGroup.ToLowerInvariant()
                if ($rgToSub.ContainsKey($key)) { $ident.SubscriptionId = $rgToSub[$key] }
            }
        }
    }

    # ---- assessments[] + resourceIndex ----------------------------------------------------------
    $manifest = $null
    try { $manifest = Import-PowerShellDataFile "$PSScriptRoot/../../../manifests/assessments.psd1" } catch { $manifest = $null }

    # ---- learnUrl resolver ------------------------------------------------------------------------
    # AB#6928 follow-up -- ported (not copied verbatim; same precedence, PowerShell-native) from
    # the approved mockup's resolver, D:\tmp\azure-scout-react-mockups\_build\generate.js
    # (CAF_DESIGN_AREAS / WAF_PILLARS / DOMAIN_LINKS / SPECIALTY_LINKS / FINDING_LINK_RULES /
    # classify() / findingLearnLink()). Precedence, most specific first:
    #   1. finding id/title regex override (topic-specific: backup, NSG, private endpoint, ...) --
    #      checked FIRST so a cross-cutting rule (e.g. an XR-* join, or a backup/NSG/PIM finding
    #      that surfaces inside several different assessments) always resolves to the page for
    #      what it's actually ABOUT, not the page for whichever assessment happened to run it.
    #   2. the assessment's own slug -- CAF design area / WAF pillar / domain / specialty map.
    #   3. a framework-level root (CAF or WAF design-areas index) -- NEVER an unrelated topic.
    # Every URL below is either one `scripts/Test-ScoutGuidanceLinks.ps1` already audits live
    # (AB#6913 — 26 URLs verified), or a well-known top-level Learn product/service root. Rule #1
    # learned from that same audit: a rule file's OWN cited URL can 404 even after being marked
    # "verified" (Microsoft renames pages) -- this curated map is the source of truth, not a blind
    # pass-through of whatever a rule file cites.
    $cafDesignAreaLinks = @{
        'caf-azure-billing-and-microsoft-entra-tenant' = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas'
        'caf-identity-and-access-management'           = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas'
        'caf-resource-organization'                    = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas'
        'caf-network-topology-and-connectivity'        = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas'
        'caf-governance'                               = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/governance'
        'caf-security'                                 = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/security'
        'caf-management'                               = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas'
        'caf-platform-automation-and-devops'           = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas'
    }
    $wafPillarLinks = @{
        'waf-reliability'            = 'https://learn.microsoft.com/azure/well-architected/reliability/'
        'waf-security'               = 'https://learn.microsoft.com/azure/well-architected/security/'
        'waf-cost-optimization'      = 'https://learn.microsoft.com/azure/well-architected/cost-optimization/'
        'waf-operational-excellence' = 'https://learn.microsoft.com/azure/well-architected/operational-excellence/'
        'waf-performance-efficiency' = 'https://learn.microsoft.com/azure/well-architected/performance-efficiency/'
        'waf-maturity-model'         = 'https://learn.microsoft.com/azure/well-architected/'
    }
    $domainLinks = @{
        'assess-ai'            = 'https://learn.microsoft.com/azure/ai-services/'
        'assess-ai-workload'   = 'https://learn.microsoft.com/azure/well-architected/ai/'
        'assess-analytics'     = 'https://learn.microsoft.com/azure/cloud-adoption-framework/scenarios/data-management/'
        'assess-avd-workload'  = 'https://learn.microsoft.com/azure/architecture/landing-zones/azure-virtual-desktop/design-guide'
        'assess-cloud-governance' = 'https://learn.microsoft.com/azure/cloud-adoption-framework/govern/'
        'assess-compliance'    = 'https://learn.microsoft.com/azure/governance/policy/overview'
        'assess-compute'       = 'https://learn.microsoft.com/azure/architecture/framework/services/compute/'
        'assess-containers'    = 'https://learn.microsoft.com/azure/aks/best-practices'
        'assess-databases'     = 'https://learn.microsoft.com/azure/architecture/framework/services/data/'
        'assess-hybrid'        = 'https://learn.microsoft.com/azure/azure-arc/overview'
        'assess-identity'      = 'https://learn.microsoft.com/entra/fundamentals/'
        'assess-integration'   = 'https://learn.microsoft.com/azure/architecture/framework/services/messaging/'
        'assess-iot'           = 'https://learn.microsoft.com/azure/iot/iot-introduction'
        'assess-management'    = 'https://learn.microsoft.com/azure/cloud-adoption-framework/manage/'
        'assess-monitor'       = 'https://learn.microsoft.com/azure/azure-monitor/overview'
        'assess-networking'    = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas'
        'assess-security'      = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/security'
        'assess-storage'       = 'https://learn.microsoft.com/azure/storage/common/storage-introduction'
        'assess-web'           = 'https://learn.microsoft.com/azure/app-service/overview'
    }
    $specialtyLinks = @{
        # Old (pre-namespace) slugs kept beside the new ones -- a payload rendered from an
        # older run's findings still carries the old assessment names.
        'cost'                            = 'https://learn.microsoft.com/azure/well-architected/cost-optimization/'
        'scout-cost-optimization'         = 'https://learn.microsoft.com/azure/well-architected/cost-optimization/'
        'crossresource'                   = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas'
        'scout-cross-resource'            = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas'
        'devops-capability-assessment'    = 'https://learn.microsoft.com/azure/devops/'
        'microsoft-devops-capability'     = 'https://learn.microsoft.com/azure/devops/'
        'finops-review'                   = 'https://learn.microsoft.com/azure/cost-management-billing/finops/overview-finops'
        'microsoft-finops-review'         = 'https://learn.microsoft.com/azure/cost-management-billing/finops/overview-finops'
        'governance'                      = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/governance'
        'scout-governance-baseline'       = 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/governance'
        'monitoring'                      = 'https://learn.microsoft.com/azure/azure-monitor/overview'
        'scout-monitoring-baseline'       = 'https://learn.microsoft.com/azure/azure-monitor/overview'
        'smart'                           = 'https://learn.microsoft.com/azure/migrate/migrate-services-overview'
        'microsoft-smart-migration'       = 'https://learn.microsoft.com/azure/migrate/migrate-services-overview'
        'updatemanager'                   = 'https://learn.microsoft.com/azure/update-manager/overview'
        'scout-update-manager'            = 'https://learn.microsoft.com/azure/update-manager/overview'
    }
    # Finding id/title overrides -- ordered list, first match wins. Checked BEFORE the
    # assessment-level map (see precedence note above).
    $findingLinkRules = [System.Collections.Generic.List[pscustomobject]]::new()
    $findingLinkRuleDefs = @(
        @{ p = '^XR-BKP'; u = 'https://learn.microsoft.com/azure/backup/backup-overview' }
        @{ p = '^XR-STO'; u = 'https://learn.microsoft.com/azure/storage/common/storage-private-endpoints' }
        @{ p = '^XR-KV'; u = 'https://learn.microsoft.com/azure/key-vault/general/private-link-service' }
        @{ p = '^/providers/microsoft\.authorization/policydefinitions/'; u = 'https://learn.microsoft.com/azure/governance/policy/overview' }
        @{ p = '^CAF-STO|^WAF-STO'; u = 'https://learn.microsoft.com/azure/storage/common/storage-introduction' }
        @{ p = '^CAF-DB'; u = 'https://learn.microsoft.com/azure/architecture/framework/services/data/' }
        @{ p = '^CAF-CON'; u = 'https://learn.microsoft.com/azure/aks/best-practices' }
        @{ p = '^CAF-HYB'; u = 'https://learn.microsoft.com/azure/azure-arc/overview' }
        @{ p = '^CAF-ANL'; u = 'https://learn.microsoft.com/azure/cloud-adoption-framework/scenarios/data-management/' }
        @{ p = '^CAF-AI'; u = 'https://learn.microsoft.com/azure/ai-services/' }
        @{ p = '^WAF-AI'; u = 'https://learn.microsoft.com/azure/well-architected/ai/' }
        @{ p = '^WAF-AVD'; u = 'https://learn.microsoft.com/azure/architecture/landing-zones/azure-virtual-desktop/design-guide' }
        @{ p = '^WAF-AZLOCAL'; u = 'https://learn.microsoft.com/azure/azure-local/' }
        @{ p = '^DEVOPS-'; u = 'https://learn.microsoft.com/azure/devops/' }
        @{ p = '^FINOPS-'; u = 'https://learn.microsoft.com/azure/cost-management-billing/finops/overview-finops' }
        @{ p = '^CGOV-'; u = 'https://learn.microsoft.com/azure/cloud-adoption-framework/govern/' }
        @{ p = '^SMART-'; u = 'https://learn.microsoft.com/azure/migrate/migrate-services-overview' }
        @{ p = '^CASA-'; u = 'https://learn.microsoft.com/security/' }
        @{ p = 'nsg rule|unrestricted.*inbound|inbound exposure'; u = 'https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview' }
        @{ p = 'private endpoint'; u = 'https://learn.microsoft.com/azure/private-link/private-endpoint-overview' }
        @{ p = 'private dns zone'; u = 'https://learn.microsoft.com/azure/dns/private-dns-privatednszone' }
        @{ p = 'backup'; u = 'https://learn.microsoft.com/azure/backup/backup-overview' }
        @{ p = 'diagnostic setting'; u = 'https://learn.microsoft.com/azure/azure-monitor/essentials/diagnostic-settings' }
        @{ p = 'log analytics'; u = 'https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-workspace-overview' }
        @{ p = 'purview'; u = 'https://learn.microsoft.com/purview/purview' }
        @{ p = 'pim|privileged identity'; u = 'https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-configure' }
    )
    foreach ($def in $findingLinkRuleDefs) {
        [void]$findingLinkRules.Add([pscustomobject]@{ Pattern = [regex]::new($def.p, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase); Url = $def.u })
    }

    # Per-assessment fallback link -- mirrors generate.js's classify(). Never a topic-unrelated
    # default: an unrecognised slug lands on the CAF design-areas INDEX (a real, on-topic landing
    # zone page), not a cost-management or other specialty page (the exact wrong-fallback class
    # the owner's team already hit once and corrected in the mockup).
    function Get-ReactAssessmentLearnUrl {
        param([string] $Slug)
        if ($Slug -in @('landingzone', 'caf-azure-landing-zone')) { return 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/' }
        if ($cafDesignAreaLinks.ContainsKey($Slug)) { return $cafDesignAreaLinks[$Slug] }
        if ($wafPillarLinks.ContainsKey($Slug)) { return $wafPillarLinks[$Slug] }
        if ($domainLinks.ContainsKey($Slug)) { return $domainLinks[$Slug] }
        if ($Slug -like 'avs-*' -or $Slug -like 'workload-avs*') { return 'https://learn.microsoft.com/azure/azure-vmware/' }
        if ($Slug -in @('casa', 'microsoft-casa')) { return 'https://learn.microsoft.com/security/' }
        if ($specialtyLinks.ContainsKey($Slug)) { return $specialtyLinks[$Slug] }
        return 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas'
    }
    function Get-ReactFindingLearnUrl {
        param([string] $Id, [string] $Title, [string] $AssessmentSlug)
        $haystack = (@($Id, $Title) | Where-Object { $_ }) -join ' '
        foreach ($rule in $findingLinkRules) {
            if ($rule.Pattern.IsMatch($haystack)) { return $rule.Url }
        }
        return Get-ReactAssessmentLearnUrl -Slug $AssessmentSlug
    }

    $sevRank = @{ high = 0; medium = 1; low = 2 }
    $resourceIndex = [ordered]@{}
    function Add-ReactResourceIndexEntry {
        param([string] $ResourceName, $Identity, [string] $Category, [string] $FindingId)
        if ([string]::IsNullOrWhiteSpace($ResourceName)) { return }
        # Coverage-by-type aggregate rows are not a resource -- see Test-ReactCoverageRow. They
        # still render inside the finding's own evidence list (resourceName = the type string);
        # they just never become a clickable entry in the global index.
        if ($Identity.IsCoverageRow) { return }
        if (-not $resourceIndex.Contains($ResourceName)) {
            $resourceIndex[$ResourceName] = [ordered]@{
                resourceId     = $Identity.ResourceId
                subscriptionId = $Identity.SubscriptionId
                resourceGroup  = $Identity.ResourceGroup
                category       = $Category
                findingIds     = [System.Collections.Generic.List[string]]::new()
            }
        }
        $entry = $resourceIndex[$ResourceName]
        # A resource named identically in two evidence rows keeps whichever identity fields it
        # already has; only fill gaps, never overwrite a known id with a blank one.
        if (-not $entry.resourceId -and $Identity.ResourceId) { $entry.resourceId = $Identity.ResourceId }
        if (-not $entry.subscriptionId -and $Identity.SubscriptionId) { $entry.subscriptionId = $Identity.SubscriptionId }
        if (-not $entry.resourceGroup -and $Identity.ResourceGroup) { $entry.resourceGroup = $Identity.ResourceGroup }
        if (-not $entry.findingIds.Contains($FindingId)) { [void]$entry.findingIds.Add($FindingId) }
    }

    # Group by the `Assessment` property Invoke-Assessment stamps onto every finding. A merged
    # (run-root) findings set carries several distinct Assessment values; a per-assessment folder
    # render carries exactly one -- the same grouping logic handles both without a branch.
    $findingsByAssessment = [ordered]@{}
    for ($i = 0; $i -lt $allFindingsRows.Count; $i++) {
        $f = $allFindingsRows[$i]
        # Every finding-producing path (Invoke-Assessment's rule-set loop, its benchmark-compare
        # branch, Invoke-ScoutComplianceAssessment) stamps Assessment today -- see Invoke-
        # Assessment.ps1's own fix for the benchmark branch, which used to leave ALZ findings
        # unstamped and rendered as a nameless 0%-scoring "(unassigned)" card next to the real
        # assessments (found visually on the executive view, AB#6929 follow-up). This fallback is
        # a defensive backstop only, not an expected bucket -- named honestly rather than blank so
        # a future finding-building path that forgets to stamp Assessment still reads as "some
        # checks ran outside a named assessment", never as a mystery zero.
        $assessmentName = Get-ReactSafeProp $f @('Assessment')
        if (-not $assessmentName) { $assessmentName = 'Unassigned checks' }
        if (-not $findingsByAssessment.Contains($assessmentName)) { $findingsByAssessment[$assessmentName] = [System.Collections.Generic.List[int]]::new() }
        [void]$findingsByAssessment[$assessmentName].Add($i)
    }

    $assessments = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($assessmentName in $findingsByAssessment.Keys) {
        $idxList = $findingsByAssessment[$assessmentName]
        $assessmentFindingRows = @($idxList | ForEach-Object { $allFindingsRows[$_] })

        $slug = ($assessmentName.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
        $spec = if ($manifest -and $manifest.ContainsKey($assessmentName)) { $manifest[$assessmentName] } else { $null }
        $frameworkLabel = if ($spec -and $spec.ContainsKey('Frameworks') -and $spec.Frameworks) { ($spec.Frameworks -join ' + ') }
                          else { (($assessmentFindingRows | ForEach-Object { $_.Framework } | Where-Object { $_ } | Select-Object -Unique) -join ' + ') }
        $category = if ($spec -and $spec.ContainsKey('Category')) { $spec.Category } else { $null }

        # Per-assessment area buckets, tallied INLINE from this assessment's slice of the
        # already-scored findings (each row carries Framework/Area/Status/Weight). The run-wide
        # $Findings.Areas would be wrong the moment two assessments render together in one
        # merged run -- and re-invoking the scoring engine here is exactly the renderer drift
        # conformance clause R-04 bans, so the grouping is a plain count over scored rows: no
        # finding is re-derived, no status is re-decided, and the percent arithmetic below is
        # the same visible formula the rest of this payload already uses.
        # AB#6938 -- ALZ benchmark findings (Compare-Benchmark's BENCH-MG-*/BENCH-POL-*) are
        # EXCLUDED from the area-scoring tally below. Without this, BENCH-POL-* rows (Area =
        # 'Governance (policy & compliance)') silently blend into the caf.governance design
        # area's OWN scorecard -- the exact "merged silently into the CAF chapters" defect the
        # acceptance criteria calls out -- and BENCH-MG-* rows (Area = 'Management group &
        # subscription org', which no caf.*.yaml design area claims) would otherwise surface as
        # a phantom 9th "design area" chapter indistinguishable from the real eight. The
        # benchmark's own tally is computed separately just below and rendered by the template
        # as its own named section. `findingsOut` (built further down) still carries every
        # BENCH-* finding untouched -- exports and the register keep seeing them; only the
        # per-design-area SCORE stops counting them.
        $benchFindingRows = @($assessmentFindingRows | Where-Object { $_.Id -like 'BENCH-*' })
        $scorableFindingRows = @($assessmentFindingRows | Where-Object { $_.Id -notlike 'BENCH-*' })

        $areaBuckets = [ordered]@{}
        foreach ($row in $scorableFindingRows) {
            $rowFramework = Get-ReactSafeProp $row @('Framework')
            $bKey = '{0}|{1}' -f $rowFramework, (Get-ReactSafeProp $row @('Area'))
            if (-not $areaBuckets.Contains($bKey)) {
                $areaWeight = Get-ReactSafeProp $row @('AreaWeight')
                if ($null -eq $areaWeight) { $areaWeight = 1.0 }
                $areaBuckets[$bKey] = [pscustomobject]@{
                    Area      = (Get-ReactSafeProp $row @('Area'))
                    Framework = $rowFramework
                    Pass = 0; Partial = 0; Fail = 0; Manual = 0; Unknown = 0; Error = 0; NotAssessed = 0
                    Score = $null; Weight = [double]$areaWeight
                }
            }
            $b = $areaBuckets[$bKey]
            switch ([string](Get-ReactSafeProp $row @('Status'))) {
                'Pass'        { $b.Pass++ }
                'Partial'     { $b.Partial++ }
                'Fail'        { $b.Fail++ }
                'Manual'      { $b.Manual++ }
                'Error'       { $b.Error++ }
                'NotAssessed' { $b.NotAssessed++ }
                default       { $b.Unknown++ }
            }
        }
        foreach ($b in $areaBuckets.Values) {
            $bDen = $b.Pass + $b.Partial + $b.Fail
            if ($bDen -gt 0) {
                $b.Score = [math]::Round(($b.Pass + (0.5 * $b.Partial)) / $bDen * 100, 0, [System.MidpointRounding]::AwayFromZero)
            }
        }

        $areas = [System.Collections.Generic.List[pscustomobject]]::new()
        $totalPass = 0; $totalPartial = 0; $totalFail = 0; $totalManual = 0; $totalUnknown = 0; $totalError = 0; $totalNotAssessed = 0; $totalWeight = 0.0
        foreach ($a in @($areaBuckets.Values)) {
            $den = $a.Pass + $a.Partial + $a.Fail
            $num = $a.Pass + (0.5 * $a.Partial)
            $excluded = $a.Manual + $a.Unknown + $a.Error + $a.NotAssessed
            $formula = if ($den -gt 0) {
                "($($a.Pass) pass + 0.5×$($a.Partial) partial) / $den automated = $($a.Score)%; $excluded excluded (manual/not-assessed)"
            } else {
                "No automated checks scored in this area; $excluded manual/not-assessed."
            }
            $areas.Add([pscustomobject]@{
                name          = $a.Area
                framework     = $a.Framework
                percent       = $a.Score
                numerator     = $num
                denominator   = $den
                weight        = $a.Weight
                excludedCount = $excluded
                formula       = $formula
            })
            $totalPass += $a.Pass; $totalPartial += $a.Partial; $totalFail += $a.Fail
            $totalManual += $a.Manual; $totalUnknown += $a.Unknown; $totalError += $a.Error; $totalNotAssessed += $a.NotAssessed
            $totalWeight += [double]$a.Weight
        }
        $automatedCheckCount = $totalPass + $totalPartial + $totalFail
        $scoredAreas = @($areaBuckets.Values | Where-Object { $null -ne $_.Score })
        $scoreDen = ($scoredAreas | ForEach-Object { [double]$_.Weight } | Measure-Object -Sum).Sum
        $scoreNum = ($scoredAreas | ForEach-Object { [double]$_.Score * [double]$_.Weight } | Measure-Object -Sum).Sum
        $scoreExcluded = $totalManual + $totalUnknown + $totalError + $totalNotAssessed
        $scorePercent = if ($scoreDen -gt 0) { [math]::Round($scoreNum / $scoreDen, 0, [System.MidpointRounding]::AwayFromZero) } else { $null }
        $scoreFormula = if ($scoreDen -gt 0) {
            "Weighted average of $($scoredAreas.Count) area scores ($scoreNum weighted points / $scoreDen total weight) = $scorePercent%; $automatedCheckCount automated checks scored and $scoreExcluded of $($assessmentFindingRows.Count) checks excluded (manual/not-assessed)"
        } else {
            "No automated checks scored in this assessment; $scoreExcluded of $($assessmentFindingRows.Count) checks are manual/not-assessed."
        }
        $excludedReason = ''
        if ($automatedCheckCount -eq 0 -and $assessmentFindingRows.Count -gt 0) {
            $unknownRow = $assessmentFindingRows | Where-Object { $_.Status -eq 'Unknown' } | Select-Object -First 1
            if ($unknownRow) { $excludedReason = [string]$unknownRow.Remediation }
        }

        # AB#6938 -- the ALZ benchmark's own scorecard, tallied separately from the eight CAF
        # design-area scorecards above (same pass/partial/fail-weighted formula, so the two
        # never disagree about arithmetic, just about what they're arithmetic OVER). $null when
        # this assessment produced no BENCH-* findings at all (every non-LandingZone assessment,
        # and LandingZone itself when Compare-Benchmark short-circuited on BENCH-GOV-DATA), so
        # the template only renders the section when there is something real to show.
        $benchmark = $null
        if ($benchFindingRows.Count -gt 0) {
            $bmPass = @($benchFindingRows | Where-Object Status -eq 'Pass').Count
            $bmFail = @($benchFindingRows | Where-Object Status -eq 'Fail').Count
            $bmManual = @($benchFindingRows | Where-Object Status -eq 'Manual').Count
            $bmUnknown = @($benchFindingRows | Where-Object { $_.Status -in 'Unknown', 'Error', 'NotAssessed' }).Count
            $bmDen = $bmPass + $bmFail
            $bmPercent = if ($bmDen -gt 0) { [math]::Round($bmPass / $bmDen * 100, 0, [System.MidpointRounding]::AwayFromZero) } else { $null }
            $bmFormula = if ($bmDen -gt 0) {
                "$bmPass pass / $bmDen assessed = $bmPercent%; $($bmManual + $bmUnknown) of $($benchFindingRows.Count) excluded (manual/not-assessed)."
            } else {
                "No ALZ benchmark check could be assessed ($($bmUnknown) unknown) -- governance data was likely unavailable for this run."
            }
            $benchmark = [pscustomobject]@{
                label   = 'ALZ benchmark conformance'
                percent = $bmPercent
                pass    = $bmPass
                fail    = $bmFail
                manual  = $bmManual
                unknown = $bmUnknown
                total   = $benchFindingRows.Count
                formula = $bmFormula
            }
        }

        # Area weight, denormalised onto each finding below (AB#6928 follow-up). The scoring
        # engine already uses per-area weight internally (Get-Score's AreaWeight); Microsoft's own
        # WAF export surfaces it on every recommendation row so a reader can see why one finding
        # moves the score more than another sitting in a lower-weighted area. Looked up by area
        # NAME rather than re-deriving it, since $areas above is already the authoritative
        # per-area weight for this assessment.
        $areaWeightByKey = @{}
        foreach ($areaEntry in $areas) {
            $areaWeightByKey['{0}|{1}' -f $areaEntry.framework, $areaEntry.name] = $areaEntry.weight
        }

        $findingsOut = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach ($i in $idxList) {
            $f = $allFindingsRows[$i]
            $compositeId = "${slug}:$($f.Id)"
            $evNorm = $normalisedByFindingIndex[$i].Evidence
            $evidenceOut = @($evNorm | ForEach-Object {
                [pscustomobject]@{
                    resourceName   = $_.ResourceName
                    resourceId     = $_.ResourceId
                    subscriptionId = $_.SubscriptionId
                    detail         = Get-ReactEvidenceDetail -Identity $_
                }
            })
            foreach ($ident in $evNorm) {
                if ($ident.ResourceName) { Add-ReactResourceIndexEntry -ResourceName $ident.ResourceName -Identity $ident -Category $category -FindingId $compositeId }
            }
            $findingAreaKey = '{0}|{1}' -f (Get-ReactSafeProp $f @('Framework')), $f.Area
            $findingWeight = if ($areaWeightByKey.ContainsKey($findingAreaKey)) {
                $areaWeightByKey[$findingAreaKey]
            }
            else {
                $declaredWeight = Get-ReactSafeProp $f @('AreaWeight')
                if ($null -eq $declaredWeight) { 1.0 } else { [double]$declaredWeight }
            }
            $findingsOut.Add([pscustomobject]@{
                id            = $compositeId
                title         = $f.Title
                severity      = $f.Severity
                status        = $f.Status
                area          = $f.Area
                framework     = (Get-ReactSafeProp $f @('Framework'))
                remediation   = $f.Remediation
                learnUrl      = (Get-ReactFindingLearnUrl -Id $f.Id -Title $f.Title -AssessmentSlug $slug)
                # AB#6928 follow-up -- the area's own weight, denormalised here so the CSV export
                # (and any other per-finding view) can show it without a separate lookup against
                # `areas[]`. $null when the finding's area carries no explicit weight (Get-Score's
                # own 1.0 default applies at the SCORING layer; this field reports exactly what
                # that area object already carries, not a re-guessed default).
                weight        = $findingWeight
                evidenceCount = (Get-ReactSafeProp $f @('EvidenceCount'))
                evidenceTruncated = [bool](Get-ReactSafeProp $f @('EvidenceTruncated'))
                evidence      = $evidenceOut
            })
        }
        # Fails first, weighted by severity; unknown/missing severity sorts LAST -- mirrors
        # Get-Score's own Gaps ordering so the two never disagree about priority.
        $findingsOut = @($findingsOut | Sort-Object `
            @{ Expression = { if ($_.status -eq 'Fail') { 0 } else { 1 } } }, `
            @{ Expression = { if ($_.severity -and $sevRank.ContainsKey($_.severity)) { $sevRank[$_.severity] } else { 99 } } })

        $assessments.Add([pscustomobject]@{
            slug       = $slug
            name       = $assessmentName
            framework  = $frameworkLabel
            scope      = [pscustomobject]@{
                subscriptionsInScope = $subscriptions.Count
                checksTotal          = $assessmentFindingRows.Count
                checksAutomated      = $automatedCheckCount
                checksManual         = $totalManual
                checksNotAssessed    = ($totalNotAssessed + $totalUnknown + $totalError)
                excludedReason       = $excludedReason
            }
            score      = [pscustomobject]@{
                percent       = $scorePercent
                numerator     = $scoreNum
                denominator   = $scoreDen
                weight        = $totalWeight
                excludedCount = $scoreExcluded
                formula       = $scoreFormula
            }
            areas      = @($areas)
            benchmark  = $benchmark
            findings   = $findingsOut
        })
    }

    # ---- inventory{} -----------------------------------------------------------------------------
    # Generic recursive walker over $Collect: every array found (at any depth) becomes its own
    # inventory category keyed by its dotted path, so a category added to Collect tomorrow shows
    # up here with no renderer change. `_meta` is the only excluded branch (run metadata, not
    # inventory). Rows are capped so one enormous category (policy compliance can run into the
    # thousands) doesn't bloat the embedded payload; `truncated` records the honest shown/actual
    # split so the UI never presents a cap as a total (AB#6864's own rule, applied here too).
    $inventoryRowCap = 300
    function Get-ReactInventoryLabel {
        param([string[]] $PathSegments)
        $titled = $PathSegments | ForEach-Object {
            # camelCase / PascalCase -> spaced Title Case: "virtualNetworks" -> "Virtual Networks".
            ($_ -creplace '([a-z0-9])([A-Z])', '$1 $2') -replace '^(.)', { $_.Value.ToUpperInvariant() }
        }
        return ($titled -join ' → ')
    }
    $inventory = [ordered]@{}
    function Add-ReactInventoryCategory {
        param($Node, [string[]] $PathSegments)
        if ($null -eq $Node) { return }
        if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string] -and $Node -isnot [System.Collections.IDictionary]) {
            $rows = @($Node)
            $key = ($PathSegments -join '.')
            $shown = @($rows | Select-Object -First $inventoryRowCap)
            $inventory[$key] = [ordered]@{
                label     = Get-ReactInventoryLabel -PathSegments $PathSegments
                count     = $rows.Count
                rows      = $shown
                truncated = if ($rows.Count -gt $inventoryRowCap) { [pscustomobject]@{ shown = $shown.Count; actual = $rows.Count } } else { $null }
            }
            return
        }
        if ($Node -is [System.Collections.IDictionary]) {
            foreach ($k in $Node.Keys) { Add-ReactInventoryCategory -Node $Node[$k] -PathSegments ($PathSegments + [string]$k) }
            return
        }
        $props = $Node.PSObject.Properties | Where-Object { $_.Name -ne '_meta' }
        foreach ($p in $props) { Add-ReactInventoryCategory -Node $p.Value -PathSegments ($PathSegments + $p.Name) }
    }
    if ($Collect) {
        foreach ($p in ($Collect.PSObject.Properties | Where-Object { $_.Name -ne '_meta' })) {
            Add-ReactInventoryCategory -Node $p.Value -PathSegments @($p.Name)
        }
    }

    # ---- costProjection{} -------------------------------------------------------------------------
    # AB#7093: a transparent trailing-30-day run-rate extrapolation over finops.costRows (the same
    # rows Import-ScoutCostInventory already ingests from Get-ScoutCostInventory/Cost Management).
    # Deliberately the simplest extrapolation that is still honest about its own math -- no seasonal
    # adjustment, no trend line -- and its `formula` string is shown verbatim, the same
    # arithmetic-visible convention the score/area formulas above already use: never a bare number.
    $finopsCostRows = @(Get-ReactSafeProp $Collect @('finops', 'costRows'))
    $finopsAvailableFlag = Get-ReactSafeProp $Collect @('finops', 'available')
    $parsedCostRows = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($row in $finopsCostRows) {
        if (-not $row) { continue }
        $rawDate = Get-ReactSafeProp $row @('UsageDate')
        $rawCost = Get-ReactSafeProp $row @('Cost')
        if ($null -eq $rawDate -or $null -eq $rawCost) { continue }
        $parsedDate = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$rawDate, [ref]$parsedDate)) { continue }
        $parsedCost = $null
        try { $parsedCost = [double]$rawCost } catch { continue }
        [void]$parsedCostRows.Add([pscustomobject]@{
                Date     = $parsedDate
                Cost     = $parsedCost
                Currency = Get-ReactSafeProp $row @('Currency')
            })
    }

    if ($parsedCostRows.Count -gt 0) {
        $anchorDate = @($parsedCostRows | Sort-Object Date -Descending)[0].Date
        $windowStart = $anchorDate.AddDays(-29)
        $trailingRows = @($parsedCostRows | Where-Object { $_.Date -ge $windowStart -and $_.Date -le $anchorDate })
        $trailingTotal = 0.0
        foreach ($tr in $trailingRows) { $trailingTotal += $tr.Cost }
        $trailingTotal = [math]::Round($trailingTotal, 2)
        $dailyRunRate = [math]::Round($trailingTotal / 30, 2)
        $monthlyProjection = [math]::Round($dailyRunRate * 30, 2)
        $yearlyProjection = [math]::Round($monthlyProjection * 12, 2)
        $costCurrencies = @($trailingRows | ForEach-Object { $_.Currency } | Where-Object { $_ } | Sort-Object -Unique)
        if ($costCurrencies.Count -gt 1) {
            $costProjection = [pscustomobject]@{
                available      = $false
                currency       = $null
                trailingDays   = 30
                windowStart    = $windowStart.ToString('yyyy-MM-dd')
                windowEnd      = $anchorDate.ToString('yyyy-MM-dd')
                rowsConsidered = $trailingRows.Count
                trailingTotal  = $null
                dailyRunRate   = $null
                monthly        = $null
                yearly         = $null
                formula        = "Cost projection was withheld because the trailing window contains multiple currencies: $($costCurrencies -join ', '). Convert them to one currency or review each currency separately."
            }
        }
        else {
            $costCurrency = if ($costCurrencies.Count -eq 1) { $costCurrencies[0] } else { $null }
            $costProjection = [pscustomobject]@{
            available      = $true
            currency       = $costCurrency
            trailingDays   = 30
            windowStart    = $windowStart.ToString('yyyy-MM-dd')
            windowEnd      = $anchorDate.ToString('yyyy-MM-dd')
            rowsConsidered = $trailingRows.Count
            trailingTotal  = $trailingTotal
            dailyRunRate   = $dailyRunRate
            monthly        = $monthlyProjection
            yearly         = $yearlyProjection
            formula        = "Trailing 30 days ($($windowStart.ToString('yyyy-MM-dd')) to $($anchorDate.ToString('yyyy-MM-dd'))), $($trailingRows.Count) cost row(s): total $trailingTotal ÷ 30 days = $dailyRunRate/day; ×30 = $monthlyProjection monthly; ×12 = $yearlyProjection yearly. Simple trailing run-rate extrapolation, not a seasonally-adjusted forecast."
            }
        }
    }
    else {
        $unavailableReason =
            if ($null -eq (Get-ReactSafeProp $Collect @('finops'))) {
                'This run did not collect cost data (finops was not populated).'
            } elseif ($finopsAvailableFlag -eq $false) {
                'Cost Management data was not available for this run (module missing, or the identity lacked Cost Management Reader rights on every queried subscription) -- see finops.blockedSubscriptions.'
            } else {
                'Cost Management returned zero cost rows for the queried period.'
            }
        $costProjection = [pscustomobject]@{
            available      = $false
            currency       = $null
            trailingDays   = 30
            windowStart    = $null
            windowEnd      = $null
            rowsConsidered = 0
            trailingTotal  = $null
            dailyRunRate   = $null
            monthly        = $null
            yearly         = $null
            formula        = $unavailableReason
        }
    }

    # ---- assemble + write ------------------------------------------------------------------------
    $payload = [ordered]@{
        identity       = $identity
        meta           = $meta
        ran            = $ran
        inventory      = $inventory
        subscriptions  = @($subscriptions | ForEach-Object {
            [pscustomobject]@{ id = (Get-ReactRowProp $_ 'id'); name = (Get-ReactRowProp $_ 'name'); state = (Get-ReactRowProp $_ 'state') }
        })
        assessments    = @($assessments)
        resourceIndex  = $resourceIndex
        drift          = $Drift
        costProjection = $costProjection
    }

    # </script> inside embedded JSON would otherwise close the <script> tag early.
    $json = ($payload | ConvertTo-Json -Depth 100) -replace '</', '<\/'

    $tplPath = "$PSScriptRoot/../templates/report-react.html.template"
    $tpl = Get-Content $tplPath -Raw
    $html = $tpl.Replace('/*__SCOUT_DATA__*/', $json)

    $outFile = Join-Path $OutputPath 'report-react.html'
    $html | Out-File $outFile -Encoding utf8

    return $outFile
}

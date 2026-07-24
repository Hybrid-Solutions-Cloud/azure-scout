#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Compare discovered Azure resources (from collect.json) against a folder of
    Bicep/ARM-JSON templates and report resources that exist in Azure but are
    NOT represented in the templates (drift-from-IaC / unmanaged resources).
    Never calls Azure.

.DESCRIPTION
    Two independent, best-effort steps:

      1. Discovery flattening — `-CollectData` accepts either the canonical
         collect.json object (src/collect/Invoke-Collect.ps1's shape:
         networking/compute/management/governance/domains.* sections) or an
         already-flattened array of `{ Type, Name, ResourceGroup }`-shaped
         objects. A static section->ARM-type map (copied from Invoke-Collect's
         own KQL `type =~ "..."` filters, so it matches the real ARM types the
         collector queries) is used to flatten the nested shape; deployment
         records, subscription-level settings and rule-level sub-collections
         (subnets, nsgPublicInbound) are deliberately excluded — see
         LIMITATIONS.

      2. Template parsing — every `.bicep`/`.json` file under `-TemplatePath`
         (recursively) is parsed BEST-EFFORT as text/JSON (no `bicep build`,
         no external dependency):
           - Bicep: `resource <symbolicName> '<type>@<apiVersion>' = ...`
             declarations are found by regex; the resource's literal `name:`
             value (if it is a plain quoted string, not an expression/
             parameter/interpolation) is read from the text immediately
             following the declaration.
           - ARM JSON: `resources[].type`/`.name` are read directly; a `name`
             value that is an ARM template expression (`"[...]"`) is treated
             as unresolved, same as an unresolvable Bicep name.

      Discovered resources are matched to template resources on
      (normalized-lowercase Type, normalized-lowercase Name). A discovered
      resource with no matching template entry is reported as `Unmanaged` —
      annotated with whether the TYPE at least appears somewhere in the
      template set (a parameter-driven name can make a genuinely-managed
      resource statically unmatchable; that case gets `TypePresentInTemplates
      = $true` and `Severity = 'Medium'` instead of `'High'`, so results are
      not over-confident). Matched resources are reported separately.
      `-IncludeTemplatedButMissing` additionally reports template resources
      with a resolvable name that have no matching discovered resource
      (declared in IaC but not found in Azure — may be undeployed).

.PARAMETER CollectData
    The parsed collect.json object, OR a pre-flattened array of
    `{ Type, Name, ResourceGroup }` objects. $null/empty degrades to zero
    discovered resources (not an error) — the template-side comparison still
    runs and simply reports nothing on the discovery side.

.PARAMETER TemplatePath
    Folder to search (recursively) for `.bicep`/`.json` template files.
    Absent, blank, non-existent, or a folder with no matching files degrades
    gracefully: `HasTemplates = $false` with a clear `Message`, never a throw.

.PARAMETER IncludeTemplatedButMissing
    Also report template resources with a resolvable literal name that have
    no matching discovered resource. Off by default (the primary contract is
    "what's unmanaged", per AB#325).

.OUTPUTS
    [pscustomobject] — HasTemplates/Message/GeneratedOn/DiscoveredCount/
    TemplateResourceCount/TemplateFileCount/Unmanaged[]/Matched[]/
    TemplatedButMissing[]. See tests/Analyze.IacGap.Tests.ps1 for the exact
    shape exercised.

.NOTES
    Tracks ADO Story AB#325.

    LIMITATIONS (honest, by design):
      - collect.json items carry `name`/`resourceGroup`/`subscriptionId` but
        NOT a full ARM resourceId or `type` string (confirmed against
        src/collect/Invoke-Collect.ps1 and tests/datadump/sample-collect.json)
        — the section->type map here is this function's own best-effort
        reconstruction of "what ARM type does this collect.json array hold",
        not data the collector stamps onto each item.
      - Excluded from discovery on purpose: `management.deployments` (a
        deployment EXECUTION record, not a `resource` block a template
        declares — not comparable), `security.defenderPlans` (a
        subscription-wide setting, not a discretely-named resource),
        `networking.subnets` / `networking.nsgPublicInbound` (child-resource /
        rule-level rows, not a full independent resource inventory for that
        type).
      - Bicep name resolution is regex/text-based, not a real Bicep parse: a
        `name:` value that is anything other than a single-quoted literal
        (a parameter reference, `${interpolation}`, a `for`-loop expression,
        `concat(...)`, etc.) is correctly reported as unresolved rather than
        guessed at — such resources fall back to the type-level
        `TypePresentInTemplates` signal instead of a confident name match.
      - Matching is exact on (Type, Name) only; it does not account for a
        resource being declared in one subscription's template set but
        deployed to a different resource group/subscription than discovered,
        nor for child resources whose collect.json `name` omits the parent
        (e.g. `domains.databases.sqlDatabases`).
#>
function Get-ScoutIacGap {
    [CmdletBinding()]
    param(
        $CollectData,
        [string] $TemplatePath,
        [switch] $IncludeTemplatedButMissing
    )

    function Get-IacGapProp {
        param($Obj, [string] $Name)
        if ($null -eq $Obj) { return $null }
        $p = $Obj.PSObject.Properties[$Name]
        if ($p) { return $p.Value } else { return $null }
    }

    function Get-IacGapPathValue {
        param($Obj, [string] $Path)
        $cur = $Obj
        foreach ($seg in ($Path -split '\.')) {
            $cur = Get-IacGapProp $cur $seg
            if ($null -eq $cur) { return $null }
        }
        return $cur
    }

    # ---- section (collect.json path) -> ARM resource type, sourced from the
    # real `type =~ "..."` filters in src/collect/Invoke-Collect.ps1 ----
    $sectionMap = @(
        @{ Path = 'networking.virtualNetworks'; Type = 'Microsoft.Network/virtualNetworks' }
        @{ Path = 'networking.azureFirewalls'; Type = 'Microsoft.Network/azureFirewalls' }
        @{ Path = 'networking.vpnGateways'; Type = 'Microsoft.Network/virtualNetworkGateways' }
        @{ Path = 'networking.privateEndpoints'; Type = 'Microsoft.Network/privateEndpoints' }
        @{ Path = 'networking.privateDnsZones'; Type = 'Microsoft.Network/privateDnsZones' }
        @{ Path = 'compute.virtualMachines'; Type = 'Microsoft.Compute/virtualMachines' }
        @{ Path = 'management.recoveryVaults'; Type = 'Microsoft.RecoveryServices/vaults' }
        @{ Path = 'governance.managementGroups'; Type = 'Microsoft.Management/managementGroups' }
        @{ Path = 'governance.policyAssignments'; Type = 'Microsoft.Authorization/policyAssignments' }
        @{ Path = 'governance.resourceLocks'; Type = 'Microsoft.Authorization/locks' }
        @{ Path = 'governance.budgets'; Type = 'Microsoft.Consumption/budgets' }
        @{ Path = 'domains.storage.storageAccounts'; Type = 'Microsoft.Storage/storageAccounts' }
        @{ Path = 'domains.databases.sqlServers'; Type = 'Microsoft.Sql/servers' }
        @{ Path = 'domains.databases.sqlDatabases'; Type = 'Microsoft.Sql/servers/databases' }
        @{ Path = 'domains.web.webApps'; Type = 'Microsoft.Web/sites' }
        @{ Path = 'domains.containers.aksClusters'; Type = 'Microsoft.ContainerService/managedClusters' }
        @{ Path = 'domains.containers.containerRegistries'; Type = 'Microsoft.ContainerRegistry/registries' }
        @{ Path = 'domains.security.keyVaults'; Type = 'Microsoft.KeyVault/vaults' }
        @{ Path = 'domains.ai.cognitiveAccounts'; Type = 'Microsoft.CognitiveServices/accounts' }
        @{ Path = 'domains.hybrid.arcServers'; Type = 'Microsoft.HybridCompute/machines' }
        @{ Path = 'domains.hybrid.azureLocalClusters'; Type = 'Microsoft.AzureStackHCI/clusters' }
        @{ Path = 'domains.integration.eventHubNamespaces'; Type = 'Microsoft.EventHub/namespaces' }
        @{ Path = 'domains.integration.apiManagement'; Type = 'Microsoft.ApiManagement/service' }
        @{ Path = 'domains.integration.serviceBusNamespaces'; Type = 'Microsoft.ServiceBus/namespaces' }
        @{ Path = 'domains.iot.iotHubs'; Type = 'Microsoft.Devices/IotHubs' }
        @{ Path = 'domains.iot.dpsInstances'; Type = 'Microsoft.Devices/provisioningServices' }
        @{ Path = 'domains.iot.digitalTwinsInstances'; Type = 'Microsoft.DigitalTwins/digitalTwinsInstances' }
        @{ Path = 'domains.analytics.synapseWorkspaces'; Type = 'Microsoft.Synapse/workspaces' }
        @{ Path = 'domains.analytics.purviewAccounts'; Type = 'Microsoft.Purview/accounts' }
    )

    # ---- flatten discovery input ----
    $discovered = [System.Collections.Generic.List[object]]::new()
    foreach ($m in $sectionMap) {
        $arr = @(Get-IacGapPathValue -Obj $CollectData -Path $m.Path)
        foreach ($item in $arr) {
            if ($null -eq $item) { continue }
            $name = Get-IacGapProp $item 'name'
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $discovered.Add([pscustomobject]@{
                    Name           = $name
                    Type           = $m.Type
                    ResourceGroup  = Get-IacGapProp $item 'resourceGroup'
                    SubscriptionId = Get-IacGapProp $item 'subscriptionId'
                    SourcePath     = $m.Path
                })
        }
    }

    # ---- fall back to treating -CollectData directly as a pre-flattened array ----
    if ($discovered.Count -eq 0) {
        foreach ($item in @($CollectData | Where-Object { $null -ne $_ })) {
            $t = Get-IacGapProp $item 'Type'
            if (-not $t) { $t = Get-IacGapProp $item 'type' }
            $n = Get-IacGapProp $item 'Name'
            if (-not $n) { $n = Get-IacGapProp $item 'name' }
            if (-not $t -or -not $n) { continue }
            $rg = Get-IacGapProp $item 'ResourceGroup'
            if (-not $rg) { $rg = Get-IacGapProp $item 'resourceGroup' }
            $subId = Get-IacGapProp $item 'SubscriptionId'
            if (-not $subId) { $subId = Get-IacGapProp $item 'subscriptionId' }
            $discovered.Add([pscustomobject]@{
                    Name = $n; Type = $t; ResourceGroup = $rg; SubscriptionId = $subId; SourcePath = '(direct)'
                })
        }
    }

    # ---- degrade gracefully: no template path supplied / doesn't exist ----
    if ([string]::IsNullOrWhiteSpace($TemplatePath) -or -not (Test-Path -LiteralPath $TemplatePath)) {
        return [pscustomobject]@{
            HasTemplates          = $false
            Message               = 'Get-ScoutIacGap: -TemplatePath was not supplied or does not exist — no IaC templates to compare against, so gap detection was skipped. Pass -TemplatePath at a folder of .bicep/.json templates to enable this check.'
            GeneratedOn           = (Get-Date).ToString('o')
            DiscoveredCount       = $discovered.Count
            TemplateResourceCount = 0
            TemplateFileCount     = 0
            Unmanaged             = @()
            Matched               = @()
            TemplatedButMissing   = @()
        }
    }

    $templateFiles = @(Get-ChildItem -LiteralPath $TemplatePath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.bicep', '.json' })

    if ($templateFiles.Count -eq 0) {
        return [pscustomobject]@{
            HasTemplates          = $false
            Message               = "Get-ScoutIacGap: -TemplatePath '$TemplatePath' contains no .bicep or .json template files — nothing to compare against."
            GeneratedOn           = (Get-Date).ToString('o')
            DiscoveredCount       = $discovered.Count
            TemplateResourceCount = 0
            TemplateFileCount     = 0
            Unmanaged             = @()
            Matched               = @()
            TemplatedButMissing   = @()
        }
    }

    # ---- parse template files (best-effort) ----
    function Get-IacGapTemplateResource {
        param([string] $FilePath, [string] $Extension)
        $found = [System.Collections.Generic.List[object]]::new()
        $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($content)) { return $found }

        if ($Extension -eq '.bicep') {
            $pattern = "resource\s+[A-Za-z0-9_]+\s+'([^'@]+)@([^']+)'\s*="
            foreach ($m in [regex]::Matches($content, $pattern)) {
                $type = $m.Groups[1].Value
                $apiVersion = $m.Groups[2].Value
                $startIdx = $m.Index + $m.Length
                $windowLen = [Math]::Min(600, $content.Length - $startIdx)
                $name = $null
                if ($windowLen -gt 0) {
                    $window = $content.Substring($startIdx, $windowLen)
                    $nameMatch = [regex]::Match($window, "name\s*:\s*'([^'\$]*)'")
                    if ($nameMatch.Success) { $name = $nameMatch.Groups[1].Value }
                }
                $found.Add([pscustomobject]@{
                        Type = $type; ApiVersion = $apiVersion; Name = $name
                        NameResolved = [bool]$name; SourceFile = $FilePath
                    })
            }
        }
        elseif ($Extension -eq '.json') {
            try { $json = $content | ConvertFrom-Json -Depth 100 -ErrorAction Stop } catch { return $found }
            $resources = Get-IacGapProp $json 'resources'
            foreach ($res in @($resources)) {
                if ($null -eq $res) { continue }
                $type = Get-IacGapProp $res 'type'
                if (-not $type) { continue }
                $rawName = Get-IacGapProp $res 'name'
                $isExpr = ($rawName -is [string]) -and $rawName.StartsWith('[') -and $rawName.EndsWith(']')
                $name = if ($isExpr -or -not $rawName) { $null } else { [string]$rawName }
                $found.Add([pscustomobject]@{
                        Type = $type; ApiVersion = (Get-IacGapProp $res 'apiVersion'); Name = $name
                        NameResolved = [bool]$name; SourceFile = $FilePath
                    })
            }
        }
        return $found
    }

    $templateResources = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $templateFiles) {
        foreach ($tr in (Get-IacGapTemplateResource -FilePath $f.FullName -Extension $f.Extension)) {
            $templateResources.Add($tr)
        }
    }

    $templateByKey = @{}
    $templateTypesPresent = @{}
    foreach ($tr in $templateResources) {
        $ntype = ([string]$tr.Type).ToLowerInvariant()
        $templateTypesPresent[$ntype] = $true
        if ($tr.NameResolved) {
            $key = "$ntype|$(([string]$tr.Name).ToLowerInvariant())"
            if (-not $templateByKey.ContainsKey($key)) { $templateByKey[$key] = [System.Collections.Generic.List[object]]::new() }
            $templateByKey[$key].Add($tr)
        }
    }

    # ---- compare ----
    $unmanaged = [System.Collections.Generic.List[object]]::new()
    $matched = [System.Collections.Generic.List[object]]::new()

    foreach ($d in $discovered) {
        $ntype = ([string]$d.Type).ToLowerInvariant()
        $nname = ([string]$d.Name).ToLowerInvariant()
        $key = "$ntype|$nname"

        if ($templateByKey.ContainsKey($key)) {
            $matched.Add([pscustomobject]@{
                    Name = $d.Name; Type = $d.Type; ResourceGroup = $d.ResourceGroup
                    MatchedTemplateFile = $templateByKey[$key][0].SourceFile
                })
        }
        else {
            $typePresent = [bool]$templateTypesPresent[$ntype]
            $message = if ($typePresent) {
                "No template resource named '$($d.Name)' of type $($d.Type) was found, though this type IS declared elsewhere in the template set — the name may be parameter-driven and not statically resolvable; verify manually."
            }
            else {
                "Resource '$($d.Name)' ($($d.Type)) exists in the discovered inventory but no template of this type was found under -TemplatePath at all — likely unmanaged / created outside IaC."
            }
            $unmanaged.Add([pscustomobject]@{
                    Name = $d.Name; Type = $d.Type; ResourceGroup = $d.ResourceGroup; SubscriptionId = $d.SubscriptionId
                    TypePresentInTemplates = $typePresent
                    Severity = if ($typePresent) { 'Medium' } else { 'High' }
                    Message  = $message
                })
        }
    }

    $templatedButMissing = [System.Collections.Generic.List[object]]::new()
    if ($IncludeTemplatedButMissing.IsPresent) {
        $discoveredKeys = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($d in $discovered) {
            [void]$discoveredKeys.Add("$(([string]$d.Type).ToLowerInvariant())|$(([string]$d.Name).ToLowerInvariant())")
        }
        foreach ($kv in $templateByKey.GetEnumerator()) {
            if (-not $discoveredKeys.Contains($kv.Key)) {
                $first = $kv.Value[0]
                $templatedButMissing.Add([pscustomobject]@{
                        Name = $first.Name; Type = $first.Type; SourceFile = $first.SourceFile
                        Message = "Template declares '$($first.Name)' ($($first.Type)) in $($first.SourceFile) but no matching resource was found in the discovered inventory — may be undeployed, deployed under a different name, or removed outside IaC."
                    })
            }
        }
    }

    $summary = "Compared $($discovered.Count) discovered resource(s) against $($templateResources.Count) template resource declaration(s) across $($templateFiles.Count) file(s): $($unmanaged.Count) unmanaged, $($matched.Count) matched"
    if ($IncludeTemplatedButMissing.IsPresent) { $summary += ", $($templatedButMissing.Count) templated-but-missing" }
    $summary += '.'

    return [pscustomobject]@{
        HasTemplates          = $true
        Message               = $summary
        GeneratedOn           = (Get-Date).ToString('o')
        DiscoveredCount       = $discovered.Count
        TemplateResourceCount = $templateResources.Count
        TemplateFileCount     = $templateFiles.Count
        Unmanaged             = @($unmanaged | Sort-Object Type, Name)
        Matched               = @($matched | Sort-Object Type, Name)
        TemplatedButMissing   = @($templatedButMissing | Sort-Object Type, Name)
    }
}

#Requires -Version 7.0
#Requires -Modules Pester, powershell-yaml

<#
    AB#9300 (depth wiring) -- manual rules converted to data-backed rules because the data they need was
    already collected (a dataset the inventory run reads, or a property already on the Resource Graph row)
    and only needed projecting, shaping and a rule that reads it.

    For every converted rule this file holds a fixture that PASSES, one that FAILS (with the evidence count
    the query must find, so a query that always passes or always fails cannot slip through) and one that is
    NOT ASSESSED -- the data was not measured, or the resource type is absent. The rules are the real ones,
    read from src/assess/rules; the fixtures are shaped like ConvertFrom-ScoutInventory's output, and the
    shaper tests below prove the shapes by feeding that function real-looking Resource Graph rows.

    It also pins:
      - typed-query / shaper parity: the columns each changed typed Resource Graph query projects are
        exactly the properties the shaper emits, field for field (tests/Collect.SinglePassInversion.Tests.ps1
        holds the value-level equivalence for the fixtures it already carries);
      - the lifecycle policy dataset end to end (the ARM sweep, its storage-kind gate, the shaper, and the
        wiring into the assessment path's ArmChildDataset list);
      - nothing secret-bearing is projected: no Container App secret, registry credential or probe header,
        no APIM key, no Firewall CA name or Key Vault secret id, no lifecycle rule name or container prefix.

    No Azure connection is made.
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'helpers/DepthWiringCases.ps1')
}

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    Import-Module powershell-yaml -ErrorAction Stop
    . (Join-Path $script:Root 'src/assess/engine/Get-RuleSet.ps1')
    . (Join-Path $script:Root 'src/assess/engine/Resolve-JsonPath.ps1')
    . (Join-Path $script:Root 'src/assess/engine/Resolve-RuleJoin.ps1')
    . (Join-Path $script:Root 'src/assess/engine/Invoke-Rule.ps1')
    . (Join-Path $script:Root 'src/collect/ConvertFrom-ScoutInventory.ps1')

    $script:RuleSets = @{}
    function Get-DepthRule {
        param([string] $Set, [string] $Id)
        if (-not $script:RuleSets.ContainsKey($Set)) { $script:RuleSets[$Set] = @(Get-RuleSet -Patterns @($Set))[0] }
        $rule = @($script:RuleSets[$Set].Rules | Where-Object { $_.id -eq $Id })[0]
        $rule | Should -Not -BeNullOrEmpty -Because "$Id must exist in $Set"
        return $rule
    }

    function Get-DepthFinding {
        param([string] $Set, [string] $Id, [hashtable] $Collect)
        $rule = Get-DepthRule -Set $Set -Id $Id
        $json = $Collect | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        return Invoke-Rule -Rule $rule -Collect $json -Area $script:RuleSets[$Set].Area -Framework $script:RuleSets[$Set].Framework
    }

    # A shaped-resource helper: the Resource Graph row ConvertFrom-ScoutInventory reads.
    function New-DepthResource {
        param([string] $Type, [string] $Name = 'r1', $Properties = @{}, [hashtable] $Extra = @{})
        $row = [ordered]@{
            id = "/subscriptions/sub1/resourceGroups/rg1/providers/$Type/$Name"
            name = $Name; type = $Type; location = 'eastus'; resourceGroup = 'rg1'; subscriptionId = 'sub1'
            properties = [pscustomobject] $Properties
        }
        foreach ($key in $Extra.Keys) { $row[$key] = $Extra[$key] }
        return [pscustomobject] $row
    }

    # The columns a typed Resource Graph query puts on its result: the identifiers of the LAST `project`.
    function Get-KqlProjectedColumn {
        param([string] $Kql)
        $text = (($Kql -split "\r?\n") | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
        $at = $text.LastIndexOf('| project ')
        $at | Should -BeGreaterOrEqual 0
        $body = $text.Substring($at + '| project '.Length)
        $items = [System.Collections.Generic.List[string]]::new()
        $depth = 0; $quote = [char]0; $current = [System.Text.StringBuilder]::new()
        foreach ($ch in $body.ToCharArray()) {
            if ($quote -ne [char]0) { if ($ch -eq $quote) { $quote = [char]0 } }
            elseif ($ch -eq '"' -or $ch -eq "'") { $quote = $ch }
            elseif ($ch -in '(', '[') { $depth++ }
            elseif ($ch -in ')', ']') { $depth-- }
            elseif ($ch -eq ',' -and $depth -eq 0) { $items.Add($current.ToString()); [void]$current.Clear(); continue }
            [void]$current.Append($ch)
        }
        $items.Add($current.ToString())
        foreach ($item in $items) {
            $trimmed = $item.Trim()
            if ($trimmed -match "^\[?'?([A-Za-z_][A-Za-z0-9_]*)'?\]?\s*=") { $Matches[1] }
            elseif ($trimmed -match '^([A-Za-z_][A-Za-z0-9_]*)$') { $Matches[1] }
        }
    }

    $script:CollectSource = Get-Content (Join-Path $script:Root 'src/collect/Invoke-Collect.ps1') -Raw
    function Get-TypedQuery {
        param([string] $Key)
        $m = [regex]::Match($script:CollectSource, "(?s)\r?\n\s+$Key = @'\r?\n(.*?)\r?\n'@")
        $m.Success | Should -BeTrue -Because "the typed query '$Key' must exist"
        return $m.Groups[1].Value
    }

    . (Join-Path $PSScriptRoot 'helpers/DepthWiringCases.ps1')
}

Describe 'Every converted rule is automated, keeps its conventions and is gated' {
    It '<Id> is no longer manual, starts its title and remediation with its id, and carries a gate' -ForEach $script:Cases {
        $rule = Get-DepthRule -Set $Set -Id $Id
        [bool]$rule.manual | Should -BeFalse
        $rule.assert.type | Should -Not -Be 'manual'
        $rule.title | Should -BeLike "$Id. *"
        $rule.remediation | Should -BeLike "$Id. *"
        @($rule.assert.gate | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count | Should -BeGreaterThan 0 -Because 'a converted rule must read Not assessed, never Fail, when its data was not measured'
    }

    It '<Id> uses no grouping parenthesis and never mixes && with || in one filter' -ForEach $script:Cases {
        $rule = Get-DepthRule -Set $Set -Id $Id
        $paths = @(
            if ($rule.ContainsKey('query')) { [string]$rule.query }
            @($rule.assert.gate | ForEach-Object { [string]$_ })
            if ($rule.ContainsKey('join')) { [string]$rule.join.left; [string]$rule.join.right }
        )
        foreach ($path in $paths) {
            $stripped = [regex]::Replace($path, '/(\\.|[^/])*/i?', '').Replace('?(', '')
            $stripped | Should -Not -Match '\(' -Because "$Id would hide a grouping parenthesis from Newtonsoft JSONPath"
            $stripped | Should -Not -Match '&&.*\|\||\|\|.*&&' -Because "$Id mixes && and || and Newtonsoft nests them to the right"
            $stripped | Should -Not -Match '!\s*(\(|@)' -Because "$Id uses a negation Newtonsoft JSONPath does not have"
        }
    }
}

Describe 'Each converted rule passes, fails and is not assessed on its fixtures' {
    It '<Id> passes on a compliant estate' -ForEach $script:Cases {
        $finding = Get-DepthFinding -Set $Set -Id $Id -Collect $Pass
        $finding.Status | Should -Be 'Pass' -Because "evidence: $($finding.EvidenceCount)"
        $finding.Manual | Should -BeFalse
    }

    It '<Id> fails on a non-compliant estate with exactly the offenders as evidence' -ForEach @($script:Cases | Where-Object { $_.Id -ne 'WAF-MC-HM-10' }) {
        $finding = Get-DepthFinding -Set $Set -Id $Id -Collect $Fail
        $finding.Status | Should -Be 'Fail'
        $finding.EvidenceCount | Should -Be $FailCount
    }

    It '<Id> reads NotAssessed -- never Fail -- when the data was not measured or the type is absent' -ForEach $script:Cases {
        $finding = Get-DepthFinding -Set $Set -Id $Id -Collect $NotAssessed
        $finding.Status | Should -Be 'NotAssessed'
    }
}

Describe 'WAF-MC-HM-10 -- Service Health alert coverage' {
    It 'fails when no ENABLED Service Health activity-log alert exists, and counts none as evidence' {
        $case = @($script:Cases | Where-Object { $_.Id -eq 'WAF-MC-HM-10' })[0]
        $finding = Get-DepthFinding -Set $case.Set -Id $case.Id -Collect $case.Fail
        $finding.Status | Should -Be 'Fail'
        $finding.EvidenceCount | Should -Be 0
    }

    It 'is satisfied by one enabled Service Health alert among other categories' {
        $finding = Get-DepthFinding -Set 'waf.missioncritical' -Id 'WAF-MC-HM-10' -Collect @{
            subscriptions = @(@{ id = 'sub-a' })
            monitor = @{ activityLogAlertRules = @(@{ category = 'Administrative'; enabled = $true }, @{ category = 'ServiceHealth'; enabled = $true }, @{ category = 'ResourceHealth'; enabled = $false }) }
        }
        $finding.Status | Should -Be 'Pass'
        $finding.EvidenceCount | Should -Be 1
    }
}

Describe 'Rule-specific semantics' {
    It 'WAF-SVC-FW-06 leaves a child policy to its parent, because the firewall enforces the stricter of the two' {
        $finding = Get-DepthFinding -Set 'waf.serviceguides' -Id 'WAF-SVC-FW-06' -Collect @{
            networking = @{ firewallPolicies = @(@{ id = 'child'; hasBasePolicy = $true; idpsEnabled = $false; tlsInspectionEnabled = $false; dnsProxyEnabled = $false; idpsTlsDnsEnabled = $false }) }
        }
        $finding.Status | Should -Be 'Pass'
    }

    It 'WAF-DATA-BLOB-13 does not list a premium block blob account, which has no access tiers' {
        $finding = Get-DepthFinding -Set 'waf.dataservices' -Id 'WAF-DATA-BLOB-13' -Collect @{
            domains = @{ storage = @{ lifecyclePoliciesMeasured = $true; lifecyclePolicies = @(@{ storageAccountId = 's-premium'; premium = $true; enabledRuleCount = 0; tieringRuleCount = 0; deleteRuleCount = 0 }) } }
        }
        $finding.Status | Should -Be 'Pass'
    }

    It 'WAF-SVC-VWAN-05 treats a hub with no ExpressRoute gateway as out of scope, not as a pass' {
        $finding = Get-DepthFinding -Set 'waf.serviceguides' -Id 'WAF-SVC-VWAN-05' -Collect @{
            networking = @{ virtualHubs = @(@{ name = 'h'; hasExpressRouteGateway = $false; hasVpnGateway = $false; routingPreference = ''; expressRouteBackedUp = $false }) }
        }
        $finding.Status | Should -Be 'NotAssessed'
    }

    It 'WAF-ANALYTICS-RE-10 matches the zone-region list case-insensitively and ignores a missing replication flag in a zone region' {
        $finding = Get-DepthFinding -Set 'waf.analytics' -Id 'WAF-ANALYTICS-RE-10' -Collect @{
            management = @{ logAnalyticsWorkspaces = @(@{ id = 'w'; location = 'WestEurope'; replicationEnabled = $null }) }
        }
        $finding.Status | Should -Be 'Pass'
    }

    It 'CAF-RES-04 lists a subscription directly under the tenant root and not one a level further down' {
        $finding = Get-DepthFinding -Set 'caf.resourceorg' -Id 'CAF-RES-04' -Collect @{
            subscriptions = @(@{ id = 'root-child'; managementGroupLevels = 1 }, @{ id = 'placed'; managementGroupLevels = 2 })
        }
        $finding.Status | Should -Be 'Fail'
        $finding.EvidenceCount | Should -Be 1
        (@($finding.Evidence | ForEach-Object { $_.ToString() }) -join ' ') | Should -Match 'root-child'
        (@($finding.Evidence | ForEach-Object { $_.ToString() }) -join ' ') | Should -Not -Match 'placed'
    }
}

Describe 'The shaper reads each new field from a Resource Graph row' {
    It 'shapes a subscription management group chain to its length, null when the chain is absent' {
        $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @(
            [pscustomobject]@{ type = 'microsoft.resources/subscriptions'; name = 'a'; subscriptionId = 's1'; properties = [pscustomobject]@{ state = 'Enabled'; managementGroupAncestorsChain = @([pscustomobject]@{ name = 'root' }) }; tags = $null }
            [pscustomobject]@{ type = 'microsoft.resources/subscriptions'; name = 'b'; subscriptionId = 's2'; properties = [pscustomobject]@{ state = 'Enabled'; managementGroupAncestorsChain = @([pscustomobject]@{ name = 'child' }, [pscustomobject]@{ name = 'mid' }, [pscustomobject]@{ name = 'root' }) }; tags = $null }
            [pscustomobject]@{ type = 'microsoft.resources/subscriptions'; name = 'c'; subscriptionId = 's3'; properties = [pscustomobject]@{ state = 'Enabled' }; tags = $null }
        )
        $levels = @($shaped['subscriptions'] | Sort-Object id | ForEach-Object { $_.managementGroupLevels })
        $levels[0] | Should -Be 1
        $levels[1] | Should -Be 3
        $null -eq $levels[2] | Should -BeTrue
    }

    It 'counts Container App containers and those missing any of the three probes, reading only each probe type' {
        $probe = { param($type) [pscustomobject]@{ type = $type; httpGet = [pscustomobject]@{ path = '/h'; httpHeaders = @([pscustomobject]@{ name = 'Authorization'; value = 'SENTINEL-HEADER-VALUE' }) } } }
        $full = [pscustomobject]@{ name = 'c1'; probes = @((& $probe 'Liveness'), (& $probe 'Readiness'), (& $probe 'Startup')) }
        $partial = [pscustomobject]@{ name = 'c2'; probes = @((& $probe 'Liveness'), (& $probe 'Readiness')) }
        $bare = [pscustomobject]@{ name = 'c3' }
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-DepthResource -Type 'microsoft.app/containerapps' -Name 'all-good' -Properties @{ template = [pscustomobject]@{ containers = @($full) } }
            New-DepthResource -Type 'microsoft.app/containerapps' -Name 'mixed' -Properties @{ template = [pscustomobject]@{ containers = @($full, $partial, $bare) } }
            New-DepthResource -Type 'microsoft.app/containerapps' -Name 'no-list' -Properties @{}
            New-DepthResource -Type 'microsoft.app/containerapps' -Name 'empty-list' -Properties @{ template = [pscustomobject]@{ containers = @() } }
        ) -ResourceContainers @()
        $apps = @{}; foreach ($a in $shaped['containerApps']) { $apps[$a.name] = $a }
        $apps['all-good'].containerCount | Should -Be 1
        $apps['all-good'].containersWithoutAllProbes | Should -Be 0
        $apps['mixed'].containerCount | Should -Be 3
        $apps['mixed'].containersWithoutAllProbes | Should -Be 2
        $null -eq $apps['no-list'].containerCount | Should -BeTrue
        $apps['no-list'].containersWithoutAllProbes | Should -Be 0
        $apps['empty-list'].containerCount | Should -Be 0
        $apps['empty-list'].containersWithoutAllProbes | Should -Be 0
        ($shaped | ConvertTo-Json -Depth 8) | Should -Not -Match 'SENTINEL-HEADER-VALUE'
    }

    It 'says whether a Container Apps environment exports its logs, from the destination or an OpenTelemetry logs destination' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-DepthResource -Type 'microsoft.app/managedenvironments' -Name 'law' -Properties @{ appLogsConfiguration = [pscustomobject]@{ destination = 'log-analytics'; logAnalyticsConfiguration = [pscustomobject]@{ customerId = 'SENTINEL-WORKSPACE'; sharedKey = 'SENTINEL-KEY' } } }
            New-DepthResource -Type 'microsoft.app/managedenvironments' -Name 'monitor' -Properties @{ appLogsConfiguration = [pscustomobject]@{ destination = 'Azure-Monitor' } }
            New-DepthResource -Type 'microsoft.app/managedenvironments' -Name 'none' -Properties @{ appLogsConfiguration = [pscustomobject]@{ destination = 'none' } }
            New-DepthResource -Type 'microsoft.app/managedenvironments' -Name 'otel' -Properties @{ appLogsConfiguration = [pscustomobject]@{ destination = 'none' }; openTelemetryConfiguration = [pscustomobject]@{ logsConfiguration = [pscustomobject]@{ destinations = @('appInsights') } } }
            New-DepthResource -Type 'microsoft.app/managedenvironments' -Name 'unset' -Properties @{}
        ) -ResourceContainers @()
        $envs = @{}; foreach ($e in $shaped['containerAppEnvironments']) { $envs[$e.name] = $e }
        $envs['law'].logsExported | Should -BeTrue
        $envs['monitor'].logsExported | Should -BeTrue
        $envs['none'].logsExported | Should -BeFalse
        $envs['otel'].logsExported | Should -BeTrue
        $envs['unset'].logsExported | Should -BeFalse
        $envs['unset'].logDestination | Should -Be ''
        ($shaped | ConvertTo-Json -Depth 8) | Should -Not -Match 'SENTINEL-'
    }

    It 'reads the AKS Azure Policy add-on switch, null when the cluster has no such add-on profile' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-DepthResource -Type 'microsoft.containerservice/managedclusters' -Name 'on' -Properties @{ addonProfiles = [pscustomobject]@{ azurepolicy = [pscustomobject]@{ enabled = $true } } }
            New-DepthResource -Type 'microsoft.containerservice/managedclusters' -Name 'off' -Properties @{ addonProfiles = [pscustomobject]@{ azurepolicy = [pscustomobject]@{ enabled = $false } } }
            New-DepthResource -Type 'microsoft.containerservice/managedclusters' -Name 'none' -Properties @{ addonProfiles = [pscustomobject]@{ omsagent = [pscustomobject]@{ enabled = $true } } }
        ) -ResourceContainers @()
        $aks = @{}; foreach ($c in $shaped['aksClusters']) { $aks[$c.name] = $c }
        $aks['on'].azurePolicyAddon | Should -BeTrue
        $aks['off'].azurePolicyAddon | Should -BeFalse
        $null -eq $aks['none'].azurePolicyAddon | Should -BeTrue
    }

    It 'reads the APIM legacy protocol and cipher switches by their dotted key names, case-insensitively, null when absent' {
        $prefix = 'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.'
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-DepthResource -Type 'microsoft.apimanagement/service' -Name 'clean' -Properties @{ customProperties = [pscustomobject]@{ "${prefix}Protocols.Ssl30" = 'False'; "${prefix}Protocols.Tls10" = 'false'; "${prefix}Protocols.Tls11" = 'False'; "${prefix}Backend.Protocols.Tls10" = 'False'; "${prefix}Ciphers.TripleDes168" = 'False' } }
            New-DepthResource -Type 'microsoft.apimanagement/service' -Name 'tls10' -Properties @{ customProperties = [pscustomobject]@{ "${prefix}Protocols.Tls10" = 'True'; "${prefix}Protocols.Tls11" = 'False' } }
            New-DepthResource -Type 'microsoft.apimanagement/service' -Name 'backend' -Properties @{ customProperties = [pscustomobject]@{ "${prefix}Backend.Protocols.Tls11" = 'TRUE' } }
            New-DepthResource -Type 'microsoft.apimanagement/service' -Name 'cipher' -Properties @{ customProperties = [pscustomobject]@{ "${prefix}Protocols.Tls10" = 'False'; "${prefix}Ciphers.TripleDes168" = 'True' } }
            New-DepthResource -Type 'microsoft.apimanagement/service' -Name 'absent' -Properties @{}
        ) -ResourceContainers @()
        $apim = @{}; foreach ($s in $shaped['apiManagement']) { $apim[$s.name] = $s }
        $apim['clean'].legacyProtocolEnabled | Should -BeFalse
        $apim['clean'].legacyCipherEnabled | Should -BeFalse
        $apim['tls10'].legacyProtocolEnabled | Should -BeTrue
        $null -eq $apim['tls10'].legacyCipherEnabled | Should -BeTrue
        $apim['backend'].legacyProtocolEnabled | Should -BeTrue
        $apim['cipher'].legacyProtocolEnabled | Should -BeFalse
        $apim['cipher'].legacyCipherEnabled | Should -BeTrue
        $null -eq $apim['absent'].legacyProtocolEnabled | Should -BeTrue
        $null -eq $apim['absent'].legacyCipherEnabled | Should -BeTrue
    }

    It 'reduces a Firewall policy to booleans and never carries the certificate authority name or Key Vault secret id' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-DepthResource -Type 'microsoft.network/firewallpolicies' -Name 'full' -Properties @{
                sku = [pscustomobject]@{ tier = 'Premium' }
                intrusionDetection = [pscustomobject]@{ mode = 'Deny' }
                transportSecurity = [pscustomobject]@{ certificateAuthority = [pscustomobject]@{ name = 'SENTINEL-CA-NAME'; keyVaultSecretId = 'https://SENTINEL-VAULT.vault.azure.net/secrets/ca' } }
                dnsSettings = [pscustomobject]@{ enableProxy = $true }
            }
            New-DepthResource -Type 'microsoft.network/firewallpolicies' -Name 'idpsOff' -Properties @{ intrusionDetection = [pscustomobject]@{ mode = 'Off' }; dnsSettings = [pscustomobject]@{ enableProxy = $true } }
            New-DepthResource -Type 'microsoft.network/firewallpolicies' -Name 'child' -Properties @{ basePolicy = [pscustomobject]@{ id = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.Network/firewallPolicies/parent' } }
        ) -ResourceContainers @()
        $fw = @{}; foreach ($p in $shaped['firewallPolicies']) { $fw[$p.name] = $p }
        $fw['full'].idpsEnabled | Should -BeTrue
        $fw['full'].tlsInspectionEnabled | Should -BeTrue
        $fw['full'].dnsProxyEnabled | Should -BeTrue
        $fw['full'].hasBasePolicy | Should -BeFalse
        $fw['full'].idpsTlsDnsEnabled | Should -BeTrue
        $fw['idpsOff'].idpsEnabled | Should -BeFalse
        $fw['idpsOff'].idpsTlsDnsEnabled | Should -BeFalse
        $fw['child'].hasBasePolicy | Should -BeTrue
        $fw['child'].idpsTlsDnsEnabled | Should -BeFalse
        ($shaped | ConvertTo-Json -Depth 8) | Should -Not -Match 'SENTINEL-'
    }

    It 'reads the Application Insights IP masking switch, null when absent' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-DepthResource -Type 'microsoft.insights/components' -Name 'masked' -Properties @{ DisableLocalAuth = $true; DisableIpMasking = $false }
            New-DepthResource -Type 'microsoft.insights/components' -Name 'unmasked' -Properties @{ DisableIpMasking = $true }
            New-DepthResource -Type 'microsoft.insights/components' -Name 'unset' -Properties @{}
        ) -ResourceContainers @()
        $ai = @{}; foreach ($c in $shaped['appInsights']) { $ai[$c.name] = $c }
        $ai['masked'].disableIpMasking | Should -BeFalse
        $ai['unmasked'].disableIpMasking | Should -BeTrue
        $null -eq $ai['unset'].disableIpMasking | Should -BeTrue
    }

    It 'reads a Traffic Manager profile TTL and counts the endpoints with AlwaysServe on' {
        $endpoint = { param($state) [pscustomobject]@{ name = 'e'; properties = [pscustomobject]@{ alwaysServe = $state } } }
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-DepthResource -Type 'microsoft.network/trafficmanagerprofiles' -Name 'tm' -Properties @{ dnsConfig = [pscustomobject]@{ ttl = 30 }; endpoints = @((& $endpoint 'Enabled'), (& $endpoint 'Disabled'), (& $endpoint 'enabled')) }
            New-DepthResource -Type 'microsoft.network/trafficmanagerprofiles' -Name 'sparse' -Properties @{}
        ) -ResourceContainers @()
        $tm = @{}; foreach ($p in $shaped['trafficManagerProfiles']) { $tm[$p.name] = $p }
        $tm['tm'].dnsTtl | Should -Be 30
        $tm['tm'].alwaysServeEndpointCount | Should -Be 2
        $null -eq $tm['sparse'].dnsTtl | Should -BeTrue
        $tm['sparse'].alwaysServeEndpointCount | Should -Be 0
    }

    It 'flags a hub as backed up only with both gateways and ExpressRoute preferred, treating an unset preference as ExpressRoute' {
        $gateway = '/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.Network/expressRouteGateways/g'
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-DepthResource -Type 'microsoft.network/virtualhubs' -Name 'both' -Properties @{ expressRouteGateway = [pscustomobject]@{ id = $gateway }; vpnGateway = [pscustomobject]@{ id = "$gateway-vpn" }; hubRoutingPreference = 'ExpressRoute' }
            New-DepthResource -Type 'microsoft.network/virtualhubs' -Name 'unset' -Properties @{ expressRouteGateway = [pscustomobject]@{ id = $gateway }; vpnGateway = [pscustomobject]@{ id = "$gateway-vpn" } }
            New-DepthResource -Type 'microsoft.network/virtualhubs' -Name 'vpn-preferred' -Properties @{ expressRouteGateway = [pscustomobject]@{ id = $gateway }; vpnGateway = [pscustomobject]@{ id = "$gateway-vpn" }; hubRoutingPreference = 'VpnGateway' }
            New-DepthResource -Type 'microsoft.network/virtualhubs' -Name 'er-only' -Properties @{ expressRouteGateway = [pscustomobject]@{ id = $gateway }; hubRoutingPreference = 'ExpressRoute' }
            New-DepthResource -Type 'microsoft.network/virtualhubs' -Name 'none' -Properties @{}
        ) -ResourceContainers @()
        $hubs = @{}; foreach ($h in $shaped['virtualHubs']) { $hubs[$h.name] = $h }
        $hubs['both'].expressRouteBackedUp | Should -BeTrue
        $hubs['unset'].expressRouteBackedUp | Should -BeTrue
        $hubs['vpn-preferred'].expressRouteBackedUp | Should -BeFalse
        $hubs['er-only'].hasExpressRouteGateway | Should -BeTrue
        $hubs['er-only'].hasVpnGateway | Should -BeFalse
        $hubs['er-only'].expressRouteBackedUp | Should -BeFalse
        $hubs['none'].hasExpressRouteGateway | Should -BeFalse
        ($shaped | ConvertTo-Json -Depth 8) | Should -Not -Match 'expressRouteGateways/g'
    }

    It 'reads the PostgreSQL custom maintenance window and the registry id and subscription' {
        $shaped = ConvertFrom-ScoutInventory -Resources @(
            New-DepthResource -Type 'microsoft.dbforpostgresql/flexibleservers' -Name 'pg-on' -Properties @{ maintenanceWindow = [pscustomobject]@{ customWindow = 'Enabled'; dayOfWeek = 6 } }
            New-DepthResource -Type 'microsoft.dbforpostgresql/flexibleservers' -Name 'pg-default' -Properties @{ maintenanceWindow = [pscustomobject]@{ customWindow = 'Disabled' } }
            New-DepthResource -Type 'microsoft.dbforpostgresql/flexibleservers' -Name 'pg-unset' -Properties @{}
            New-DepthResource -Type 'microsoft.containerregistry/registries' -Name 'acr1' -Properties @{ adminUserEnabled = $false }
        ) -ResourceContainers @()
        $pg = @{}; foreach ($s in $shaped['postgreSqlFlexibleServers']) { $pg[$s.name] = $s }
        $pg['pg-on'].customMaintenanceWindow | Should -Be 'Enabled'
        $pg['pg-default'].customMaintenanceWindow | Should -Be 'Disabled'
        $pg['pg-unset'].customMaintenanceWindow | Should -Be ''
        $registry = @($shaped['containerRegistries'])[0]
        $registry.id | Should -BeLike '/subscriptions/sub1/*/acr1'
        $registry.subscriptionId | Should -Be 'sub1'
    }
}

Describe 'Typed Resource Graph query and shaper project the same fields' {
    # Every dataset whose columns changed. A column in one and not the other would be a field a rule reads
    # on one collection path and never sees on the other.
    It '<Key> projects exactly the properties the shaper emits' -ForEach @(
        @{ Key = 'containerApps'; Type = 'microsoft.app/containerapps' }
        @{ Key = 'containerAppEnvironments'; Type = 'microsoft.app/managedenvironments' }
        @{ Key = 'aksClusters'; Type = 'microsoft.containerservice/managedclusters' }
        @{ Key = 'containerRegistries'; Type = 'microsoft.containerregistry/registries' }
        @{ Key = 'apiManagement'; Type = 'microsoft.apimanagement/service' }
        @{ Key = 'firewallPolicies'; Type = 'microsoft.network/firewallpolicies' }
        @{ Key = 'appInsights'; Type = 'microsoft.insights/components' }
        @{ Key = 'trafficManagerProfiles'; Type = 'microsoft.network/trafficmanagerprofiles' }
        @{ Key = 'virtualHubs'; Type = 'microsoft.network/virtualhubs' }
        @{ Key = 'postgreSqlFlexibleServers'; Type = 'microsoft.dbforpostgresql/flexibleservers' }
    ) {
        $columns = @(Get-KqlProjectedColumn -Kql (Get-TypedQuery -Key $Key) | Sort-Object -Unique)
        $shaped = ConvertFrom-ScoutInventory -Resources @(New-DepthResource -Type $Type -Name 'sparse' -Properties @{}) -ResourceContainers @()
        $emitted = @(@($shaped[$Key])[0].PSObject.Properties.Name | Sort-Object -Unique)
        ($columns -join ',') | Should -Be ($emitted -join ',')
    }

    It 'subscriptions projects exactly the properties the shaper emits' {
        $columns = @(Get-KqlProjectedColumn -Kql (Get-TypedQuery -Key 'subscriptions') | Sort-Object -Unique)
        $shaped = ConvertFrom-ScoutInventory -Resources @() -ResourceContainers @([pscustomobject]@{ type = 'microsoft.resources/subscriptions'; name = 'a'; subscriptionId = 's1'; properties = [pscustomobject]@{ state = 'Enabled' }; tags = $null })
        $emitted = @(@($shaped['subscriptions'])[0].PSObject.Properties.Name | Sort-Object -Unique)
        ($columns -join ',') | Should -Be ($emitted -join ',')
    }

    It 'every new field is named in BOTH the typed query and the shaper' -ForEach @(
        @{ Key = 'subscriptions'; Fields = @('managementGroupLevels') }
        @{ Key = 'containerApps'; Fields = @('containerCount', 'containersWithoutAllProbes') }
        @{ Key = 'containerAppEnvironments'; Fields = @('logDestination', 'logsExported') }
        @{ Key = 'aksClusters'; Fields = @('azurePolicyAddon') }
        @{ Key = 'containerRegistries'; Fields = @('id', 'subscriptionId') }
        @{ Key = 'apiManagement'; Fields = @('legacyProtocolEnabled', 'legacyCipherEnabled') }
        @{ Key = 'firewallPolicies'; Fields = @('idpsEnabled', 'tlsInspectionEnabled', 'dnsProxyEnabled', 'hasBasePolicy', 'idpsTlsDnsEnabled') }
        @{ Key = 'appInsights'; Fields = @('disableIpMasking') }
        @{ Key = 'trafficManagerProfiles'; Fields = @('dnsTtl', 'alwaysServeEndpointCount') }
        @{ Key = 'virtualHubs'; Fields = @('hasExpressRouteGateway', 'hasVpnGateway', 'routingPreference', 'expressRouteBackedUp') }
        @{ Key = 'postgreSqlFlexibleServers'; Fields = @('customMaintenanceWindow') }
    ) {
        $columns = @(Get-KqlProjectedColumn -Kql (Get-TypedQuery -Key $Key))
        $shaperText = Get-Content (Join-Path $script:Root 'src/collect/ConvertFrom-ScoutInventory.ps1') -Raw
        foreach ($field in $Fields) {
            $columns | Should -Contain $field -Because "the typed $Key query must project $field"
            $shaperText | Should -Match "\b$field\s*=" -Because "the $Key shaper must emit $field"
        }
    }
}

Describe 'Nothing secret-bearing is projected by the new typed columns' {
    BeforeAll {
        $script:Pack = [regex]::Match($script:CollectSource, '(?s)\$q = @\{.*?\r?\n    \}').Value
        $script:PackKql = (($script:Pack -split "`r?`n") | Where-Object { $_ -notmatch '^\s*(//|#)' }) -join "`n"
    }

    It 'never reads a Container App secret, a registry credential, or a probe header or path' {
        $script:PackKql | Should -Not -Match 'configuration\.secrets'
        $script:PackKql | Should -Not -Match 'passwordSecretRef'
        $script:PackKql | Should -Not -Match 'httpHeaders|httpGet'
    }

    It 'reads only the seven named APIM customProperties keys, never the bag as a whole' {
        $apim = [regex]::Match($script:PackKql, "(?s)apiManagement = @'.*?\r?\n'@").Value
        $reads = @([regex]::Matches($apim, 'customProperties(\[[^\]]*\])?') | ForEach-Object { $_.Value })
        $reads.Count | Should -BeGreaterThan 0
        foreach ($read in $reads) { $read | Should -Match 'customProperties\["Microsoft\.WindowsAzure\.ApiManagement\.Gateway\.Security\.' }
        $apim | Should -Not -Match 'hostnameConfigurations|certificates|secret'
    }

    It 'reads the Firewall policy certificate authority only inside isnotempty(), as a bool' {
        $hits = @([regex]::Matches($script:PackKql, '[^\r\n]*certificateAuthority[^\r\n]*') | ForEach-Object { $_.Value })
        $hits.Count | Should -BeGreaterThan 0
        foreach ($hit in $hits) { $hit | Should -Match 'isnotempty\(tostring\(properties\.transportSecurity\.certificateAuthority\.keyVaultSecretId\)\)' }
    }

    It 'reads the Container Apps log configuration only for the destination name' {
        $env = [regex]::Match($script:PackKql, "(?s)containerAppEnvironments = @'.*?\r?\n'@").Value
        $env | Should -Not -Match 'logAnalyticsConfiguration|sharedKey|customerId|destinationsConfiguration'
        $env | Should -Match 'appLogsConfiguration\.destination'
    }

}

Describe 'Storage lifecycle policies: shaper' {
    BeforeAll {
        $script:StorageId = { param($n) "/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/$n" }
        $script:PolicyRow = {
            param([string] $Account, $Rules)
            [pscustomobject]@{
                id = (& $script:StorageId $Account) + '/managementPolicies/default'; name = 'default'
                TYPE = 'AZSC/ARMChild/StorageLifecyclePolicies'; PARENTID = (& $script:StorageId $Account); PARENTNAME = $Account; PARENTLOCATION = 'eastus'
                RESOURCEGROUP = 'rg1'; subscriptionId = 'sub1'
                properties = [pscustomobject]@{ policy = [pscustomobject]@{ rules = @($Rules) } }
            }
        }
        $script:Rule = {
            param([string] $Name, $Enabled, $Actions)
            $r = [ordered]@{ name = $Name; type = 'Lifecycle'; definition = [pscustomobject]@{ actions = [pscustomobject]$Actions; filters = [pscustomobject]@{ blobTypes = @('blockBlob'); prefixMatch = @('SENTINEL-PREFIX/') } } }
            if ($null -ne $Enabled) { $r['enabled'] = $Enabled }
            [pscustomobject]$r
        }
        $script:Operation = { param($Account, $Status) [pscustomobject]@{ Dataset = 'StorageLifecyclePolicies'; Status = $Status; ParentId = (& $script:StorageId $Account); Uri = 'u' } }
    }

    It 'counts rules, enabled rules, tiering rules and delete rules per account, and carries no rule name, prefix or filter' {
        $rows = @(
            New-DepthResource -Type 'microsoft.storage/storageaccounts' -Name 'tiered' -Properties @{} -Extra @{ sku = [pscustomobject]@{ name = 'Standard_LRS' }; kind = 'StorageV2' }
            New-DepthResource -Type 'microsoft.storage/storageaccounts' -Name 'premium' -Properties @{} -Extra @{ sku = [pscustomobject]@{ name = 'Premium_LRS' }; kind = 'BlockBlobStorage' }
            New-DepthResource -Type 'microsoft.storage/storageaccounts' -Name 'nopolicy' -Properties @{} -Extra @{ sku = [pscustomobject]@{ name = 'Standard_LRS' }; kind = 'StorageV2' }
            New-DepthResource -Type 'microsoft.storage/storageaccounts' -Name 'failed' -Properties @{} -Extra @{ sku = [pscustomobject]@{ name = 'Standard_LRS' }; kind = 'StorageV2' }
            (& $script:PolicyRow 'tiered' @(
                    (& $script:Rule 'r1' $true @{ baseBlob = [pscustomobject]@{ tierToCool = [pscustomobject]@{ daysAfterModificationGreaterThan = 30 }; delete = [pscustomobject]@{ daysAfterModificationGreaterThan = 365 } } })
                    (& $script:Rule 'r2' $null @{ version = [pscustomobject]@{ tierToArchive = [pscustomobject]@{ daysAfterCreationGreaterThan = 90 } } })
                    (& $script:Rule 'r3' $false @{ snapshot = [pscustomobject]@{ delete = [pscustomobject]@{ daysAfterCreationGreaterThan = 30 } } })))
            (& $script:PolicyRow 'premium' @((& $script:Rule 'only-delete' $true @{ baseBlob = [pscustomobject]@{ delete = [pscustomobject]@{ daysAfterModificationGreaterThan = 30 } } })))
        )
        $operations = @(
            (& $script:Operation 'tiered' 'Success'), (& $script:Operation 'premium' 'Success'),
            (& $script:Operation 'nopolicy' 'Empty'), (& $script:Operation 'failed' 'Failed')
        )
        $shaped = ConvertFrom-ScoutInventory -Resources $rows -ResourceContainers @() -SourceOperations $operations
        $shaped['lifecyclePoliciesMeasured'] | Should -BeTrue
        $byName = @{}; foreach ($r in $shaped['lifecyclePolicies']) { $byName[$r.name] = $r }
        @($shaped['lifecyclePolicies']).Count | Should -Be 3 -Because 'the account whose GET failed has no row'
        $byName.ContainsKey('failed') | Should -BeFalse

        $t = $byName['tiered']
        $t.storageAccountId | Should -Be (& $script:StorageId 'tiered').ToLowerInvariant()
        $t.premium | Should -BeFalse
        $t.policyPresent | Should -BeTrue
        $t.ruleCount | Should -Be 3
        $t.enabledRuleCount | Should -Be 2 -Because 'an explicit enabled=false is off, a missing flag is on'
        $t.tieringRuleCount | Should -Be 2
        $t.deleteRuleCount | Should -Be 1 -Because 'the disabled rule does not count'

        $p = $byName['premium']
        $p.premium | Should -BeTrue
        $p.tieringRuleCount | Should -Be 0
        $p.deleteRuleCount | Should -Be 1

        $n = $byName['nopolicy']
        $n.policyPresent | Should -BeFalse
        $n.ruleCount | Should -Be 0
        $n.enabledRuleCount | Should -Be 0
        $n.tieringRuleCount | Should -Be 0
        $n.deleteRuleCount | Should -Be 0
        ($shaped | ConvertTo-Json -Depth 8) | Should -Not -Match 'SENTINEL-'
    }

    It 'recovers the account from the request path when an inventory banked before this dataset recorded a ParentId is shaped' {
        $oldOperation = [pscustomobject]@{ Dataset = 'StorageLifecyclePolicies'; Status = 'Empty'; Uri = (& $script:StorageId 'st-old') + '/managementPolicies/default?api-version=2023-05-01' }
        $account = New-DepthResource -Type 'microsoft.storage/storageaccounts' -Name 'st-old' -Properties @{} -Extra @{ kind = 'StorageV2' }
        $shaped = ConvertFrom-ScoutInventory -Resources @($account) -ResourceContainers @() -SourceOperations @($oldOperation)
        $shaped['lifecyclePoliciesMeasured'] | Should -BeTrue
        @($shaped['lifecyclePolicies']).Count | Should -Be 1 -Because 'a 404 on an account with no policy is the finding, even in an old dump'
        $shaped['lifecyclePolicies'][0].policyPresent | Should -BeFalse
        $shaped['lifecyclePolicies'][0].name | Should -Be 'st-old'
    }

    It 'is unmeasured, with no rows, when no GET of the dataset was answered' {
        $account = New-DepthResource -Type 'microsoft.storage/storageaccounts' -Name 'st1' -Properties @{} -Extra @{ kind = 'StorageV2' }
        $failed = ConvertFrom-ScoutInventory -Resources @($account) -ResourceContainers @() -SourceOperations @((& $script:Operation 'st1' 'Failed'))
        $failed['lifecyclePoliciesMeasured'] | Should -BeFalse
        @($failed['lifecyclePolicies']).Count | Should -Be 0
        $none = ConvertFrom-ScoutInventory -Resources @($account) -ResourceContainers @()
        $none['lifecyclePoliciesMeasured'] | Should -BeFalse
        @($none['lifecyclePolicies']).Count | Should -Be 0
    }
}

Describe 'Storage lifecycle policies: the ARM sweep and its wiring' {
    BeforeAll {
        . (Join-Path $script:Root 'src/collect/Get-ScoutArmChildResource.ps1')
        $script:Requested = [System.Collections.Generic.List[string]]::new()
        function global:Invoke-AzRestMethod {
            [CmdletBinding()]
            param([string] $Path, [string] $Method)
            $null = $Method
            $script:Requested.Add($Path)
            if ($Path -match 'st-none') {
                $exception = [System.InvalidOperationException]::new('ARM status code 404')
                $exception.Data['StatusCode'] = 404
                throw $exception
            }
            [pscustomobject]@{ StatusCode = 200; Content = '{"id":"x/managementPolicies/default","name":"default","properties":{"policy":{"rules":[{"name":"r","enabled":true,"definition":{"actions":{"baseBlob":{"tierToCool":{"daysAfterModificationGreaterThan":30}}}}}]}}}' }
        }
    }
    AfterAll { Remove-Item function:Invoke-AzRestMethod -ErrorAction SilentlyContinue }

    It 'asks only the blob-capable storage kinds, one GET each, and records the parent id on every operation' {
        $script:Requested.Clear()
        $accounts = foreach ($spec in @(@('st-v2', 'StorageV2'), @('st-blob', 'BlobStorage'), @('st-premium', 'BlockBlobStorage'), @('st-v1', 'Storage'), @('st-file', 'FileStorage'), @('st-none', 'StorageV2'), @('st-unknown', $null))) {
            $row = [ordered]@{ id = "/subscriptions/sub1/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/$($spec[0])"; name = $spec[0]; type = 'microsoft.storage/storageaccounts'; location = 'eastus'; resourceGroup = 'rg1'; subscriptionId = 'sub1' }
            if ($spec[1]) { $row['kind'] = $spec[1] }
            [pscustomobject]$row
        }
        $operations = [System.Collections.Generic.List[object]]::new()
        $rows = @(Get-ScoutArmChildResource -Resources @($accounts) -Dataset StorageLifecyclePolicies -SourceOperations $operations -Execution InProcess)
        $asked = @($script:Requested | ForEach-Object { ($_ -split '/storageAccounts/')[1] -replace '/.*$', '' } | Sort-Object)
        $asked | Should -Be @('st-blob', 'st-none', 'st-premium', 'st-unknown', 'st-v2')
        $script:Requested | ForEach-Object { $_ | Should -Match '/managementPolicies/default\?api-version=2023-05-01$' }
        $rows.Count | Should -Be 4 -Because 'the 404 is empty data, not a row'
        $rows[0].TYPE | Should -Be 'AZSC/ARMChild/StorageLifecyclePolicies'
        $rows[0].properties.policy.rules.Count | Should -Be 1 -Because 'the worksheet reads the whole response, so the row is not reduced'
        @($operations | Where-Object { -not $_.ParentId }).Count | Should -Be 0
        @($operations | Where-Object { $_.Status -eq 'Empty' }).Count | Should -Be 1
    }

    It 'joins the shared per-parent apply step, so it is fetched in the 8-wide parallel batch' {
        $source = Get-Content (Join-Path $script:Root 'src/collect/Get-ScoutArmChildResource.ps1') -Raw
        $parallel = [regex]::Match($source, "(?s)\`$ParallelDatasets = @\((.*?)\r?\n    \)").Groups[1].Value
        $parallel | Should -Match "'StorageLifecyclePolicies'"
        $source | Should -Match "(?s)'StorageLifecyclePolicies' \{\s+foreach \(\`$Parent in \`$StorageAccountParents\)"
        # exactly one explicit sequential case would double every row: the switch runs every matching clause
        @([regex]::Matches($source, "(?m)^\s+'StorageLifecyclePolicies' \{")).Count | Should -Be 1
    }

    It 'is read by the assessment path, and its shaped rows reach domains.storage' {
        $script:CollectSource | Should -Match "(?s)\`$rawArgs\.ArmChildDataset = @\(.*?'StorageLifecyclePolicies'.*?\)"
        $script:CollectSource | Should -Match 'lifecyclePolicies = \$r\.lifecyclePolicies'
        $script:CollectSource | Should -Match "lifecyclePoliciesMeasured = \[bool\]\`$r\['lifecyclePoliciesMeasured'\]"
        $script:CollectSource | Should -Match "\`$r\['lifecyclePolicies'\] = "
        $script:CollectSource | Should -Match "\`$r\['lifecyclePoliciesMeasured'\] = "
    }
}

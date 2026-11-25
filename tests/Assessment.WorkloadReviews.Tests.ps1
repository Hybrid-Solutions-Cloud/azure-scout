#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300 phase 1: the Azure Virtual Desktop (AVD in Azure) workload review and the AI workload
    review's new design areas. Each rule set is run against a small collect object built here, so
    every automated rule's Pass/Fail is pinned, gated rules are proven NotAssessed on an estate
    without the resource, and no rule errors.
#>

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    Import-Module "$script:root/AzureScout.psd1" -Force -ErrorAction Stop
    $script:Module = Get-Module AzureScout | Where-Object { $_.ModuleBase -eq $script:root } | Select-Object -First 1
    Import-Module powershell-yaml

    function Invoke-ScoutTestRuleSet {
        param([string] $Pattern, $Collect, [string] $Assessment)
        & $script:Module {
            param($p, $c, $a)
            $sets = Get-RuleSet -Patterns $p
            $json = $c | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
            @(Invoke-Assessment -Collect $json -RuleSet $sets -Assessment $a)
        } $Pattern $Collect $Assessment
    }

    $sub = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers'
    $script:AvdCollect = [ordered]@{
        compute    = [ordered]@{
            virtualMachines = @(
                [ordered]@{ id = "$sub/Microsoft.Compute/virtualMachines/sh-good"; zoneEligible = $true; zoneRedundant = $true; osType = 'Windows'; licenseType = 'Windows_Client'; assessmentMode = 'AutomaticByPlatform' }
                [ordered]@{ id = "$sub/Microsoft.Compute/virtualMachines/sh-bad"; zoneEligible = $true; zoneRedundant = $false; osType = 'Windows'; licenseType = ''; assessmentMode = 'ImageDefault' }
            )
            avdHostPools = @(
                [ordered]@{ id = "$sub/Microsoft.DesktopVirtualization/hostPools/pooled-ok"; hostPoolType = 'Pooled'; maxSessionLimit = 12; startVMOnConnect = $false; validationEnvironment = $true; publicNetworkAccess = 'Disabled'; agentUpdateType = 'Scheduled' }
                [ordered]@{ id = "$sub/Microsoft.DesktopVirtualization/hostPools/pooled-bad"; hostPoolType = 'Pooled'; maxSessionLimit = 999999; startVMOnConnect = $false; validationEnvironment = $false; publicNetworkAccess = 'Enabled'; agentUpdateType = 'Default' }
                [ordered]@{ id = "$sub/Microsoft.DesktopVirtualization/hostPools/personal"; hostPoolType = 'Personal'; maxSessionLimit = 1; startVMOnConnect = $false; validationEnvironment = $false; publicNetworkAccess = 'Disabled'; agentUpdateType = 'Scheduled' }
            )
            avdSessionHosts = @(
                [ordered]@{ name = 'pooled-ok/sh-good'; status = 'Available'; updateState = 'Succeeded'; resourceId = "$sub/Microsoft.Compute/virtualMachines/sh-good" }
                [ordered]@{ name = 'pooled-bad/sh-bad'; status = 'Unavailable'; updateState = 'Failed'; resourceId = "$sub/Microsoft.Compute/virtualMachines/sh-bad" }
            )
            avdScalingPlans = @(
                [ordered]@{ name = 'sp'; hostPoolRefCount = 1; enabledHostPools = @([ordered]@{ id = "$sub/microsoft.desktopvirtualization/hostpools/pooled-ok".ToLowerInvariant() }) }
            )
            avdWorkspaces = @(
                [ordered]@{ id = "$sub/Microsoft.DesktopVirtualization/workspaces/ws"; publicNetworkAccess = 'Enabled' }
            )
        }
        networking = [ordered]@{
            privateEndpoints = @([ordered]@{ targetResourceId = "$sub/Microsoft.DesktopVirtualization/hostPools/pooled-ok" })
            nsgPublicInbound = @()
        }
        security   = [ordered]@{ defenderPlans = @([ordered]@{ name = 'VirtualMachines'; properties = [ordered]@{ pricingTier = 'Standard' } }) }
        domains    = [ordered]@{ storage = [ordered]@{ storageAccounts = @() } }
        management = [ordered]@{ backupProtectedItems = @() }
        monitor    = [ordered]@{ dataCollectionRules = @(); activityLogAlertRules = @() }
    }
    $script:AvdFindings = @(Invoke-ScoutTestRuleSet -Pattern 'waf.avd.azure' -Collect $script:AvdCollect -Assessment 'Workload: AVD')
    $script:AvdById = @{}; foreach ($f in $script:AvdFindings) { $script:AvdById[[string]$f.Id] = $f }
}

Describe 'Workload: AVD (AVD in Azure)' {
    It 'loads 30 rules with unique ids, every one citing its own id' {
        $set = & $script:Module { Get-RuleSet -Patterns 'waf.avd.azure' }
        @($set.Rules).Count | Should -Be 30
        @($set.Rules.id | Select-Object -Unique).Count | Should -Be 30
        foreach ($r in $set.Rules) { $r.title | Should -BeLike "$($r.id).*"; $r.remediation | Should -BeLike "$($r.id).*" }
    }

    It 'every rule id is enumerated in the checklist doc' {
        $doc = Get-Content "$script:root/docs/frameworks/waf-avd-azure-workload-checklist.md" -Raw
        foreach ($f in $script:AvdFindings) { $doc | Should -Match ([regex]::Escape([string]$f.Id)) }
    }

    It 'is registered as its own assessment and leaves the Azure Local review unchanged' {
        $m = Import-PowerShellDataFile "$script:root/manifests/assessments.psd1"
        $m['Workload: AVD'].Rules | Should -Be @('waf.avd.azure')
        $m['Assess: AVD Workload'].Rules | Should -Be @('waf.avd')
    }

    It 'produces no Error findings' {
        @($script:AvdFindings | Where-Object Status -eq 'Error').Count | Should -Be 0
    }

    It 'scores <Id> as <Status>' -ForEach @(
        @{ Id = 'WAF-AVDAZ-RE-01'; Status = 'Fail' }   # sh-bad has no zone
        @{ Id = 'WAF-AVDAZ-RE-02'; Status = 'Fail' }   # sh-bad Unavailable
        @{ Id = 'WAF-AVDAZ-SE-01'; Status = 'Fail' }   # pooled-bad public
        @{ Id = 'WAF-AVDAZ-SE-02'; Status = 'Fail' }   # workspace public
        @{ Id = 'WAF-AVDAZ-SE-03'; Status = 'Fail' }   # two pools without a private endpoint
        @{ Id = 'WAF-AVDAZ-SE-05'; Status = 'Pass' }   # Defender for Servers Standard
        @{ Id = 'WAF-AVDAZ-SE-09'; Status = 'Fail' }   # sh-bad not on periodic assessment
        @{ Id = 'WAF-AVDAZ-CO-01'; Status = 'Fail' }   # pooled-bad has no enabled scaling plan
        @{ Id = 'WAF-AVDAZ-CO-02'; Status = 'Fail' }   # personal pool without Start VM on Connect
        @{ Id = 'WAF-AVDAZ-CO-03'; Status = 'Fail' }   # sh-bad has no licence type
        @{ Id = 'WAF-AVDAZ-CO-04'; Status = 'Fail' }   # pooled-bad at the default limit
        @{ Id = 'WAF-AVDAZ-OE-01'; Status = 'Pass' }   # pooled-ok is a validation pool
        @{ Id = 'WAF-AVDAZ-OE-02'; Status = 'Fail' }   # pooled-bad not scheduled
        @{ Id = 'WAF-AVDAZ-OE-04'; Status = 'Fail' }   # sh-bad update failed
        @{ Id = 'WAF-AVDAZ-SE-06'; Status = 'Manual' }
    ) {
        $script:AvdById[$Id].Status | Should -Be $Status
    }

    It 'names only the offending resources in a failing join' {
        $f = $script:AvdById['WAF-AVDAZ-CO-01']
        $f.EvidenceCount | Should -Be 1
    }

    It 'reports every automated rule NotAssessed on an estate with no AVD' {
        $empty = [ordered]@{
            compute = [ordered]@{ virtualMachines = @(); avdHostPools = @(); avdSessionHosts = @(); avdScalingPlans = @(); avdWorkspaces = @() }
            networking = [ordered]@{ privateEndpoints = @() }; security = [ordered]@{ defenderPlans = @() }
        }
        $findings = @(Invoke-ScoutTestRuleSet -Pattern 'waf.avd.azure' -Collect $empty -Assessment 'Workload: AVD')
        @($findings | Where-Object { $_.Status -in 'Pass', 'Fail', 'Partial', 'Error' }).Count | Should -Be 0
        @($findings | Where-Object Status -eq 'NotAssessed').Count | Should -Be 15
    }
}

Describe 'Assess: AI Workload — all ten design areas' {
    BeforeAll {
        $script:AiSet = & $script:Module { Get-RuleSet -Patterns 'waf.ai' }
        $script:AiCollect = [ordered]@{
            domains = [ordered]@{
                ai = [ordered]@{
                    cognitiveAccounts = @(
                        [ordered]@{ id = 'a1'; name = 'oai'; accountKind = 'OpenAI'; publicAccess = 'Disabled'; disableLocalAuth = $true }
                        [ordered]@{ id = 'a2'; name = 'lang'; accountKind = 'TextAnalytics'; publicAccess = 'Enabled'; disableLocalAuth = $null }
                    )
                    mlWorkspaces = @([ordered]@{ id = 'w1'; name = 'ml'; workspaceKind = 'Default'; publicAccess = 'Enabled'; isolationMode = 'Disabled' })
                    searchServices = @(
                        [ordered]@{ id = 's1'; name = 'srch'; sku = 'standard'; replicaCount = 3; publicAccess = 'disabled' }
                        [ordered]@{ id = 's2'; name = 'free'; sku = 'free'; replicaCount = 1; publicAccess = 'enabled' }
                    )
                }
                analytics = [ordered]@{ purviewAccounts = @(); dataFactories = @([ordered]@{ name = 'adf'; publicNetworkAccess = 'Enabled' }) }
            }
        }
        $findings = @(Invoke-ScoutTestRuleSet -Pattern 'waf.ai' -Collect $script:AiCollect -Assessment 'Assess: AI Workload')
        $script:AiById = @{}; foreach ($f in $findings) { $script:AiById[[string]$f.Id] = $f }
        $script:AiFindings = $findings
    }

    It 'has 63 rules covering all ten design areas plus the architecture pattern' {
        @($script:AiSet.Rules).Count | Should -Be 63
        foreach ($prefix in 'APPD', 'APPP', 'TRAIN', 'GROUND', 'MLOPS', 'OPS', 'RAI', 'DATA', 'TEST', 'PERSONA', 'ARCH') {
            @($script:AiSet.Rules | Where-Object { $_.id -like "WAF-AI-$prefix-*" }).Count | Should -BeGreaterThan 0 -Because "design area $prefix must be covered"
        }
        @($script:AiSet.Rules | Where-Object { $_.id -eq 'WAF-AI-GROUND-05' }).Count | Should -Be 1
    }

    It 'every rule id is enumerated in the checklist doc' {
        $doc = Get-Content "$script:root/docs/frameworks/waf-ai-workload-checklist.md" -Raw
        foreach ($r in $script:AiSet.Rules) { $doc | Should -Match ([regex]::Escape([string]$r.id)) }
    }

    It 'produces no Error findings' {
        @($script:AiFindings | Where-Object Status -eq 'Error').Count | Should -Be 0
    }

    It 'scores <Id> as <Status>' -ForEach @(
        @{ Id = 'WAF-AI-DATA-04'; Status = 'Fail' }   # no Purview
        @{ Id = 'WAF-AI-DATA-05'; Status = 'Fail' }   # public data factory
        @{ Id = 'WAF-AI-DATA-07'; Status = 'Fail' }   # free-tier search
        @{ Id = 'WAF-AI-DATA-08'; Status = 'Fail' }   # public search
        @{ Id = 'WAF-AI-ARCH-01'; Status = 'Fail' }   # public ML workspace
        @{ Id = 'WAF-AI-ARCH-02'; Status = 'Fail' }   # no managed network
        @{ Id = 'WAF-AI-ARCH-05'; Status = 'Fail' }   # local auth not disabled on 'lang'
        @{ Id = 'WAF-AI-TEST-01'; Status = 'Manual' }
        @{ Id = 'WAF-AI-PERSONA-01'; Status = 'Manual' }
    ) {
        $script:AiById[$Id].Status | Should -Be $Status
    }

    It 'gates the new automated AI checks to NotAssessed on an estate with no AI resources' {
        $empty = [ordered]@{ domains = [ordered]@{ ai = [ordered]@{ cognitiveAccounts = @(); mlWorkspaces = @(); searchServices = @() }; analytics = [ordered]@{ purviewAccounts = @(); dataFactories = @() } } }
        $findings = @(Invoke-ScoutTestRuleSet -Pattern 'waf.ai' -Collect $empty -Assessment 'Assess: AI Workload')
        foreach ($id in 'WAF-AI-DATA-04', 'WAF-AI-DATA-05', 'WAF-AI-DATA-07', 'WAF-AI-DATA-08', 'WAF-AI-ARCH-01', 'WAF-AI-ARCH-02', 'WAF-AI-ARCH-05') {
            ($findings | Where-Object Id -eq $id).Status | Should -Be 'NotAssessed' -Because "$id must not fail an estate with nothing to check"
        }
    }
}

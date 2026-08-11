#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    . "$script:RepoRoot/src/Start-AZTIExtractionOrchestration.ps1"
    . "$script:RepoRoot/src/collect/Start-ScoutGraphExtraction.ps1"
    . "$script:RepoRoot/src/collect/Get-ScoutRawInventory.ps1"
}

Describe 'category-aware extraction plan' {
    It 'preserves full collection for the default, unknown values, and assessment-backed runs' {
        (Resolve-AZSCExtractionCategoryPlan).IsFull | Should -BeTrue
        (Resolve-AZSCExtractionCategoryPlan -Category 'NotARealCategory').IsFull | Should -BeTrue

        $assessmentPlan = Resolve-AZSCExtractionCategoryPlan -Category 'Compute' -PreserveAssessmentDependencies
        $assessmentPlan.IsFull | Should -BeTrue
        $assessmentPlan.CollectTenantWideResources | Should -BeTrue
        $assessmentPlan.CollectGovernance | Should -BeTrue
        $assessmentPlan.IncludeEntra | Should -BeTrue
    }

    It 'keeps manifest-referenced Compute dependencies while excluding unrelated remote datasets' {
        $plan = Resolve-AZSCExtractionCategoryPlan -Category 'Compute'

        $plan.IsFull | Should -BeFalse
        $plan.ResourceTypes | Should -Contain 'microsoft.compute/virtualmachines'
        $plan.ResourceTypes | Should -Contain 'microsoft.network/networkinterfaces'
        $plan.ResourceTypes | Should -Contain 'microsoft.compute/disks'
        $plan.CollectNetworkTable | Should -BeTrue
        $plan.IncludeVmDetails | Should -BeTrue
        $plan.IncludeOperationalCollectorEnrichment | Should -BeTrue
        # VM setup preambles consume protected-item/backup-policy rows, so the closure must
        # retain this non-obvious cross-table dependency.
        $plan.IncludeBackupResources | Should -BeTrue
        $plan.PSObject.Properties.Name | Should -Not -Contain 'IncludeLighthouseDelegations'
        $plan.CollectTenantWideResources | Should -BeFalse
        $plan.CollectGovernance | Should -BeFalse
        $plan.IncludeEntra | Should -BeFalse
        $plan.IncludeDevOps | Should -BeFalse
    }

    It 'retains cross-service dependencies for Identity and Management' {
        $identity = Resolve-AZSCExtractionCategoryPlan -Category 'Identity'
        $identity.IncludeEntra | Should -BeTrue
        $identity.CollectGovernance | Should -BeTrue
        $identity.ResourceTypes | Should -Contain 'microsoft.managedidentity/userassignedidentities'

        $management = Resolve-AZSCExtractionCategoryPlan -Category 'Management'
        $management.CollectTenantWideResources | Should -BeTrue
        $management.CollectGovernance | Should -BeTrue
        $management.IncludeApiResourceSweep | Should -BeTrue
        $management.IncludeBackupResources | Should -BeTrue
        $management.PSObject.Properties.Name | Should -Not -Contain 'IncludeLighthouseDelegations'
    }
}

Describe 'category plan production plumbing' {
    BeforeEach {
        $script:RawSplat = $null
        function Get-ScoutRawInventory {
            [CmdletBinding()]
            param(
                $SubscriptionIds, $IncludeSupportResources, $IncludeBackupResources,
                $IncludeDesktopVirtualization, $IncludeUpdateManagerResources,
                $IncludeRetirements, $IncludeAdvisories,
                $IncludeSecurityCenter, $IncludeArmChildResources, $ArmChildDataset,
                $IncludeOperationalCollectorEnrichment, $IncludeSubscriptionSecurityPolicy,
                $SkipApiResourceSweep, $SkipPolicy, $IncludeTags, $AzureEnvironment,
                $CollectResourceTable, $CollectNetworkTable, $CollectTenantWideResources,
                $CollectGovernance, $ResourceTypes, $ResourceGroups, $TagKey, $TagValue,
                $ManagementGroupName
            )
            $script:RawSplat = @{} + $PSBoundParameters
            [pscustomobject]@{
                Resources = @(); ResourceContainers = @(); Advisories = @(); Security = @()
                Retirements = @(); ApiResources = @(); Governance = $null
            }
        }
    }

    It 'threads a selected category plan to the raw extractor and suppresses unneeded calls' {
        $plan = Resolve-AZSCExtractionCategoryPlan -Category 'Storage'
        $null = Start-AZSCGraphExtraction -Subscriptions @([pscustomobject]@{ id = 'sub-1' }) `
            -AzureEnvironment 'AzureCloud' -CategoryPlan $plan

        $script:RawSplat.CollectResourceTable | Should -BeTrue
        $script:RawSplat.CollectNetworkTable | Should -BeFalse
        $script:RawSplat.CollectTenantWideResources | Should -BeFalse
        $script:RawSplat.CollectGovernance | Should -BeFalse
        [bool]$script:RawSplat.SkipApiResourceSweep | Should -BeTrue
        [bool]$script:RawSplat.IncludeBackupResources | Should -BeFalse
        [bool]$script:RawSplat.IncludeDesktopVirtualization | Should -BeFalse
        $script:RawSplat.Keys | Should -Not -Contain 'IncludeLighthouseDelegations'
        @($script:RawSplat.ResourceTypes).Count | Should -BeGreaterThan 0
    }

    It 'leaves the established full/default raw splat unchanged' {
        $null = Start-AZSCGraphExtraction -Subscriptions @([pscustomobject]@{ id = 'sub-1' }) `
            -AzureEnvironment 'AzureCloud'

        $script:RawSplat.Keys | Should -Not -Contain 'CollectResourceTable'
        $script:RawSplat.Keys | Should -Not -Contain 'CollectNetworkTable'
        $script:RawSplat.Keys | Should -Not -Contain 'CollectTenantWideResources'
        $script:RawSplat.Keys | Should -Not -Contain 'CollectGovernance'
        $script:RawSplat.Keys | Should -Not -Contain 'ResourceTypes'
        [bool]$script:RawSplat.IncludeBackupResources | Should -BeTrue
        [bool]$script:RawSplat.IncludeDesktopVirtualization | Should -BeTrue
        $script:RawSplat.Keys | Should -Not -Contain 'IncludeLighthouseDelegations'
        [bool]$script:RawSplat.SkipApiResourceSweep | Should -BeFalse
    }

    It 'passes Category from the public entry point and protects combined assessment dependencies' {
        $source = Get-Content -LiteralPath "$script:RepoRoot/src/Invoke-AzureScout.ps1" -Raw
        $call = [regex]::Match($source, '(?s)Start-AZSCExtractionOrchestration\s+.+?-Category\s+\$Category.+?-PreserveAssessmentDependencies:\(\$null -ne \$deferredAssessArgs\)')
        $call.Success | Should -BeTrue
    }
}

Describe 'selective raw Resource Graph queries' {
    BeforeEach {
        $script:Queries = [System.Collections.Generic.List[string]]::new()
        Mock Import-Module {}
        Mock Search-AzGraph {
            $script:Queries.Add([string]$Query)
            return @()
        }
    }

    It 'does not call unneeded resource and network tables' {
        $null = Get-ScoutRawInventory -CollectResourceTable:$false -CollectNetworkTable:$false `
            -CollectTenantWideResources:$false -CollectGovernance:$false -SkipApiResourceSweep

        @($script:Queries).Count | Should -Be 1
        $script:Queries[0] | Should -Match '^resourcecontainers '
    }

    It 'applies the dependency closure as a server-side resources type filter' {
        $null = Get-ScoutRawInventory -ResourceTypes @('microsoft.compute/virtualmachines', 'microsoft.compute/disks') `
            -CollectNetworkTable:$false -CollectTenantWideResources:$false -CollectGovernance:$false `
            -SkipApiResourceSweep

        @($script:Queries).Count | Should -Be 2
        $resourceQuery = @($script:Queries | Where-Object { $_ -match '^resources ' })[0]
        $resourceQuery | Should -Match "type in~ \('microsoft.compute/disks','microsoft.compute/virtualmachines'\)"
        @($script:Queries | Where-Object { $_ -match '^networkresources ' }).Count | Should -Be 0
    }
}

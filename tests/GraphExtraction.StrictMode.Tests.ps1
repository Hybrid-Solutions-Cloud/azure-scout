#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#5547 — regression test for the unset $MGContainerExtension crash.

    Start-AZSCGraphExtraction consumed $MGContainerExtension unconditionally in the
    resourcecontainers query but only assigned it inside the -ManagementGroup branch, so an
    inventory run WITHOUT -ManagementGroup threw "The variable '$MGContainerExtension' cannot be
    retrieved because it has not been set" as soon as the caller had StrictMode on.

    This was found by a live tenant run, NOT by the suite: all 1688 tests passed while the bug was
    present, because nothing invoked the extractor from a StrictMode caller. That is the gap this
    file closes — it drives the real function under Set-StrictMode -Version Latest with the Azure
    calls stubbed out, so the variable-initialisation contract is enforced offline from now on.

    No Azure connection.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . "$root/Modules/Private/Extraction/Start-AZTIGraphExtraction.ps1"

    # Stub the two Azure-touching dependencies. Each records the queries it was handed so the
    # tests can assert on what the extractor built.
    function Invoke-AZSCInventoryLoop {
        param($GraphQuery, $FSubscri, $LoopName)
        $script:capturedQueries += [pscustomobject]@{ LoopName = $LoopName; Query = $GraphQuery }
        return @()
    }
    function Get-AZSCManagementGroups {
        param($ManagementGroup, $Subscriptions)
        return $Subscriptions
    }

    $script:subs = @([pscustomobject]@{ id = 'sub1'; name = 'Sub One' })

    # The function's switch-ish parameters are declared untyped (legacy v1 signature) and are
    # tested with `.IsPresent`, so they only work when the caller passes a real SwitchParameter.
    # Invoke-AzureScout always does, via Start-AZSCExtractionOrchestration — mirror that contract
    # here rather than relying on the $null default, which is a separate latent fragility in this
    # file and out of scope for AB#5547.
    $script:switchArgs = @{
        IncludeTags    = [switch]$false
        SkipAdvisory   = [switch]$true
        SecurityCenter = [switch]$false
    }
}

Describe 'Start-AZSCGraphExtraction under StrictMode (AB#5547)' {

    BeforeEach { $script:capturedQueries = @() }

    It 'does not throw on an unset variable when no -ManagementGroup is supplied' {
        Set-StrictMode -Version Latest
        {
            Start-AZSCGraphExtraction -Subscriptions $script:subs -AzureEnvironment 'AzureCloud' `
                @script:switchArgs 3>$null 4>$null 6>$null | Out-Null
        } | Should -Not -Throw
    }

    It 'builds the resourcecontainers query with an empty management-group extension' {
        Set-StrictMode -Version Latest
        Start-AZSCGraphExtraction -Subscriptions $script:subs -AzureEnvironment 'AzureCloud' `
            @script:switchArgs 3>$null 4>$null 6>$null | Out-Null

        $containerQuery = ($script:capturedQueries |
                Where-Object { $_.LoopName -eq 'Subscriptions and Resource Groups' }).Query
        $containerQuery | Should -Not -BeNullOrEmpty
        $containerQuery | Should -Match 'resourcecontainers'
        # The management-group join must be absent entirely, not rendered as a literal null.
        $containerQuery | Should -Not -Match 'managementGroupAncestorsChain'
    }

    It 'still injects the management-group extension when -ManagementGroup IS supplied' {
        Set-StrictMode -Version Latest
        Start-AZSCGraphExtraction -Subscriptions $script:subs -AzureEnvironment 'AzureCloud' `
            -ManagementGroup 'mg-root' @script:switchArgs 3>$null 4>$null 6>$null | Out-Null

        $containerQuery = ($script:capturedQueries |
                Where-Object { $_.LoopName -eq 'Subscriptions and Resource Groups' }).Query
        $containerQuery | Should -Match 'managementGroupAncestorsChain'
        $containerQuery | Should -Match 'mg-root'
    }

    It 'returns the documented shape rather than a bare collection' {
        Set-StrictMode -Version Latest
        $result = Start-AZSCGraphExtraction -Subscriptions $script:subs -AzureEnvironment 'AzureCloud' `
            @script:switchArgs 3>$null 4>$null 6>$null

        foreach ($field in 'Resources', 'ResourceContainers', 'Advisories', 'Security', 'Retirements') {
            $result.PSObject.Properties.Name | Should -Contain $field
        }
    }
}

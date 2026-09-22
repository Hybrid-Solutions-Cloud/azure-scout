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

    AB#5648 update: Start-AZSCGraphExtraction no longer builds queries or issues Resource Graph
    calls — it is a shim over src/collect/Get-ScoutRawInventory.ps1, and the
    Invoke-AZSCInventoryLoop stub this file used to install no longer exists. The stub therefore
    moved DOWN one layer to Search-AzGraph itself, which makes these assertions stronger rather
    than weaker: they now pin the query text that actually reaches Resource Graph through the
    whole (shim -> single-pass collector) call path, not the text handed to an intermediate
    function.

    No Azure connection.
#>

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    # Neutralise Import-Module so Get-ScoutRawInventory's `Import-Module Az.ResourceGraph`
    # cannot pull the real module (and therefore the real Search-AzGraph) into this session.
    function Import-Module { param([Parameter(ValueFromRemainingArguments)] $Rest) }
    . "$root/src/collect/Get-ScoutRawInventory.ps1"
    . "$root/src/collect/Start-ScoutGraphExtraction.ps1"

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

    BeforeEach {
        $script:capturedQueries = @()
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            $script:capturedQueries += $Query
            return @()
        }
    }

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

        $containerQuery = @($script:capturedQueries | Where-Object { $_ -match '^resourcecontainers\b' })
        $containerQuery.Count | Should -BeGreaterThan 0
        # The management-group join must be absent entirely, not rendered as a literal null.
        ($containerQuery -join "`n") | Should -Not -Match 'managementGroupAncestorsChain'
    }

    It 'still injects the management-group extension when -ManagementGroup IS supplied' {
        Set-StrictMode -Version Latest
        Start-AZSCGraphExtraction -Subscriptions $script:subs -AzureEnvironment 'AzureCloud' `
            -ManagementGroup 'mg-root' @script:switchArgs 3>$null 4>$null 6>$null | Out-Null

        $containerQuery = @($script:capturedQueries | Where-Object { $_ -match '^resourcecontainers\b' }) -join "`n"
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

Describe 'Start-AZSCGraphExtraction issues no Resource Graph query of its own (AB#5648)' {

    BeforeEach {
        $script:capturedQueries = @()
        function Search-AzGraph {
            param([string] $Query, [int] $First, [string] $SkipToken, [string] $ManagementGroup, [string[]] $Subscription, [string] $ErrorAction)
            $script:capturedQueries += $Query
            return @()
        }
    }

    It 'the shim invokes no Resource Graph cmdlet and no retired extraction function' {
        # Asserted against the AST's COMMAND names, not the raw file text: this file's own
        # comments name both retired functions (explaining what replaced them), and a text
        # match cannot tell an explanation from a call.
        $root = Split-Path $PSScriptRoot -Parent
        $path = "$root/src/collect/Start-ScoutGraphExtraction.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $commands = @(
            $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }
        )
        $commands | Should -Not -Contain 'Search-AzGraph'
        $commands | Should -Not -Contain 'Invoke-AZSCInventoryLoop'
        $commands | Should -Contain 'Get-ScoutRawInventory'

        # And no KQL table name survives in any string literal the shim builds.
        $literals = @(
            $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
                ForEach-Object { $_.Value }
        ) -join "`n"
        foreach ($table in 'networkresources', 'recoveryservicesresources',
            'desktopvirtualizationresources', 'advisorresources', 'securityresources') {
            $literals | Should -Not -Match ([regex]::Escape($table))
        }
    }

    It 'the deleted legacy paging engine is really gone' {
        $root = Split-Path $PSScriptRoot -Parent
        Test-Path "$root/Modules/Private/Extraction/Invoke-AZTIInventoryLoop.ps1" | Should -BeFalse
    }

    It 'preserves the legacy per-table query set, filters and ordering through the shim' {
        Set-StrictMode -Version Latest
        Start-AZSCGraphExtraction -Subscriptions $script:subs -AzureEnvironment 'AzureCloud' `
            -SkipAdvisory ([switch]$false) -SecurityCenter ([switch]$true) -IncludeTags ([switch]$false) `
            3>$null 4>$null 6>$null | Out-Null

        $all = $script:capturedQueries -join "`n"
        foreach ($table in 'resources', 'networkresources', 'SupportResources',
            'recoveryservicesresources', 'desktopvirtualizationresources',
            'resourcecontainers', 'advisorresources', 'securityresources') {
            $all | Should -Match ('(?m)^' + [regex]::Escape($table) + '\b')
        }
        # The four UI/authoring artifact types stayed excluded, on the `resources` table only.
        $resourcesQuery = @($script:capturedQueries | Where-Object { $_ -match '^resources\b' }) -join "`n"
        $resourcesQuery | Should -Match 'microsoft\.portal/dashboards'
        # And the advisor/security filters are unchanged.
        $all | Should -Match "properties\.impact in~ \('Medium','High'\)"
        $all | Should -Match "type =~ 'microsoft\.security/assessments'"
    }

    It 'omits SupportResources on AzureUSGovernment, exactly as the legacy extractor did' {
        Set-StrictMode -Version Latest
        Start-AZSCGraphExtraction -Subscriptions $script:subs -AzureEnvironment 'AzureUSGovernment' `
            @script:switchArgs 3>$null 4>$null 6>$null | Out-Null
        ($script:capturedQueries -join "`n") | Should -Not -Match '(?m)^SupportResources\b'
    }

    It 'renders the resource-group filter clause and still requires a subscription id' {
        Set-StrictMode -Version Latest
        Start-AZSCGraphExtraction -Subscriptions $script:subs -AzureEnvironment 'AzureCloud' `
            -SubscriptionID 'sub1' -ResourceGroup 'rg-alpha' @script:switchArgs 3>$null 4>$null 6>$null | Out-Null
        ($script:capturedQueries -join "`n") | Should -Match "where resourceGroup in~ \('rg-alpha'\)"

        {
            Start-AZSCGraphExtraction -Subscriptions $script:subs -AzureEnvironment 'AzureCloud' `
                -ResourceGroup 'rg-alpha' @script:switchArgs 3>$null 4>$null 6>$null | Out-Null
        } | Should -Throw '*SubscriptionID must also be provided*'
    }

    It 'renders the tag filter clause when -TagKey/-TagValue are supplied' {
        Set-StrictMode -Version Latest
        Start-AZSCGraphExtraction -Subscriptions $script:subs -AzureEnvironment 'AzureCloud' `
            -TagKey 'Environment' -TagValue 'Production' @script:switchArgs 3>$null 4>$null 6>$null | Out-Null
        $all = $script:capturedQueries -join "`n"
        $all | Should -Match "where tagKey =~ 'Environment'"
        $all | Should -Match "tagValue =~ 'Production'"
    }

    It 'projects the tags column only when -IncludeTags is supplied' {
        Set-StrictMode -Version Latest
        Start-AZSCGraphExtraction -Subscriptions $script:subs -AzureEnvironment 'AzureCloud' `
            -IncludeTags ([switch]$false) -SkipAdvisory ([switch]$true) -SecurityCenter ([switch]$false) `
            3>$null 4>$null 6>$null | Out-Null
        ($script:capturedQueries -join "`n") | Should -Not -Match 'extendedLocation,tags'

        $script:capturedQueries = @()
        Start-AZSCGraphExtraction -Subscriptions $script:subs -AzureEnvironment 'AzureCloud' `
            -IncludeTags ([switch]$true) -SkipAdvisory ([switch]$true) -SecurityCenter ([switch]$false) `
            3>$null 4>$null 6>$null | Out-Null
        ($script:capturedQueries -join "`n") | Should -Match 'extendedLocation,tags'
    }
}

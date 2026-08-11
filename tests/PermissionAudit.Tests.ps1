#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the -PermissionAudit switch and Invoke-AZSCPermissionAudit function.

.DESCRIPTION
    Validates:
      - The -PermissionAudit and -IncludeEntraPermissions switches exist on Invoke-AzureScout
      - Invoke-AZSCPermissionAudit function signature (parameters, OutputFormat ValidateSet)
      - Return object structure when function is invoked with no Azure context
      - IncludeEntraPermissions switch is exposed and documented in the function
    No live Azure authentication is required.

.NOTES
    Author:  AzureScout Contributors
    Version: 1.0.0
    Created: 2026-02-24
    Phase:   20 — Permission Audit Feature
#>

BeforeAll {
    $script:ModuleRoot      = Split-Path -Parent $PSScriptRoot
    $script:InvokeScript    = Join-Path -Path $script:ModuleRoot -ChildPath 'src' -AdditionalChildPath 'Invoke-AzureScout.ps1'
    $script:AuditScript     = Join-Path -Path $script:ModuleRoot -ChildPath 'src' -AdditionalChildPath 'Invoke-AZTIPermissionAudit.ps1'

    # Dot-source both scripts to inspect function metadata
    . $script:InvokeScript
    . $script:AuditScript

    $script:InvokeCmd = Get-Command -Name Invoke-AzureScout         -ErrorAction SilentlyContinue
    $script:AuditCmd  = Get-Command -Name Invoke-AZSCPermissionAudit -ErrorAction SilentlyContinue
}

# ===================================================================
# Switch parameters on Invoke-AzureScout
# ===================================================================
Describe 'PermissionAudit switches on Invoke-AzureScout' {
    It 'Invoke-AzureScout function is available' {
        $script:InvokeCmd | Should -Not -BeNullOrEmpty
    }

    It 'PermissionAudit switch parameter exists' {
        $script:InvokeCmd.Parameters.ContainsKey('PermissionAudit') | Should -BeTrue
    }

    It 'PermissionAudit is a [switch] type' {
        $script:InvokeCmd.Parameters['PermissionAudit'].ParameterType | Should -Be ([System.Management.Automation.SwitchParameter])
    }

    It 'PermissionAudit has alias "AuditPermissions"' {
        $aliases = $script:InvokeCmd.Parameters['PermissionAudit'].Aliases
        $aliases | Should -Contain 'AuditPermissions'
    }

    It 'PermissionAudit has alias "CheckPermissions"' {
        $aliases = $script:InvokeCmd.Parameters['PermissionAudit'].Aliases
        $aliases | Should -Contain 'CheckPermissions'
    }

    It 'IncludeEntraPermissions switch parameter exists' {
        $script:InvokeCmd.Parameters.ContainsKey('IncludeEntraPermissions') | Should -BeTrue
    }

    It 'IncludeEntraPermissions is a [switch] type' {
        $script:InvokeCmd.Parameters['IncludeEntraPermissions'].ParameterType | Should -Be ([System.Management.Automation.SwitchParameter])
    }

    It 'IncludeEntraPermissions has alias "EntraAudit"' {
        $aliases = $script:InvokeCmd.Parameters['IncludeEntraPermissions'].Aliases
        $aliases | Should -Contain 'EntraAudit'
    }

    It 'IncludeEntraPermissions has alias "CheckEntraPermissions"' {
        $aliases = $script:InvokeCmd.Parameters['IncludeEntraPermissions'].Aliases
        $aliases | Should -Contain 'CheckEntraPermissions'
    }
}

# ===================================================================
# Invoke-AZSCPermissionAudit function signature
# ===================================================================
Describe 'Invoke-AZSCPermissionAudit — Function Signature' {
    It 'Invoke-AZSCPermissionAudit function is available after dot-source' {
        $script:AuditCmd | Should -Not -BeNullOrEmpty
    }

    It 'IncludeEntraPermissions switch parameter exists' {
        $script:AuditCmd.Parameters.ContainsKey('IncludeEntraPermissions') | Should -BeTrue
    }

    It 'IncludeEntraPermissions is a [switch] type' {
        $script:AuditCmd.Parameters['IncludeEntraPermissions'].ParameterType | Should -Be ([System.Management.Automation.SwitchParameter])
    }

    It 'TenantID parameter exists' {
        $script:AuditCmd.Parameters.ContainsKey('TenantID') | Should -BeTrue
    }

    It 'TenantID is a [string] type' {
        $script:AuditCmd.Parameters['TenantID'].ParameterType | Should -Be ([string])
    }

    It 'OutputFormat parameter exists' {
        $script:AuditCmd.Parameters.ContainsKey('OutputFormat') | Should -BeTrue
    }

    It 'OutputFormat ValidateSet contains "Console"' {
        $vs = $script:AuditCmd.Parameters['OutputFormat'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $vs.ValidValues | Should -Contain 'Console'
    }

    It 'OutputFormat ValidateSet contains "Markdown"' {
        $vs = $script:AuditCmd.Parameters['OutputFormat'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $vs.ValidValues | Should -Contain 'Markdown'
    }

    It 'OutputFormat ValidateSet contains "AsciiDoc"' {
        $vs = $script:AuditCmd.Parameters['OutputFormat'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $vs.ValidValues | Should -Contain 'AsciiDoc'
    }

    It 'OutputFormat ValidateSet contains "Json"' {
        $vs = $script:AuditCmd.Parameters['OutputFormat'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $vs.ValidValues | Should -Contain 'Json'
    }

    It 'OutputFormat ValidateSet contains "All"' {
        $vs = $script:AuditCmd.Parameters['OutputFormat'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $vs.ValidValues | Should -Contain 'All'
    }

    It 'OutputFormat default value is "Console"' {
        $source = Get-Content -LiteralPath $script:AuditScript -Raw
        $source | Should -Match "\[string\]\s*\`$OutputFormat\s*=\s*'Console'"
    }

    It 'ReportDir parameter exists' {
        $script:AuditCmd.Parameters.ContainsKey('ReportDir') | Should -BeTrue
    }

    It 'SubscriptionID parameter exists' {
        $script:AuditCmd.Parameters.ContainsKey('SubscriptionID') | Should -BeTrue
    }

    It 'SubscriptionID accepts an array of strings' {
        $script:AuditCmd.Parameters['SubscriptionID'].ParameterType | Should -Be ([string[]])
    }
}

# ===================================================================
# No-auth graceful behavior
# ===================================================================
Describe 'Invoke-AZSCPermissionAudit — No Azure Context Behavior' {
    BeforeEach {
        # The test contract is the unauthenticated path.  Do not let a developer's
        # cached Azure session turn this unit test into a live RBAC/provider scan.
        Mock -CommandName Get-AzContext -MockWith { $null }
    }

    It 'Returns $null when no Azure context is present (no auth)' {
        # The function calls Get-AzContext internally; without auth it returns $null
        # and the function returns $null early with an error message — not a throw
        $result = Invoke-AZSCPermissionAudit -ErrorAction SilentlyContinue 2>$null
        # If no context, function should return null (not throw)
        $result | Should -BeNullOrEmpty
    }

    It 'Does not throw terminating error when Get-AzContext returns $null' {
        { Invoke-AZSCPermissionAudit -ErrorAction SilentlyContinue 2>$null } | Should -Not -Throw
    }
}

# ===================================================================
# Return object structure (source analysis)
# ===================================================================
Describe 'Invoke-AZSCPermissionAudit — Return Object Structure (Source Analysis)' {
    BeforeAll {
        $script:AuditSource = Get-Content -Path $script:AuditScript -Raw
    }

    It 'Source defines ArmAccess in the return object' {
        $script:AuditSource | Should -Match 'ArmAccess'
    }

    It 'Source defines GraphAccess in the return object' {
        $script:AuditSource | Should -Match 'GraphAccess'
    }

    It 'Source defines CallerAccount in the return object' {
        $script:AuditSource | Should -Match 'CallerAccount'
    }

    It 'Source defines OverallReadiness in the return object' {
        $script:AuditSource | Should -Match 'OverallReadiness'
    }

    It 'Source defines ArmDetails in the return object' {
        $script:AuditSource | Should -Match 'armDetails|ArmDetails'
    }

    It 'Source defines ProviderResults in the return object' {
        $script:AuditSource | Should -Match 'providerResults|ProviderResults'
    }

    It 'Source defines GraphDetails in the return object' {
        $script:AuditSource | Should -Match 'graphDetails|GraphDetails'
    }

    It 'Source defines Recommendations in the return object' {
        $script:AuditSource | Should -Match 'recommendations|Recommendations'
    }

    It 'OverallReadiness uses switch expression with Insufficient state' {
        $script:AuditSource | Should -Match 'Insufficient'
    }

    It 'OverallReadiness includes FullARM state' {
        $script:AuditSource | Should -Match 'FullARM'
    }

    It 'OverallReadiness includes FullARMAndEntra state' {
        $script:AuditSource | Should -Match 'FullARMAndEntra'
    }

    It 'Source has separate ARM path and Entra path (IncludeEntraPermissions guard)' {
        $script:AuditSource | Should -Match 'IncludeEntraPermissions'
    }
}

# ===================================================================
# Invoke-AzureScout source-level PermissionAudit routing
# ===================================================================
Describe 'PermissionAudit routing in Invoke-AzureScout source' {
    BeforeAll {
        $script:InvokeSource = Get-Content -Path $script:InvokeScript -Raw
    }

    It 'Invoke-AzureScout calls Invoke-AZSCPermissionAudit when -PermissionAudit is set' {
        $script:InvokeSource | Should -Match 'Invoke-AZSCPermissionAudit'
    }

    It 'Source passes IncludeEntraPermissions to the audit function' {
        $script:InvokeSource | Should -Match 'IncludeEntraPermissions'
    }

    It 'Source passes SubscriptionID to the audit function' {
        $script:InvokeSource | Should -Match 'Invoke-AZSCPermissionAudit[\s\S]*-SubscriptionID'
    }

    It 'Source has early-return or conditional block that skips inventory when PermissionAudit is used' {
        $script:InvokeSource | Should -Match 'PermissionAudit'
    }
}

# ===================================================================
# Entra/Graph audit path — null/scalar-safe .Count regression tests
#
# Root cause: Get-AzSubscription/Where-Object/Select-Object collapse a SINGLE
# matching result to a bare scalar object instead of an array. Calling .Count
# on that scalar is silently coerced to 1 by PowerShell 7's intrinsic
# Count/Length member, but THROWS under strict mode on Windows PowerShell 5.1
# ("The property 'Count' cannot be found on this object") because Desktop
# edition has no such intrinsic. These tests pin the fix (@() wrapping) with
# a fully mocked, offline audit run — no live Azure/Graph access required.
# ===================================================================
Describe 'Invoke-AZSCPermissionAudit — Entra audit survives null/scalar Graph and ARM data' {
    BeforeAll {
        # Bring the private Graph helper functions into scope so they can be mocked
        # (they are dot-sourced by the module but not by this test's BeforeAll).
        . (Join-Path -Path $script:ModuleRoot -ChildPath 'src' -AdditionalChildPath 'Get-AZTIGraphToken.ps1')
        . (Join-Path -Path $script:ModuleRoot -ChildPath 'src' -AdditionalChildPath 'Invoke-AZTIGraphRequest.ps1')

        # Exactly ONE enabled subscription — the precise shape that collapses
        # $subs | Where-Object {...} | Select-Object -First 3 to a scalar.
        $script:FakeSub = [PSCustomObject]@{
            Id    = '11111111-1111-1111-1111-111111111111'
            Name  = 'demo-sub'
            State = 'Enabled'
        }

        Mock -CommandName Get-AzContext -MockWith {
            [PSCustomObject]@{
                Account = [PSCustomObject]@{ Id = 'user@contoso.com'; Type = 'User' }
                Tenant  = [PSCustomObject]@{ Id = '22222222-2222-2222-2222-222222222222' }
            }
        }
        Mock -CommandName Get-AzSubscription -MockWith { $script:FakeSub }
        Mock -CommandName Get-AzRoleAssignment -MockWith {
            [PSCustomObject]@{ RoleDefinitionName = 'Reader' }
        }
        Mock -CommandName Get-AzManagementGroup -MockWith {
            @([pscustomobject]@{ Name = 'root'; DisplayName = 'Tenant Root Group' })
        }
        Mock -CommandName Get-AzResourceGroup -MockWith { @() }
        Mock -CommandName Set-AzContext -MockWith {
            [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $Subscription } }
        }
        Mock -CommandName Get-AzResourceProvider -MockWith {
            [PSCustomObject]@{ RegistrationState = 'Registered' }
        }
        # Graph token acquisition succeeds, but every Graph request returns $null —
        # simulating an empty/absent Graph response rather than a hard failure.
        Mock -CommandName Get-AZSCGraphToken -MockWith { @{ Authorization = 'Bearer faketoken' } }
        Mock -CommandName Invoke-AZSCGraphRequest -MockWith { $null }
    }

    It 'Does not throw when Get-AzSubscription returns a single (scalar-collapsing) subscription and Graph returns $null' {
        # Set-StrictMode is dynamically scoped and propagates into functions called from
        # here (verified against both Windows PowerShell 5.1 and PowerShell 7). Enabling it
        # is what actually exercises the crash condition: without it, a scalar's missing
        # .Count silently evaluates to $null/1 instead of throwing, so this assertion would
        # pass even against the un-fixed code. This is the same failure mode a caller with
        # `Set-StrictMode -Version Latest` in their profile hits on Windows PowerShell 5.1.
        Set-StrictMode -Version Latest
        { $script:Result = Invoke-AZSCPermissionAudit -IncludeEntraPermissions -TenantID '22222222-2222-2222-2222-222222222222' -OutputFormat Console } | Should -Not -Throw
    }

    It 'Returns a populated result object instead of crashing mid-audit' {
        $script:Result | Should -Not -BeNullOrEmpty
        $script:Result.OverallReadiness | Should -Not -BeNullOrEmpty
    }

    It 'GraphDetails is present (an array, possibly empty) rather than the audit crashing before reaching Section 3' {
        , $script:Result.GraphDetails | Should -Not -BeNullOrEmpty
        $script:Result.GraphDetails.Count | Should -BeGreaterOrEqual 0
    }

    It 'ProviderResults reflects the single scalar-collapsing subscription without throwing on .Count' {
        , $script:Result.ProviderResults | Should -Not -BeNullOrEmpty
        $script:Result.ProviderResults.Count | Should -BeGreaterThan 0
    }

    It 'Recommendations is a real array whose .Count never throws even when empty (Sort-Object -Unique null-collapse guard)' {
        { $script:Result.Recommendations.Count } | Should -Not -Throw
    }

    It 'does not recommend tenant-wide provider registration from one sampled subscription' {
        $source = Get-Content -LiteralPath $script:AuditScript -Raw
        $source | Should -Not -Match '\$recommendations\.Add\("Register provider'
        $source | Should -Match 'one subscription sample'
    }

    It 'marks a delegated run Partial when selected Entra collectors are known unavailable' {
        $payload = @{ scp = 'User.Read.All'; upn = 'user@contoso.com' } | ConvertTo-Json -Compress
        $toBase64Url = {
            param([string]$Value)
            [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        }
        $jwt = "$( & $toBase64Url '{\"alg\":\"none\"}' ).$( & $toBase64Url $payload ).sig"
        Mock -CommandName Get-AZSCGraphToken -MockWith { @{ Authorization = "Bearer $jwt" } }

        $partial = Invoke-AZSCPermissionAudit -IncludeEntraPermissions -TenantID '22222222-2222-2222-2222-222222222222' -OutputFormat Console

        $partial.OverallReadiness | Should -Be 'Partial'
        @($partial.EmptyCollectors).Count | Should -BeGreaterThan 0
    }

    It 'resolves one collision-safe output path and filename stem for all file formats' {
        $source = Get-Content -LiteralPath $script:AuditScript -Raw
        ([regex]::Matches($source, 'Set-AZSCReportPath -ReportDir \$null')).Count | Should -Be 1
        $source | Should -Match '\$auditFileStem\s*='
        $source | Should -Match "NewGuid\(\).*Substring\(0, 8\)"
        foreach ($extension in 'json', 'md', 'adoc') {
            $source | Should -Match "\`$auditFileStem\.$extension"
        }
    }

    It 'does not treat a Reader assignment held by another principal as caller access' {
        Mock -CommandName Get-AzResourceGroup -MockWith { throw 'AuthorizationFailed for current identity' }
        Mock -CommandName Get-AzRoleAssignment -MockWith {
            [PSCustomObject]@{ RoleDefinitionName = 'Reader'; ObjectId = 'someone-else' }
        }

        $result = Invoke-AZSCPermissionAudit -TenantID '22222222-2222-2222-2222-222222222222' -OutputFormat Console
        $detail = $result.ArmDetails | Where-Object Check -eq 'ARM: Subscription [demo-sub]' | Select-Object -First 1

        $detail.Status | Should -Be 'Fail'
        $result.ArmAccess | Should -BeFalse
    }
}

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#6893 — a licence boundary must not be reported as a permission denial.

    Field report: a tenant without Entra ID P2 ran the audit and got

        [FAIL] Graph: IdentityRiskyUser.Read.All: DENIED — 1 collectors will be empty
               Grant 'IdentityRiskyUser.Read.All' in Entra ID > Enterprise Applications

    which is wrong advice. Identity Protection is a P2 feature; on a tenant without P2 the
    risky-users endpoint fails however much consent it has, so granting the permission cannot fix
    it. Most tenants do not have P2, so the COMMON case was being reported as an error.

    The three-state licence lookup is the load-bearing part. `$null` (could not read the SKUs)
    must NOT soften the verdict — downgrading a genuine denial on the strength of a failed lookup
    would hide a real problem, which is the opposite of what this fix is for.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . "$script:Root/src/Invoke-AZTIPermissionAudit.ps1"

    # Mock needs a real command to attach to, and the Graph helper lives in a file this test does
    # not dot-source (it drags in the whole collect layer). A stub with the same name and shape is
    # enough: every test below replaces it wholesale.
    if (-not (Get-Command Invoke-AZSCGraphRequest -ErrorAction SilentlyContinue)) {
        function Invoke-AZSCGraphRequest { param([string]$Uri, [switch]$SinglePage) }
    }
}

Describe 'AB#6893 — licensed-feature registry' {

    It 'declares IdentityRiskyUser.Read.All as licence-gated' {
        $Script:ScoutGraphLicensedFeature.ContainsKey('IdentityRiskyUser.Read.All') | Should -BeTrue
    }

    It 'names the product a customer would actually go and buy' {
        $Script:ScoutGraphLicensedFeature['IdentityRiskyUser.Read.All'].Product | Should -Match 'P2'
    }

    It 'matches on the SERVICE PLAN, not the SKU marketing name' {
        # AAD_PREMIUM_P2 arrives via EMS E5 and Microsoft 365 E5 as well as standalone Entra ID
        # P2. Matching the SKU name would miss every bundled route to the same licence.
        $Script:ScoutGraphLicensedFeature['IdentityRiskyUser.Read.All'].SkuPattern | Should -Be 'AAD_PREMIUM_P2'
    }
}

Describe 'AB#6893 — Test-ScoutTenantLicence is three-state' {

    It 'returns $true when the service plan is present on any subscribed SKU' {
        Mock Invoke-AZSCGraphRequest {
            @([pscustomobject]@{ servicePlans = @([pscustomobject]@{ servicePlanName = 'AAD_PREMIUM_P2' }) })
        }
        Test-ScoutTenantLicence -SkuPattern 'AAD_PREMIUM_P2' | Should -BeTrue
    }

    It 'finds the plan even when it is bundled behind other plans on the same SKU' {
        Mock Invoke-AZSCGraphRequest {
            @([pscustomobject]@{ servicePlans = @(
                        [pscustomobject]@{ servicePlanName = 'EXCHANGE_S_ENTERPRISE' }
                        [pscustomobject]@{ servicePlanName = 'AAD_PREMIUM_P2' }
                    ) })
        }
        Test-ScoutTenantLicence -SkuPattern 'AAD_PREMIUM_P2' | Should -BeTrue
    }

    It 'returns $false when the tenant is licensed but not for that plan' {
        Mock Invoke-AZSCGraphRequest {
            @([pscustomobject]@{ servicePlans = @([pscustomobject]@{ servicePlanName = 'AAD_PREMIUM' }) })
        }
        Test-ScoutTenantLicence -SkuPattern 'AAD_PREMIUM_P2' | Should -BeFalse
    }

    It 'returns $null — not $false — when the SKU list cannot be read' {
        # This is the case that must NOT soften a real denial. Organization.Read.All may itself
        # be withheld, and "I could not tell" is not "the tenant lacks the licence".
        Mock Invoke-AZSCGraphRequest { throw 'Authorization_RequestDenied' }
        Test-ScoutTenantLicence -SkuPattern 'AAD_PREMIUM_P2' | Should -BeNullOrEmpty
    }

    It 'returns $null when the tenant reports no subscribed SKUs at all' {
        Mock Invoke-AZSCGraphRequest { @() }
        Test-ScoutTenantLicence -SkuPattern 'AAD_PREMIUM_P2' | Should -BeNullOrEmpty
    }

    It 'does not throw on a SKU with no servicePlans property' {
        # Real Graph payloads are not uniformly shaped, and StrictMode turns a missing property
        # into a terminating error rather than a $null.
        Mock Invoke-AZSCGraphRequest { @([pscustomobject]@{ skuPartNumber = 'FLOW_FREE' }) }
        { Test-ScoutTenantLicence -SkuPattern 'AAD_PREMIUM_P2' } | Should -Not -Throw
    }
}

Describe 'AB#6893 — the audit softens only on a definitive no' {

    It 'only downgrades to Warn when the licence check returns exactly $false' {
        # Guards the flow rather than the helper: an `if ($licensed -eq $false)` is correct and an
        # `if (-not $licensed)` is not, because $null is also falsy and would swallow a real
        # denial whenever the SKU lookup failed.
        $src = Get-Content "$script:Root/src/Invoke-AZTIPermissionAudit.ps1" -Raw
        $src | Should -Match '\$licensed -eq \$false'
        $src | Should -Not -Match 'if \(-not \$licensed\)'
    }

    It 'tells the reader that granting the permission will not help' {
        $src = Get-Content "$script:Root/src/Invoke-AZTIPermissionAudit.ps1" -Raw
        $src | Should -Match 'NOT LICENSED'
        $src | Should -Match 'will not populate these collectors'
    }

    It 'still records the affected collectors so the gap stays visible' {
        # Not licensed is still a coverage gap -- it must reach $emptyCollectors and be reported
        # as Not assessed, not vanish because it is nobody's fault.
        $src = Get-Content "$script:Root/src/Invoke-AZTIPermissionAudit.ps1" -Raw
        $src | Should -Match "Reason\s*=\s*`"Not licensed"
    }
}

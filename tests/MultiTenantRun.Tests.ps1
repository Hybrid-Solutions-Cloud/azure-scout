#Requires -Version 7.0
#Requires -Modules Pester
Set-StrictMode -Version Latest

$moduleRoot = Split-Path $PSScriptRoot -Parent
$originalCi = [Environment]::GetEnvironmentVariable('CI', 'Process')
try {
    $env:CI = 'true'
    Import-Module (Join-Path $moduleRoot 'AzureScout.psd1') -Force -ErrorAction Stop
}
finally {
    [Environment]::SetEnvironmentVariable('CI', $originalCi, 'Process')
}

InModuleScope AzureScout {

Describe 'AB#7105 enterprise tenant target resolution' {
    It 'enumerates every directly accessible tenant and removes duplicates' {
        Mock Get-AZSCAccessibleTenant {
            @(
                [pscustomobject]@{ Id = 'aaaaaaaa-1111'; Name = 'Contoso' }
                [pscustomobject]@{ Id = 'bbbbbbbb-2222'; Name = 'Fabrikam' }
                [pscustomobject]@{ Id = 'AAAAAAAA-1111'; Name = 'Contoso duplicate' }
            )
        }
        $result = Resolve-AZSCMultiTenantTarget -AllAccessibleTenants

        @($result).Count | Should -Be 2
        $result[0].Name | Should -Be 'Contoso'
        $result[0].FolderName | Should -Be 'Contoso_aaaaaaaa'
        $result[1].Name | Should -Be 'Fabrikam'
    }

    It 'scans only explicitly selected tenant IDs and retains unknown targets for clear failure reporting' {
        Mock Get-AZSCAccessibleTenant {
            @(
                [pscustomobject]@{ Id = 'tenant-one'; Name = 'Tenant One' }
                [pscustomobject]@{ Id = 'tenant-two'; Name = 'Tenant Two' }
            )
        }
        $result = Resolve-AZSCMultiTenantTarget -RequestedTenantId @('tenant-two', 'tenant-missing')

        @($result).Count | Should -Be 2
        $result[0].Id | Should -Be 'tenant-two'
        $result[0].Name | Should -Be 'Tenant Two'
        $result[1].Id | Should -Be 'tenant-missing'
        $result[1].Discovered | Should -BeFalse
    }

    It 'throws when all-accessible discovery returns no tenants' {
        Mock Get-AZSCAccessibleTenant { @() }
        {
            Resolve-AZSCMultiTenantTarget -AllAccessibleTenants
        } | Should -Throw '*No accessible tenants*'
    }
}

Describe 'AB#7105 multi-tenant overview rendering' {
    It 'writes a self-contained root overview and machine-readable summary with tenant links' {
        $out = Join-Path $TestDrive 'overview'
        $summary = [pscustomobject]@{
            Schema      = 'azure-scout/multi-tenant-run/v1'
            RunId       = 'enterprise-run'
            RootPath    = $out
            Account     = 'operator@example.test'
            StartedAt   = '2026-08-17T00:00:00Z'
            CompletedAt = '2026-08-17T00:10:00Z'
            Status      = 'Completed'
            Selection   = [ordered]@{
                TenantSelection = 'Selected tenant IDs'
                RunType = 'Inventory and assessment'
                Scope = 'All'
                Categories = @('All')
                Assessments = @('CAF: Azure Landing Zone')
                OutputFormats = @('React', 'JsonEvidence')
                SubscriptionIds = @()
                ManagementGroups = @()
                EnabledOptions = @('IncludeCosts')
                SkippedOptions = @('SkipDiagram')
            }
            Counts = [ordered]@{ Total = 1; Pending = 0; Running = 0; Completed = 1; Failed = 0 }
            Tenants = @([pscustomobject]@{
                TenantId = 'tenant-one'; TenantName = 'Tenant One'; Folder = 'Tenant One_tenant-o'
                Status = 'Completed'; StartedAt = 'start'; CompletedAt = 'end'; Duration = '00:00:10:00.000'
                SubscriptionCount = 3; ResourceCount = 42
                ReactReport = 'Tenant One_tenant-o/assessment-report/report-react.html'; Error = $null
            })
        }

        $report = Export-AZSCMultiTenantOverview -Summary $summary -OutputPath $out

        $report | Should -Be (Join-Path $out 'report-react.html')
        Test-Path (Join-Path $out 'index.html') | Should -BeTrue
        Test-Path (Join-Path $out 'run-summary.json') | Should -BeTrue
        $html = Get-Content -LiteralPath $report -Raw
        $html | Should -Match 'Tenant One_tenant-o/assessment-report/report-react.html'
        $html | Should -Match 'Inventory and assessment'
        (Get-Content (Join-Path $out 'run-summary.json') -Raw | ConvertFrom-Json).Counts.Completed | Should -Be 1
    }
}

Describe 'AB#7105 multi-tenant orchestration' {
    It 'routes multiple TenantID values through the outer orchestrator before single-tenant work' {
        Mock Test-AZSCPS { 'Windows' }
        Mock Invoke-AZSCMultiTenantRun {
            [pscustomobject]@{
                PSTypeName = 'AzureScout.MultiTenantRunResult'
                Requested = @($RequestedTenantId)
                ScanAll = [bool]$AllAccessibleTenants
            }
        }
        $result = Invoke-AzureScout -NoWizard -TenantID @('tenant-one', 'tenant-two')

        $result.Requested | Should -Be @('tenant-one', 'tenant-two')
        $result.ScanAll | Should -BeFalse
    }

    It 'routes -AllAccessibleTenants without changing a bare invocation into a fleet scan' {
        Mock Test-AZSCPS { 'Windows' }
        Mock Invoke-AZSCMultiTenantRun {
            [pscustomobject]@{
                PSTypeName = 'AzureScout.MultiTenantRunResult'
                Requested = @($RequestedTenantId)
                ScanAll = [bool]$AllAccessibleTenants
            }
        }
        $result = Invoke-AzureScout -NoWizard -AllAccessibleTenants

        @($result.Requested).Count | Should -Be 0
        $result.ScanAll | Should -BeTrue
    }

    It 'creates one umbrella folder, contains a failed tenant, and links the successful report' {
        $out = Join-Path $TestDrive 'runs'
        $runner = {
            param($arguments)
            $tenantId = [string]@($arguments.TenantID)[0]
            if ($tenantId -eq 'tenant-fail') { throw 'synthetic tenant failure' }
            $reportFolder = Join-Path $arguments.ReportDir 'assessment-report'
            $null = New-Item -ItemType Directory -Path $reportFolder -Force
            $react = Join-Path $reportFolder 'report-react.html'
            '<html>tenant report</html>' | Set-Content -LiteralPath $react
            [pscustomobject]@{
                PSTypeName = 'AzureScout.RunResult'; Status = 'Completed'; TenantId = $tenantId
                OutputPath = $arguments.ReportDir; ReactFile = $react; EvidenceFile = $null; JsonFile = $null
                SubscriptionCount = 2; ResourceCount = 10; Duration = '00:00:00:01.000'
            }
        }

        Mock Get-AzContext {
            [pscustomobject]@{
                Account = [pscustomobject]@{ Id = 'operator@example.test' }
                Tenant = [pscustomobject]@{ Id = 'tenant-ok' }
            }
        }
        Mock Set-AzContext { }
        Mock Connect-AZSCLoginSession { 'tenant-ok' }
        Mock Get-AZSCAccessibleTenant {
            @(
                [pscustomobject]@{ Id = 'tenant-ok'; Name = 'Tenant OK' }
                [pscustomobject]@{ Id = 'tenant-fail'; Name = 'Tenant Fail' }
            )
        }
        $parameters = @{
            ReportDir = $out
            RunName = 'enterprise-run'
            Scope = 'All'
            OutputFormat = @('React')
            InventoryAndAssessment = $true
            NoWizard = $true
        }
        $result = Invoke-AZSCMultiTenantRun -InvocationParameters $parameters `
            -RequestedTenantId @('tenant-ok', 'tenant-fail') -TenantRunner $runner -WarningAction SilentlyContinue

        $result.Status | Should -Be 'CompletedWithErrors'
        $result.Tenants.Count | Should -Be 2
        $result.Tenants[0].Status | Should -Be 'Completed'
        $result.Tenants[0].ReactReport | Should -Match 'assessment-report/report-react.html$'
        $result.Tenants[1].Status | Should -Be 'Failed'
        $result.Tenants[1].Error | Should -Match 'synthetic tenant failure'
        Test-Path $result.Overview | Should -BeTrue
        Test-Path $result.Summary | Should -BeTrue
    }

    It 'requires explicit opt-in for automatic tenant enumeration' {
        $source = Get-Content (Join-Path (Get-Module AzureScout).ModuleBase 'src/Invoke-AzureScout.ps1') -Raw
        $source | Should -Match '\$AllAccessibleTenants\.IsPresent\s+-or\s+\$requestedTenantIds\.Count\s+-gt\s+1'
        $source | Should -Match '\$requestedTenantIds\.Count\s+-eq\s+1'
    }

    It 'accepts the real $PSBoundParameters type as -InvocationParameters, not just a plain hashtable' {
        # AB#7105 hotfix -- a live enterprise run crashed immediately with "Cannot find an
        # overload for 'Contains' and the argument count: '1'." because every existing test
        # here (and the caller in Invoke-AzureScout.ps1) worked with either a real
        # PSBoundParametersDictionary or a hand-built [hashtable]; but the function body called
        # $InvocationParameters.Contains(...) -- a Hashtable method that PSBoundParametersDictionary
        # (backed by Dictionary[string,object]) does not expose the same way, since its own
        # .Contains(...) only matches KeyValuePair, not a bare key. Every prior test constructed
        # -InvocationParameters from a hashtable literal (which has a working .Contains(key)), so
        # none of them caught it. This test builds a genuine PSBoundParametersDictionary the same
        # way Invoke-AzureScout does -- via $PSBoundParameters inside a real function call -- so a
        # regression to .Contains(...) here fails loudly again.
        function Get-AZSCTestBoundParameters {
            param($TenantID, $Category, [switch]$IncludeCosts, [switch]$IncludeTags, $OutputFormat, $ReportDir, [switch]$SecurityCenter)
            return $PSBoundParameters
        }
        $realBoundParameters = Get-AZSCTestBoundParameters -TenantID @('tenant-one', 'tenant-two') -Category 'All' `
            -IncludeCosts -IncludeTags -OutputFormat @('React') -ReportDir (Join-Path $TestDrive 'real-params-run') -SecurityCenter
        # Should -BeOfType with the internal type's full name string fails to resolve on some
        # platforms/PS builds (confirmed failing on Linux CI while passing on Windows) --
        # comparing the already-instantiated object's runtime type name needs no string-to-type
        # lookup and is portable everywhere.
        $realBoundParameters.GetType().Name | Should -Be 'PSBoundParametersDictionary'

        Mock Get-AzContext {
            [pscustomobject]@{
                Account = [pscustomobject]@{ Id = 'operator@example.test' }
                Tenant  = [pscustomobject]@{ Id = 'tenant-one' }
            }
        }
        Mock Set-AzContext { }
        Mock Connect-AZSCLoginSession { 'tenant-one' }
        Mock Get-AZSCAccessibleTenant {
            @(
                [pscustomobject]@{ Id = 'tenant-one'; Name = 'Tenant One' }
                [pscustomobject]@{ Id = 'tenant-two'; Name = 'Tenant Two' }
            )
        }
        $runner = {
            param($arguments)
            $tenantId = [string]@($arguments.TenantID)[0]
            $reportFolder = Join-Path $arguments.ReportDir 'assessment-report'
            $null = New-Item -ItemType Directory -Path $reportFolder -Force
            $react = Join-Path $reportFolder 'report-react.html'
            '<html>tenant report</html>' | Set-Content -LiteralPath $react
            [pscustomobject]@{
                PSTypeName = 'AzureScout.RunResult'; Status = 'Completed'; TenantId = $tenantId
                OutputPath = $arguments.ReportDir; ReactFile = $react; EvidenceFile = $null; JsonFile = $null
                SubscriptionCount = 1; ResourceCount = 1; Duration = '00:00:00:01.000'
            }
        }

        { Invoke-AZSCMultiTenantRun -InvocationParameters $realBoundParameters `
            -RequestedTenantId @('tenant-one', 'tenant-two') -TenantRunner $runner -WarningAction SilentlyContinue
        } | Should -Not -Throw
    }
}

} # end InModuleScope

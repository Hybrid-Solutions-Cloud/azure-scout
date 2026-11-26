#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300 phase 4, batch 2: the landing-zone and pillar rules that were manual only because the
    per-resource ARM reads did not exist yet, and are automated now that collect.json carries them:

      CAF-STO-04   caf.storage     blob soft delete or versioning        (blobServiceProperties)
      WAF-RE-13    waf.reliability blob soft-delete retention >= 7 days  (blobServiceProperties)
      CAF-DB-07    caf.databases   SQL server auditing enabled           (sqlServerAuditing)
      CAF-WEB-06   caf.web         Always On and a health check path     (webAppConfig joined to webApps)

    Every one is gated on its dataset's sibling <name>Measured flag, so a run that never read the
    setting reports Not assessed instead of a pass. Each rule is proven failing, passing, and
    Not assessed with the flag false, against small collect objects built here with no Azure
    connection. The other rules converted by the same reads are pinned in
    Assessment.TechnologyReviews, Assessment.ServiceGuides, Assessment.WaraAdvisor and
    Assessment.WorkloadReviews.
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

    $script:Sub = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers'

    function New-BlobRow {
        param([hashtable] $Over = @{})
        $r = [ordered]@{
            storageAccountId = "$script:Sub/Microsoft.Storage/storageAccounts/st1".ToLowerInvariant(); name = 'st1'
            deleteRetentionEnabled = $true; deleteRetentionDays = 14; containerDeleteRetentionEnabled = $true; containerDeleteRetentionDays = 14
            versioningEnabled = $true; changeFeedEnabled = $true; pointInTimeRestoreEnabled = $true
        }
        foreach ($k in $Over.Keys) { $r[$k] = $Over[$k] }
        $r
    }
    function New-StorageCollect { param($Rows, [bool] $Measured = $true) [ordered]@{ domains = [ordered]@{ storage = [ordered]@{ blobServiceProperties = @($Rows); blobServicePropertiesMeasured = $Measured } } } }
    function New-AuditCollect {
        param($State, [bool] $Measured = $true)
        [ordered]@{ domains = [ordered]@{ databases = [ordered]@{
                    sqlServerAuditing = @([ordered]@{ sqlServerId = "$script:Sub/Microsoft.Sql/servers/sql1".ToLowerInvariant(); name = 'sql1'; auditingState = $State; azureMonitorTargetEnabled = ($State -eq 'Enabled') })
                    sqlServerAuditingMeasured = $Measured } } }
    }
    function New-WebCollect {
        param([hashtable] $Config = @{}, [string] $Kind = 'app,linux', [bool] $Measured = $true)
        $site = "$script:Sub/Microsoft.Web/sites/app1"
        $row = [ordered]@{ webAppId = $site.ToLowerInvariant(); name = 'app1'; ftpsState = 'FtpsOnly'; alwaysOn = $true; healthCheckPathSet = $true; remoteDebuggingEnabled = $false }
        foreach ($k in $Config.Keys) { $row[$k] = $Config[$k] }
        [ordered]@{ domains = [ordered]@{ web = [ordered]@{
                    webApps = @([ordered]@{ id = $site; name = 'app1'; kind = $Kind })
                    webAppConfig = @($row); webAppConfigMeasured = $Measured } } }
    }
}

Describe 'Rule files the phase 4 batch 2 reads converted' {
    It '<File> keeps <Rules> rules with <Auto> automated, each id unique' -ForEach @(
        @{ File = 'caf.storage'; Rules = 6; Auto = 5 }
        @{ File = 'caf.databases'; Rules = 7; Auto = 7 }
        @{ File = 'caf.web'; Rules = 6; Auto = 5 }
        @{ File = 'waf.reliability'; Rules = 7; Auto = 4 }
    ) {
        $set = & $script:Module { param($f) Get-RuleSet -Patterns $f } $File
        @($set.Rules).Count | Should -Be $Rules
        @($set.Rules.id | Select-Object -Unique).Count | Should -Be $Rules
        @($set.Rules | Where-Object { -not $_.manual }).Count | Should -Be $Auto
    }

    It '<Id> in <File> is automated, gated on a Measured flag, and says what fails' -ForEach @(
        @{ File = 'caf.storage'; Id = 'CAF-STO-04'; Flag = 'blobServicePropertiesMeasured' }
        @{ File = 'waf.reliability'; Id = 'WAF-RE-13'; Flag = 'blobServicePropertiesMeasured' }
        @{ File = 'caf.databases'; Id = 'CAF-DB-07'; Flag = 'sqlServerAuditingMeasured' }
        @{ File = 'caf.web'; Id = 'CAF-WEB-06'; Flag = 'webAppConfigMeasured' }
    ) {
        $rule = @((& $script:Module { param($f) Get-RuleSet -Patterns $f } $File).Rules | Where-Object { $_.id -eq $Id })[0]
        $rule.manual | Should -BeFalse
        $rule.assert.type | Should -Not -Be 'manual'
        $rule.assert.gate | Should -Match $Flag
        $rule.remediation | Should -Not -Match 'does not yet capture'
    }
}

Describe 'CAF-STO-04: storage accounts enable blob soft delete or versioning' {
    It '<Case>' -ForEach @(
        @{ Case = 'passes soft delete with versioning off'; Over = @{ versioningEnabled = $false }; Status = 'Pass'; Count = 0 }
        @{ Case = 'passes versioning with soft delete off'; Over = @{ deleteRetentionEnabled = $false; deleteRetentionDays = $null }; Status = 'Pass'; Count = 0 }
        @{ Case = 'fails an account with both off'; Over = @{ deleteRetentionEnabled = $false; deleteRetentionDays = $null; versioningEnabled = $false }; Status = 'Fail'; Count = 1 }
    ) {
        $f = (Invoke-ScoutTestRuleSet -Pattern 'caf.storage' -Collect (New-StorageCollect (New-BlobRow $Over)) -Assessment 'x') | Where-Object Id -eq 'CAF-STO-04'
        $f.Status | Should -Be $Status
        $f.EvidenceCount | Should -Be $Count
    }

    It 'is NotAssessed when the blob service was never read, even with rows present' {
        $c = New-StorageCollect (New-BlobRow @{ versioningEnabled = $false; deleteRetentionEnabled = $false }) -Measured $false
        ((Invoke-ScoutTestRuleSet -Pattern 'caf.storage' -Collect $c -Assessment 'x') | Where-Object Id -eq 'CAF-STO-04').Status | Should -Be 'NotAssessed'
    }

    It 'leaves the other storage rules unaffected by the missing blob service data' {
        $c = New-StorageCollect @() -Measured $false
        $findings = Invoke-ScoutTestRuleSet -Pattern 'caf.storage' -Collect $c -Assessment 'x'
        @($findings | Where-Object Status -eq 'Error').Count | Should -Be 0
        ($findings | Where-Object Id -eq 'CAF-STO-06').Status | Should -Be 'Manual'
    }
}

Describe 'WAF-RE-13: blob soft-delete retention meets the minimum recovery window' {
    It '<Case>' -ForEach @(
        @{ Case = 'passes 7 days'; Over = @{ deleteRetentionDays = 7 }; Status = 'Pass'; Count = 0 }
        @{ Case = 'passes 30 days'; Over = @{ deleteRetentionDays = 30 }; Status = 'Pass'; Count = 0 }
        @{ Case = 'fails 6 days'; Over = @{ deleteRetentionDays = 6 }; Status = 'Fail'; Count = 1 }
        @{ Case = 'fails 1 day'; Over = @{ deleteRetentionDays = 1 }; Status = 'Fail'; Count = 1 }
        @{ Case = 'fails soft delete off'; Over = @{ deleteRetentionEnabled = $false; deleteRetentionDays = $null }; Status = 'Fail'; Count = 1 }
    ) {
        $f = (Invoke-ScoutTestRuleSet -Pattern 'waf.reliability' -Collect (New-StorageCollect (New-BlobRow $Over)) -Assessment 'x') | Where-Object Id -eq 'WAF-RE-13'
        $f.Status | Should -Be $Status
        $f.EvidenceCount | Should -Be $Count
    }

    It 'is NotAssessed when the blob service was never read' {
        $c = New-StorageCollect @() -Measured $false
        ((Invoke-ScoutTestRuleSet -Pattern 'waf.reliability' -Collect $c -Assessment 'x') | Where-Object Id -eq 'WAF-RE-13').Status | Should -Be 'NotAssessed'
    }
}

Describe 'CAF-DB-07: SQL Server auditing is enabled' {
    It '<Case>' -ForEach @(
        @{ Case = 'passes Enabled'; State = 'Enabled'; Status = 'Pass'; Count = 0 }
        @{ Case = 'fails Disabled'; State = 'Disabled'; Status = 'Fail'; Count = 1 }
        @{ Case = 'fails a state the service did not return'; State = $null; Status = 'Fail'; Count = 1 }
    ) {
        $f = (Invoke-ScoutTestRuleSet -Pattern 'caf.databases' -Collect (New-AuditCollect $State) -Assessment 'x') | Where-Object Id -eq 'CAF-DB-07'
        $f.Status | Should -Be $Status
        $f.EvidenceCount | Should -Be $Count
    }

    It 'is NotAssessed when auditing was never read' {
        ((Invoke-ScoutTestRuleSet -Pattern 'caf.databases' -Collect (New-AuditCollect 'Disabled' -Measured $false) -Assessment 'x') | Where-Object Id -eq 'CAF-DB-07').Status | Should -Be 'NotAssessed'
    }
}

Describe 'CAF-WEB-06: Always On and a health check path are configured on web apps' {
    It '<Case>' -ForEach @(
        @{ Case = 'passes a web app with both set'; Config = @{}; Kind = 'app,linux'; Status = 'Pass'; Count = 0 }
        @{ Case = 'fails Always On off'; Config = @{ alwaysOn = $false }; Kind = 'app'; Status = 'Fail'; Count = 1 }
        @{ Case = 'fails no health check path'; Config = @{ healthCheckPathSet = $false }; Kind = 'app,linux'; Status = 'Fail'; Count = 1 }
        @{ Case = 'does not score a function app (no Always On on Consumption)'; Config = @{ alwaysOn = $false; healthCheckPathSet = $false }; Kind = 'functionapp,linux'; Status = 'Pass'; Count = 0 }
    ) {
        $f = (Invoke-ScoutTestRuleSet -Pattern 'caf.web' -Collect (New-WebCollect -Config $Config -Kind $Kind) -Assessment 'x') | Where-Object Id -eq 'CAF-WEB-06'
        $f.Status | Should -Be $Status
        $f.EvidenceCount | Should -Be $Count
        $f.Manual | Should -BeFalse
    }

    It 'matches the configuration to the web app whatever the id casing' {
        $c = New-WebCollect -Config @{ alwaysOn = $false }
        $c.domains.web.webApps[0].id = $c.domains.web.webApps[0].id.ToUpperInvariant()
        ((Invoke-ScoutTestRuleSet -Pattern 'caf.web' -Collect $c -Assessment 'x') | Where-Object Id -eq 'CAF-WEB-06').Status | Should -Be 'Fail'
    }

    It 'is NotAssessed when site configuration was never read, even with rows present' {
        $c = New-WebCollect -Config @{ alwaysOn = $false } -Measured $false
        ((Invoke-ScoutTestRuleSet -Pattern 'caf.web' -Collect $c -Assessment 'x') | Where-Object Id -eq 'CAF-WEB-06').Status | Should -Be 'NotAssessed'
    }
}

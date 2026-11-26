#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#9300, 3.18.20 -- the policies of Azure SQL databases and servers, end to end.

    Resource Graph indexes SQL servers and databases but none of their policy children, so Get-ScoutArmChildResource reads six
    datasets with ARM GETs: per user database the short-term (point-in-time restore) and long-term backup retention policies and
    transparent data encryption, and per server the firewall rules, the encryption protector and the security alert policies.
    The shared contract is asserted by tests/helpers/DepthChildHarness.ps1; this file adds what is particular to SQL:

      - `master` and a System-tier database are never asked, and a dedicated SQL pool is asked for TDE only;
      - the firewall rules' ADDRESSES never leave the sweep: each rule becomes three booleans (allows everything, allows Azure
        services, spans a /8 or more) and the shaper counts them, so CAF-DB-06 reads "allow all" without any address;
      - an email address, a storage endpoint and a storage key in a security alert policy, and the Key Vault key of the encryption
        protector, are never read.

    No Azure connection, credential, tenant or subscription identifier is involved.
#>

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutArmChildResource.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertFrom-ScoutInventory.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertTo-ScoutChildDiscoveryResource.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'helpers/DepthChildHarness.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'helpers/DepthFamilyCases.ps1')
    $script:Family = @(Get-DepthFamilyCase | Where-Object { $_.Name -eq 'Sql' })[0]
}

AfterAll { Remove-DepthStub }

Describe 'Get-ScoutArmChildResource -- Azure SQL: what is asked and what is kept' {

    It 'asks nothing without a SQL server or database, and nothing about master' {
        Assert-DepthNothingAskedWithoutParent -Family $script:Family
    }

    It 'issues the documented request for every dataset: path, api-version, one list per database or server' {
        Assert-DepthDocumentedRequest -Family $script:Family
    }

    It 'carries no firewall address, key name, thumbprint, e-mail address, storage endpoint or storage key' {
        Assert-DepthNoSecret -Family $script:Family
    }

    It 'leaves every dataset empty and unmeasured when every GET is denied, so a rule reads NotAssessed' {
        Assert-DepthDeniedIsNotMeasured -Family $script:Family
    }

    It 'treats an empty list as an answer: measured, no rows' {
        Assert-DepthEmptyIsAnAnswer -Family $script:Family
    }

    It 'retries a throttled request and does not report it as a failure' {
        Assert-DepthRetriesAThrottledRequest -Family $script:Family
    }

    It 'asks a dedicated SQL pool for transparent data encryption only, not for backup retention policies it does not have' {
        Install-DepthStub -Routes $script:Family.Routes
        $pool = @($script:Family.Parents | Where-Object name -eq 'dw1')
        $null = Invoke-DepthSweep -Resources $pool -Dataset $script:Family.Datasets
        $script:StubCalls.Count | Should -Be 1
        $script:StubCalls[0] | Should -Match '/databases/dw1/transparentDataEncryption\?'
    }

    It 'treats a 404 for a policy as an empty answer, not a failure' {
        Install-DepthStub -Routes @{}
        $sweep = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset $script:Family.Datasets
        @($sweep.Warnings).Count | Should -Be 0
        @($sweep.Health).Count | Should -Be 0
        (Get-DepthShaped -Sweep $sweep -Resources $script:Family.Parents).sqlTdeMeasured | Should -BeTrue
    }
}

Describe 'ConvertFrom-ScoutInventory -- SQL datasets' {

    BeforeAll {
        Install-DepthStub -Routes $script:Family.Routes
        $script:Sweep = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset $script:Family.Datasets
        $script:Shaped = Get-DepthShaped -Sweep $script:Sweep -Resources $script:Family.Parents
    }

    It 'sets every Measured flag when the datasets were answered' {
        foreach ($key in $script:Family.Keys) { $script:Shaped["${key}Measured"] | Should -BeTrue -Because $key }
    }

    It 'shapes point-in-time restore retention against the 7-day service default, and long-term retention as configured or not' {
        $short = @($script:Shaped.sqlBackupShortTerm)
        $short.Count | Should -Be 1
        $short[0].retentionDays | Should -Be 3
        $short[0].meetsMinimumRetention | Should -BeFalse
        $short[0].databaseName | Should -Be 'db1'
        $short[0].sqlServerId | Should -Be $script:Family.Parents[0].id.ToLowerInvariant() -Because 'the server is the database id up to /databases/'
        $long = @($script:Shaped.sqlBackupLongTerm)[0]
        $long.ltrConfigured | Should -BeTrue -Because 'a weekly retention of P4W is a configured retention'
        $long.monthlyRetention | Should -Be 'PT0S'
    }

    It 'reads long-term retention of PT0S in every period as not configured' {
        $none = @{}
        foreach ($path in $script:Family.Routes.Keys) { $none[$path] = $script:Family.Routes[$path] }
        $key = @($none.Keys | Where-Object { $_ -like '*/backupLongTermRetentionPolicies' })[0]
        $none[$key] = @{ Status = 200; Body = (ConvertTo-DepthBody @{ value = @(@{ id = "$key/default"; name = 'default'; properties = @{ weeklyRetention = 'PT0S'; monthlyRetention = 'PT0S'; yearlyRetention = 'PT0S' } }) }) }
        Install-DepthStub -Routes $none
        $sweep = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset @('SqlDatabaseBackupLongTerm')
        (@((Get-DepthShaped -Sweep $sweep -Resources $script:Family.Parents).sqlBackupLongTerm)[0]).ltrConfigured | Should -BeFalse
    }

    It 'shapes transparent data encryption per database, a disabled pool included' {
        $tde = @($script:Shaped.sqlTde)
        $tde.Count | Should -Be 2
        (@($tde | Where-Object databaseName -eq 'db1')[0]).enabled | Should -BeTrue
        (@($tde | Where-Object databaseName -eq 'dw1')[0]).enabled | Should -BeFalse
    }

    It 'reduces firewall rules to counts: allow-all, Azure services and broad ranges -- with no address anywhere' {
        $firewall = @($script:Shaped.sqlFirewallRules)
        $firewall.Count | Should -Be 1
        $firewall[0].ruleCount | Should -Be 4
        $firewall[0].allowAllRuleCount | Should -Be 1
        $firewall[0].allowsAllInternet | Should -BeTrue
        $firewall[0].allowAzureServicesRuleCount | Should -Be 1
        $firewall[0].broadRangeRuleCount | Should -Be 1 -Because '10.0.0.0 to 10.255.255.255 is a /8'
        ($script:Shaped.sqlFirewallRules | ConvertTo-Json -Depth 5) | Should -Not -Match '\d+\.\d+\.\d+\.\d+'
        # The rows themselves carry booleans, not addresses.
        $ruleRows = @($script:Sweep.Rows | Where-Object { $_.TYPE -eq 'AZSC/ARMChild/SqlServerFirewallRules' })
        $ruleRows.Count | Should -Be 4
        ($ruleRows | ConvertTo-Json -Depth 8) | Should -Not -Match 'startIpAddress|endIpAddress'
    }

    It 'gives a server with no firewall rule a row of zeros, because the empty list was an answer' {
        $empty = @{}
        foreach ($path in $script:Family.Routes.Keys) { $empty[$path] = $script:Family.Routes[$path] }
        $key = @($empty.Keys | Where-Object { $_ -like '*/firewallRules' })[0]
        $empty[$key] = @{ Status = 200; Body = '{"value":[]}' }
        Install-DepthStub -Routes $empty
        $sweep = Invoke-DepthSweep -Resources $script:Family.Parents -Dataset @('SqlServerFirewallRules')
        $row = @((Get-DepthShaped -Sweep $sweep -Resources $script:Family.Parents).sqlFirewallRules)
        $row.Count | Should -Be 1
        $row[0].ruleCount | Should -Be 0
        $row[0].allowAllRuleCount | Should -Be 0
    }

    It 'shapes the encryption protector and security alert policy without the key, the e-mail addresses or the storage' {
        $protector = @($script:Shaped.sqlEncryptionProtector)[0]
        $protector.serverKeyType | Should -Be 'AzureKeyVault'
        $protector.customerManagedKey | Should -BeTrue
        $protector.autoRotationEnabled | Should -BeTrue
        $alert = @($script:Shaped.sqlSecurityAlertPolicies)[0]
        $alert.enabled | Should -BeTrue
        $alert.retentionDays | Should -Be 30
        $alert.disabledAlertCount | Should -Be 1
        $alert.emailAddressCount | Should -Be 1
    }

    It 'mirrors every row under a real SQL type for the discovery index' {
        $twins = @(ConvertTo-ScoutChildDiscoveryResource -Resources @($script:Sweep.Rows))
        @($twins.type | Sort-Object -Unique) | Should -Be @(
            'microsoft.sql/servers/databases/backuplongtermretentionpolicies', 'microsoft.sql/servers/databases/backupshorttermretentionpolicies',
            'microsoft.sql/servers/databases/transparentdataencryption', 'microsoft.sql/servers/encryptionprotector',
            'microsoft.sql/servers/firewallrules', 'microsoft.sql/servers/securityalertpolicies')
    }
}

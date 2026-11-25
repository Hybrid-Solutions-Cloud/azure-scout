#Requires -Version 7.0
#Requires -Modules Pester

<#
    AB#9300 phase 4, batch 2 -- eight per-resource ARM GET datasets, end to end.

    Settings the Well-Architected service guides check that Resource Graph does not carry are read
    with one ARM GET per resource (Get-ScoutArmChildResource), shaped by ConvertFrom-ScoutInventory
    and placed in collect.json by Invoke-Collect. The unit tests for each stage live beside that
    stage (Collect.ArmChildResources, CollectorCollapse, Collect.ShapedDatasetsReachTheResult);
    this file holds the two properties that only show when the stages run together:

      1. NOTHING SECRET SURVIVES THE WHOLE PIPELINE. Every response here sits next to a secret or
         an identifier a collect.json must not carry (a SQL auditing storage key, a web app's app
         settings and connection strings, a failover group's partner server, an Event Hubs partner
         namespace, a Redis Enterprise linked database). The real collector runs against a payload
         with a marker planted in each, and the serialised collect must contain none of them.
      2. THE MEASURED FLAGS TELL THE TRUTH. A flag is true only when a GET was answered, so a rule
         gating on it reports NotAssessed -- never a vacuous Pass -- when the sweep did not run or
         every GET failed.

    No Azure connection: Invoke-AzRestMethod, Search-AzGraph, Get-ScoutRawInventory and the two
    non-ARG sweeps are stubbed.
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutArmChildResource.ps1')

    function Import-Module {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Intentional local override of a built-in cmdlet so Invoke-Collect does not import Az modules during the test.')]
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Shadow function must accept whatever arguments the code under test passes.')]
        param([Parameter(ValueFromRemainingArguments)] $Rest)
    }
    function Get-ScoutDefenderPlanSweep {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Stub must accept the real signature.')]
        param([object[]] $Subscriptions)
        return @()
    }
    function Get-ScoutExternalIdentitiesPolicy {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Stub must accept the real signature.')]
        param([string] $TenantID)
        return [pscustomobject]@{ Collected = $false }
    }
    function Search-AzGraph {
        [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Stub must accept the real signature.')]
        param([Parameter(ValueFromRemainingArguments)] $Rest)
        return @()
    }
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/Invoke-Collect.ps1')

    $script:Sentinels = @(
        'SENTINEL-KEY-001', 'SENTINEL-SUBID-002', 'SENTINEL-STORAGE-003', 'SENTINEL-PARTNER-004',
        'SENTINEL-APPSETTING-005', 'SENTINEL-CONN-006', 'SENTINEL-PATH-007', 'SENTINEL-NAMESPACE-008',
        'SENTINEL-ALIAS-009', 'SENTINEL-NICK-010', 'SENTINEL-LINKED-011', 'SENTINEL-ARGS-012',
        'SENTINEL-ORIGIN-013', 'SENTINEL-DOC-014'
    )

    $script:Parents = @(
        foreach ($spec in @(
                @{ Type = 'microsoft.storage/storageaccounts'; Name = 'stone'; Kind = 'StorageV2' }
                @{ Type = 'microsoft.sql/servers'; Name = 'sqlone'; Kind = $null }
                @{ Type = 'microsoft.web/sites'; Name = 'webone'; Kind = 'app' }
                @{ Type = 'microsoft.eventhub/namespaces'; Name = 'ehone'; Kind = $null }
                @{ Type = 'microsoft.cache/redisenterprise'; Name = 'redisone'; Kind = $null }
            )) {
            [pscustomobject]@{
                id             = "/subscriptions/sub1/resourceGroups/rg1/providers/$($spec.Type)/$($spec.Name)"
                name           = $spec.Name
                type           = $spec.Type
                kind           = $spec.Kind
                location       = 'eastus'
                resourceGroup  = 'rg1'
                subscriptionId = 'sub1'
                properties     = [pscustomobject]@{}
            }
        }
    )

    function Get-Payload {
        param([string] $Path)
        $trimmed = ($Path -split '\?')[0]
        switch -Regex ($trimmed) {
            '/blobServices/default$' {
                return @{ id = $trimmed; name = 'default'; properties = @{
                        deleteRetentionPolicy = @{ enabled = $true; days = 14 }; isVersioningEnabled = $true
                        cors = @{ corsRules = @(@{ allowedOrigins = @('https://SENTINEL-ORIGIN-013') }) }
                        staticWebsite = @{ enabled = $true; indexDocument = 'SENTINEL-DOC-014' }
                    } }
            }
            '/fileServices/default$' {
                return @{ id = $trimmed; name = 'default'; properties = @{
                        shareDeleteRetentionPolicy = @{ enabled = $true; days = 9 }
                        protocolSettings = @{ smb = @{ versions = 'SMB3.1.1' } }
                        cors = @{ corsRules = @(@{ allowedOrigins = @('https://SENTINEL-ORIGIN-013') }) }
                    } }
            }
            '/auditingSettings/default$' {
                return @{ id = $trimmed; name = 'default'; properties = @{
                        state = 'Enabled'; isAzureMonitorTargetEnabled = $true
                        storageAccountAccessKey = 'SENTINEL-KEY-001'; storageAccountSubscriptionId = 'SENTINEL-SUBID-002'
                        storageEndpoint = 'https://SENTINEL-STORAGE-003.blob.core.windows.net'
                    } }
            }
            '/failoverGroups$' {
                return @{ value = @(@{ id = "$trimmed/fg1"; name = 'fg1'; properties = @{
                                readWriteEndpoint = @{ failoverPolicy = 'Automatic' }
                                partnerServers = @(@{ id = '/subscriptions/x/providers/Microsoft.Sql/servers/SENTINEL-PARTNER-004' })
                            } }) }
            }
            '/config/web$' {
                return @{ id = $trimmed; name = 'web'; properties = @{
                        ftpsState = 'FtpsOnly'; alwaysOn = $true; healthCheckPath = '/SENTINEL-PATH-007'
                        appSettings = @(@{ name = 'K'; value = 'SENTINEL-APPSETTING-005' })
                        connectionStrings = @(@{ name = 'db'; connectionString = 'SENTINEL-CONN-006' })
                    } }
            }
            '/basicPublishingCredentialsPolicies/(ftp|scm)$' {
                return @{ id = $trimmed; name = $Matches[1]; properties = @{ allow = ($Matches[1] -eq 'scm') } }
            }
            '/disasterRecoveryConfigs$' {
                return @{ value = @(@{ id = "$trimmed/alias1"; name = 'alias1'; properties = @{
                                role = 'Primary'; provisioningState = 'Succeeded'
                                partnerNamespace = '/subscriptions/x/providers/Microsoft.EventHub/namespaces/SENTINEL-NAMESPACE-008'
                                alternateName = 'SENTINEL-ALIAS-009'
                            } }) }
            }
            '/databases$' {
                return @{ value = @(@{ id = "$trimmed/default"; name = 'default'; properties = @{
                                accessKeysAuthentication = 'Disabled'; clientProtocol = 'Encrypted'
                                persistence = @{ aofEnabled = $true }
                                geoReplication = @{ groupNickname = 'SENTINEL-NICK-010'; linkedDatabases = @(@{ id = '/x/SENTINEL-LINKED-011' }) }
                                modules = @(@{ name = 'RedisJSON'; args = 'SENTINEL-ARGS-012' })
                            } }) }
            }
            default { return @{ value = @() } }
        }
    }

    # The raw pass is stubbed, but the ARM-child collector inside it is the real one, so what comes
    # back is exactly what a live run would hand to Invoke-Collect.
    function Set-RawInventoryStub {
        param([ValidateSet('Answered', 'Denied')] [string] $Mode)
        $script:Mode = $Mode
        $script:CapturedArmChildDataset = $null
        function global:Invoke-AzRestMethod {
            param([string] $Path, [string] $Uri, [string] $Method, [Parameter(ValueFromRemainingArguments)] $Rest)
            $null = $Method, $Rest
            $request = if ($Uri) { $Uri } else { $Path }
            if ($script:Mode -eq 'Denied') {
                return [pscustomobject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' }
            }
            [pscustomobject]@{ StatusCode = 200; Content = (Get-Payload -Path $request | ConvertTo-Json -Depth 12 -Compress) }
        }
        function global:Get-ScoutRawInventory {
            [Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '', Justification = 'Stub must accept the real signature; only the ARM-child parameters are used.')]
            param([switch] $IncludeArmChildResources, [string[]] $ArmChildDataset, [Parameter(ValueFromRemainingArguments)] $Rest)
            $script:CapturedArmChildDataset = $ArmChildDataset
            $health = [System.Collections.Generic.List[object]]::new()
            $operations = [System.Collections.Generic.List[object]]::new()
            $children = @(Get-ScoutArmChildResource -Resources $script:Parents -Dataset $ArmChildDataset `
                    -CollectionHealth $health -SourceOperations $operations -WarningAction SilentlyContinue)
            [pscustomobject]@{
                Resources          = @($script:Parents) + $children
                ResourceContainers = @()
                SourceOperations   = @($operations)
                CollectionHealth   = @($health)
            }
        }
    }
}

AfterAll {
    foreach ($name in 'Invoke-AzRestMethod', 'Get-ScoutRawInventory') {
        Remove-Item -Path "Function:\$name" -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-Collect -- per-resource ARM GET datasets (AB#9300 phase 4, batch 2)' {

    Context 'every GET is answered' {
        BeforeAll {
            Set-RawInventoryStub -Mode Answered
            $script:Collect = Invoke-Collect -Categories @('*') -WarningAction SilentlyContinue
            $script:Json = $script:Collect | ConvertTo-Json -Depth 20
        }

        It 'asks the assessment collect for all eight datasets alongside the diagnostic sweep' {
            @($script:CapturedArmChildDataset) | Should -Be @(
                'ResourceDiagnosticSettings'
                'StorageBlobServiceProperties', 'StorageFileServiceProperties'
                'SqlServerAuditing', 'SqlFailoverGroups'
                'WebAppConfig', 'WebAppBasicAuth'
                'EventHubGeoDr', 'RedisEnterpriseDatabases'
            )
        }

        It 'places each dataset in its domain, keyed by the lower-cased parent id' {
            $storage = $script:Collect.domains.storage
            $storage.blobServiceProperties[0].storageAccountId | Should -BeExactly '/subscriptions/sub1/resourcegroups/rg1/providers/microsoft.storage/storageaccounts/stone'
            $storage.blobServiceProperties[0].deleteRetentionEnabled | Should -BeTrue
            $storage.blobServiceProperties[0].versioningEnabled | Should -BeTrue
            $storage.fileServiceProperties[0].smbVersions | Should -BeExactly 'SMB3.1.1'

            $databases = $script:Collect.domains.databases
            $databases.sqlServerAuditing[0].auditingState | Should -BeExactly 'Enabled'
            $databases.sqlServerAuditing[0].azureMonitorTargetEnabled | Should -BeTrue
            $databases.sqlFailoverGroups[0].failoverGroupCount | Should -Be 1
            $databases.sqlFailoverGroups[0].hasAutomaticFailover | Should -BeTrue
            $databases.redisEnterpriseDatabases[0].accessKeysAuthentication | Should -BeExactly 'Disabled'
            $databases.redisEnterpriseDatabases[0].geoReplicationLinkCount | Should -Be 1

            $web = $script:Collect.domains.web
            $web.webAppConfig[0].ftpsState | Should -BeExactly 'FtpsOnly'
            $web.webAppConfig[0].healthCheckPathSet | Should -BeTrue
            $web.webAppBasicAuth[0].ftpBasicAuthAllowed | Should -BeFalse
            $web.webAppBasicAuth[0].scmBasicAuthAllowed | Should -BeTrue

            $script:Collect.domains.integration.eventHubGeoDr[0].geoDrConfigured | Should -BeTrue
        }

        It 'sets every Measured flag, in the same domain as its dataset' {
            $script:Collect.domains.storage.blobServicePropertiesMeasured | Should -BeTrue
            $script:Collect.domains.storage.fileServicePropertiesMeasured | Should -BeTrue
            $script:Collect.domains.databases.sqlServerAuditingMeasured | Should -BeTrue
            $script:Collect.domains.databases.sqlFailoverGroupsMeasured | Should -BeTrue
            $script:Collect.domains.databases.redisEnterpriseDatabasesMeasured | Should -BeTrue
            $script:Collect.domains.web.webAppConfigMeasured | Should -BeTrue
            $script:Collect.domains.web.webAppBasicAuthMeasured | Should -BeTrue
            $script:Collect.domains.integration.eventHubGeoDrMeasured | Should -BeTrue
        }

        It 'measures diagnostic coverage on the same run (the sweep is shared)' {
            $script:Collect.opsPosture.diagnosticCoverageMeasured | Should -BeTrue
        }

        It 'carries no secret, key, app setting, connection string or partner id anywhere in the serialised collect' {
            foreach ($sentinel in $script:Sentinels) {
                $script:Json | Should -Not -Match ([regex]::Escape($sentinel)) -Because "$sentinel sits in a property the allow-list excludes"
            }
            # Positive control: the planted payloads were read, so the absence above is the
            # projection's doing and not an empty fixture.
            $script:Json | Should -Match 'FtpsOnly'
            $script:Json | Should -Match 'SMB3\.1\.1'
        }
    }

    Context 'every GET is denied' {
        BeforeAll {
            Set-RawInventoryStub -Mode Denied
            $script:Denied = Invoke-Collect -Categories @('*') -WarningAction SilentlyContinue
        }

        It 'leaves every dataset empty and every Measured flag false, so a rule reports NotAssessed instead of passing' {
            $domains = $script:Denied.domains
            foreach ($pair in @(
                    @($domains.storage, 'blobServiceProperties'), @($domains.storage, 'fileServiceProperties'),
                    @($domains.databases, 'sqlServerAuditing'), @($domains.databases, 'sqlFailoverGroups'),
                    @($domains.databases, 'redisEnterpriseDatabases'), @($domains.web, 'webAppConfig'),
                    @($domains.web, 'webAppBasicAuth'), @($domains.integration, 'eventHubGeoDr'))) {
                $section, $key = $pair
                @($section.$key).Count | Should -Be 0 -Because "$key had no answered GET"
                $section."${key}Measured" | Should -BeFalse -Because "$key was denied for every parent"
            }
        }
    }

    Context 'the typed-query path (no ARM-child sweep)' {
        BeforeAll {
            Remove-Item -Path 'Function:\Get-ScoutRawInventory' -Force -ErrorAction SilentlyContinue
            $script:Typed = Invoke-Collect -Source TypedQueries -Categories @('*') -WarningAction SilentlyContinue
        }

        It 'declares the same keys, empty and unmeasured, so both paths expose one contract' {
            $domains = $script:Typed.domains
            @($domains.storage.blobServiceProperties).Count | Should -Be 0
            $domains.storage.blobServicePropertiesMeasured | Should -BeFalse
            @($domains.web.webAppBasicAuth).Count | Should -Be 0
            $domains.web.webAppBasicAuthMeasured | Should -BeFalse
            $domains.integration.eventHubGeoDrMeasured | Should -BeFalse
            $domains.databases.sqlFailoverGroupsMeasured | Should -BeFalse
        }
    }
}

Describe 'The allow-list stays an allow-list (AB#9300 phase 4, batch 2)' {

    BeforeAll {
        # Comment lines are stripped: the file explains what it must never read, and a scan over the
        # raw text would flag that explanation as the offence.
        $script:CollectorCode = (
            Get-Content (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutArmChildResource.ps1') |
                Where-Object { $_ -notmatch '^\s*#' }
        ) -join "`n"
        $script:AllowList = [regex]::Match($script:CollectorCode, '(?s)\$SafeChildPropertyPaths = @\{.*?\r?\n    \}').Value
    }

    It 'parses a non-trivial allow-list out of the collector' {
        $script:AllowList | Should -Not -BeNullOrEmpty
        ([regex]::Matches($script:AllowList, "'[A-Za-z.]+'")).Count | Should -BeGreaterThan 25
    }

    It 'lists no secret-bearing or identifying path' {
        foreach ($forbidden in 'storageAccountAccessKey', 'storageAccountSubscriptionId', 'storageEndpoint', 'appSettings',
            'connectionStrings', 'healthCheckPath', 'partnerServers', 'partnerNamespace', 'alternateName', 'linkedDatabases',
            'groupNickname', 'modules', 'cors', 'staticWebsite', 'ipSecurityRestrictions', 'publishingUsername', 'primaryKey',
            'secondaryKey') {
            $script:AllowList | Should -Not -Match "'$forbidden" -Because "$forbidden must never be an allow-listed path"
        }
    }

    It 'never calls a list-secrets endpoint' {
        $script:CollectorCode | Should -Not -Match '(?i)listkeys|/config/appsettings|/config/connectionstrings|list/action|/listSecrets|/publishxml|/publishingcredentials/list'
    }
}

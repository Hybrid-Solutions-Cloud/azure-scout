#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    AB#9300, 3.18.20 -- App Service authentication and API Management's global policy, APIs and named values.

    Resource Graph indexes a web app and an API Management service but not these children, so Get-ScoutArmChildResource reads four
    datasets with ARM GETs: per web app `config/authsettingsV2` (WebApps_GetAuthSettingsV2WithoutSecrets, a GET; the POST that
    returns secrets is never asked), and per service the global policy, the APIs and the named values. The shared contract is
    asserted by tests/helpers/DepthChildHarness.ps1; this file adds what is particular to these two:

      - the authentication settings' client ids, secret setting names and issuer URLs are never read, and an enabled identity
        provider is counted, including the custom OpenID Connect ones;
      - the global policy XML is scanned for three element names and dropped: the row keeps three booleans, never the document;
      - a named value's VALUE is never read (secret or not); the row keeps whether it is secret and whether Key Vault backs it.

    On whether `appserviceresources` already returns the authentication settings: Resource Graph's App Service table lists
    `microsoft.web/sites/config`, but which config names it returns could not be confirmed (neither the lab nor any banked run has a
    web app), so the dataset makes the GET.

    No Azure connection, credential, tenant or subscription identifier is involved.
#>

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/Get-ScoutArmChildResource.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertFrom-ScoutInventory.ps1')
    . (Join-Path -Path $script:Root -ChildPath 'src/collect/ConvertTo-ScoutChildDiscoveryResource.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'helpers/DepthChildHarness.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'helpers/DepthFamilyCases.ps1')
    $script:Families = @(Get-DepthFamilyCase | Where-Object { $_.Name -in 'WebAuth', 'Apim' })
}

AfterAll { Remove-DepthStub }

Describe 'Get-ScoutArmChildResource -- <Name>: what is asked and what is kept' -ForEach @(
    @{ Name = 'App Service authentication'; Family = 'WebAuth' }
    @{ Name = 'API Management'; Family = 'Apim' }
) {
    BeforeAll { $script:F = @($script:Families | Where-Object { $_.Name -eq $Family })[0] }

    It 'asks nothing without a parent' { Assert-DepthNothingAskedWithoutParent -Family $script:F }
    It 'issues the documented request for every dataset: path and api-version, never a POST' { Assert-DepthDocumentedRequest -Family $script:F }
    It 'carries no client id, secret setting, issuer, policy content, backend URL or named value' { Assert-DepthNoSecret -Family $script:F }
    It 'leaves every dataset empty and unmeasured when every GET is denied' { Assert-DepthDeniedIsNotMeasured -Family $script:F }
    It 'treats an empty list as an answer' {
        if ($script:F.Name -eq 'WebAuth') {
            # authsettingsV2 is a singleton: a 404 is the empty answer.
            Install-DepthStub -Routes @{}
            $sweep = Invoke-DepthSweep -Resources $script:F.Parents -Dataset $script:F.Datasets
            @($sweep.Rows).Count | Should -Be 0
            @($sweep.Warnings).Count | Should -Be 0
            (Get-DepthShaped -Sweep $sweep -Resources $script:F.Parents).webAppAuthMeasured | Should -BeTrue
        }
        else { Assert-DepthEmptyIsAnAnswer -Family $script:F }
    }
    It 'retries a throttled request and does not report it as a failure' { Assert-DepthRetriesAThrottledRequest -Family $script:F }
}

Describe 'ConvertFrom-ScoutInventory -- App Service authentication' {

    BeforeAll {
        $script:F = @($script:Families | Where-Object { $_.Name -eq 'WebAuth' })[0]
        Install-DepthStub -Routes $script:F.Routes
        $script:Sweep = Invoke-DepthSweep -Resources $script:F.Parents -Dataset $script:F.Datasets
        $script:Shaped = Get-DepthShaped -Sweep $script:Sweep -Resources $script:F.Parents
    }

    It 'shapes the platform switch, the requirement, the action for unauthenticated clients and the providers on' {
        $auth = @($script:Shaped.webAppAuth)
        $auth.Count | Should -Be 1
        $auth[0].name | Should -Be 'web1'
        $auth[0].builtInAuthEnabled | Should -BeTrue
        $auth[0].requireAuthentication | Should -BeTrue
        $auth[0].unauthenticatedClientAction | Should -Be 'Return401'
        $auth[0].requireHttps | Should -BeTrue
        $auth[0].entraProviderEnabled | Should -BeTrue
        $auth[0].enabledIdentityProviderCount | Should -Be 2 -Because 'Entra ID and the custom OpenID Connect provider; GitHub is off'
        $auth[0].excludedPathCount | Should -Be 2
    }

    It 'reads an app with built-in authentication switched off as off, not as unknown' {
        $off = @{}
        $key = @($script:F.Routes.Keys)[0]
        $off[$key] = @{ Status = 200; Body = (ConvertTo-DepthBody @{ id = $key; name = 'authsettingsV2'; properties = @{ platform = @{ enabled = $false } } }) }
        Install-DepthStub -Routes $off
        $sweep = Invoke-DepthSweep -Resources $script:F.Parents -Dataset $script:F.Datasets
        $row = @((Get-DepthShaped -Sweep $sweep -Resources $script:F.Parents).webAppAuth)[0]
        $row.builtInAuthEnabled | Should -BeFalse
        $row.enabledIdentityProviderCount | Should -Be 0
    }

    It 'mirrors the row under microsoft.web/sites/config for the discovery index' {
        @((ConvertTo-ScoutChildDiscoveryResource -Resources @($script:Sweep.Rows)).type) | Should -Be @('microsoft.web/sites/config')
    }
}

Describe 'ConvertFrom-ScoutInventory -- API Management' {

    BeforeAll {
        $script:F = @($script:Families | Where-Object { $_.Name -eq 'Apim' })[0]
        Install-DepthStub -Routes $script:F.Routes
        $script:Sweep = Invoke-DepthSweep -Resources $script:F.Parents -Dataset $script:F.Datasets
        $script:Shaped = Get-DepthShaped -Sweep $script:Sweep -Resources $script:F.Parents
    }

    It 'keeps three booleans from the global policy and never the document' {
        $policy = @($script:Shaped.apimGlobalPolicy)
        $policy.Count | Should -Be 1
        $policy[0].policyPresent | Should -BeTrue
        $policy[0].validatesTokens | Should -BeTrue
        $policy[0].limitsRate | Should -BeTrue
        $policy[0].filtersIp | Should -BeFalse
        $row = @($script:Sweep.Rows | Where-Object { $_.TYPE -eq 'AZSC/ARMChild/ApimGlobalPolicy' })[0]
        $row.properties.PSObject.Properties.Name | Should -Not -Contain 'value' -Because 'the policy XML is dropped at the GET'
    }

    It 'reports a service with no global policy as having none, because the empty list was an answer' {
        $none = @{}
        $key = @($script:F.Routes.Keys | Where-Object { $_ -like '*/policies' })[0]
        $none[$key] = @{ Status = 200; Body = '{"value":[]}' }
        Install-DepthStub -Routes $none
        $sweep = Invoke-DepthSweep -Resources $script:F.Parents -Dataset @('ApimGlobalPolicy')
        $row = @((Get-DepthShaped -Sweep $sweep -Resources $script:F.Parents).apimGlobalPolicy)
        $row.Count | Should -Be 1
        $row[0].policyPresent | Should -BeFalse
        $row[0].validatesTokens | Should -BeFalse
    }

    It 'counts APIs that allow plain HTTP, need no subscription and have token authentication configured' {
        $apis = @($script:Shaped.apimApis)
        $apis.Count | Should -Be 1
        $apis[0].apiCount | Should -Be 2
        $apis[0].httpAllowedApiCount | Should -Be 1
        $apis[0].subscriptionNotRequiredApiCount | Should -Be 1
        $apis[0].tokenAuthenticatedApiCount | Should -Be 1
    }

    It 'counts secret named values that are not backed by Key Vault, and never reads a value' {
        $values = @($script:Shaped.apimNamedValues)
        $values.Count | Should -Be 1
        $values[0].namedValueCount | Should -Be 3
        $values[0].secretCount | Should -Be 2
        $values[0].keyVaultBackedSecretCount | Should -Be 1
        $values[0].inlineSecretCount | Should -Be 1
        $nvRows = @($script:Sweep.Rows | Where-Object { $_.TYPE -eq 'AZSC/ARMChild/ApimNamedValues' })
        $nvRows.Count | Should -Be 3
        ($nvRows | ConvertTo-Json -Depth 8) | Should -Not -Match '"value"|displayName'
    }

    It 'mirrors the rows under real API Management types for the discovery index' {
        @((ConvertTo-ScoutChildDiscoveryResource -Resources @($script:Sweep.Rows)).type | Sort-Object -Unique) | Should -Be @(
            'microsoft.apimanagement/service/apis', 'microsoft.apimanagement/service/namedvalues', 'microsoft.apimanagement/service/policies')
    }
}

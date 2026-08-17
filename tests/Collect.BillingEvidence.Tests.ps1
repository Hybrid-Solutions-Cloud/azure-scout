#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:RepoRoot 'src/collect/Get-ScoutBillingEvidence.ps1')

    function New-BillingRestResponse {
        param([object[]] $Value = @(), [string] $NextLink)
        $body = [ordered]@{ value = @($Value) }
        if ($NextLink) { $body.nextLink = $NextLink }
        [pscustomobject]@{ StatusCode = 200; Content = ($body | ConvertTo-Json -Depth 20 -Compress) }
    }
}

Describe 'Get-ScoutBillingEvidence' {
    BeforeEach {
        $script:billingCalls = [System.Collections.Generic.List[string]]::new()
        function global:Invoke-AzRestMethod {
            param([string] $Path, [string] $Uri, [string] $Method, [string] $Payload, [string] $ErrorAction)
            $null = $Payload, $ErrorAction
            $requestUri = if ($Uri) { $Uri } else { $Path }
            $script:billingCalls.Add("$Method $requestUri")
            switch -Regex ($requestUri) {
                'billingAccounts\?api-version' {
                    return New-BillingRestResponse -Value @([pscustomobject]@{
                            id = '/providers/Microsoft.Billing/billingAccounts/account-one'
                            name = 'account-one'; type = 'Microsoft.Billing/billingAccounts'
                            properties = [pscustomobject]@{ agreementType = 'MicrosoftCustomerAgreement'; displayName = 'Account One'; hasReadAccess = $true }
                        })
                }
                '/billingProfiles\?' { return New-BillingRestResponse -Value @([pscustomobject]@{ id='/billing/profile-one'; name='profile-one'; type='Microsoft.Billing/billingAccounts/billingProfiles'; properties=[pscustomobject]@{ displayName='Profile One' } }) }
                '/invoiceSections\?' { return New-BillingRestResponse -Value @([pscustomobject]@{ id='/billing/invoice-one'; name='invoice-one'; type='Microsoft.Billing/billingAccounts/billingProfiles/invoiceSections'; properties=[pscustomobject]@{ displayName='Invoice One' } }) }
                '/billingRoleAssignments\?' { return New-BillingRestResponse -Value @([pscustomobject]@{ id='/billing/role-one'; name='role-one'; properties=[pscustomobject]@{ principalType='User'; principalId='principal-one'; scope='/billing' } }) }
                '/billingRoleDefinitions\?' { return New-BillingRestResponse -Value @([pscustomobject]@{ id='/billing/definition-one'; name='definition-one'; properties=[pscustomobject]@{ roleName='Billing account owner' } }) }
                'listInvoiceSectionsWithCreateSubscriptionPermission' { return New-BillingRestResponse -Value @([pscustomobject]@{ name='invoice-one'; properties=[pscustomobject]@{ invoiceSectionId='/billing/invoice-one' } }) }
                'reservationOrders' { return New-BillingRestResponse -Value @([pscustomobject]@{ id='/providers/Microsoft.Capacity/reservationOrders/res-one'; name='res-one'; type='Microsoft.Capacity/reservationOrders'; properties=[pscustomobject]@{ status='Succeeded' } }) }
                'savingsPlanOrders' { return New-BillingRestResponse -Value @([pscustomobject]@{ id='/providers/Microsoft.BillingBenefits/savingsPlanOrders/sp-one'; name='sp-one'; type='Microsoft.BillingBenefits/savingsPlanOrders'; properties=[pscustomobject]@{ provisioningState='Succeeded' } }) }
                default { return New-BillingRestResponse }
            }
        }
    }

    AfterEach { Remove-Item Function:global:Invoke-AzRestMethod -Force -ErrorAction SilentlyContinue }

    It 'retains every successful billing source object with exact request provenance' {
        $result = Get-ScoutBillingEvidence
        @($result.Resources | Where-Object type -eq 'AZSC/Billing/BillingAccounts').Count | Should -Be 1
        @($result.Resources | Where-Object type -eq 'AZSC/Billing/BillingProfiles').Count | Should -Be 1
        @($result.Resources | Where-Object type -eq 'AZSC/Billing/InvoiceSections').Count | Should -Be 1
        @($result.Resources | Where-Object type -eq 'AZSC/Billing/BillingRoleAssignments').Count | Should -Be 1
        @($result.Resources | Where-Object type -eq 'AZSC/Billing/ReservationOrders').Count | Should -Be 1
        @($result.Resources | Where-Object type -eq 'AZSC/Billing/SavingsPlanOrders').Count | Should -Be 1
        $result.Resources[0].properties.Raw.properties.displayName | Should -Be 'Account One'
        $result.Resources[0].AZSC.Uri | Should -Match 'billingAccounts\?api-version=2024-04-01'
        @($result.SourceOperations | Where-Object Status -eq 'Success').Count | Should -BeGreaterThan 0
        @($result.CollectionHealth | Where-Object Status -eq 'NotAssessed').Dataset | Should -Contain 'Billing/SubscriptionVendingProcess'
    }

    It 'uses POST only for the MCA subscription-creation permission endpoint' {
        $null = Get-ScoutBillingEvidence
        @($script:billingCalls | Where-Object { $_ -like 'POST *' }).Count | Should -Be 1
        @($script:billingCalls | Where-Object { $_ -like 'POST *listInvoiceSectionsWithCreateSubscriptionPermission*' }).Count | Should -Be 1
    }

    It 'records billing RBAC denial as unavailable without losing independent benefit evidence' {
        function global:Invoke-AzRestMethod {
            param([string] $Path, [string] $Uri, [string] $Method, [string] $Payload, [string] $ErrorAction)
            $null = $Method, $Payload, $ErrorAction
            $requestUri = if ($Uri) { $Uri } else { $Path }
            if ($requestUri -match 'billingAccounts\?') {
                $exception = [System.InvalidOperationException]::new('HTTP 403 AuthorizationFailed')
                $exception.Data['StatusCode'] = 403
                throw $exception
            }
            return New-BillingRestResponse
        }

        $result = Get-ScoutBillingEvidence
        @($result.CollectionHealth | Where-Object Dataset -eq 'Billing/BillingAccounts').Count | Should -Be 1
        @($result.SourceOperations | Where-Object { $_.Dataset -eq 'BillingAccounts' -and $_.Status -eq 'Unavailable' }).Count | Should -Be 1
        @($result.SourceOperations | Where-Object Dataset -eq 'ReservationOrders').Count | Should -Be 1
        @($result.Resources).Count | Should -Be 0
    }

    It 'ships importable billing report manifests' {
        foreach ($name in 'BillingAccounts','BillingHierarchy','BillingRoles','BillingBenefits') {
            { Import-PowerShellDataFile (Join-Path $script:RepoRoot "manifests/collectors/Management/$name.psd1") } | Should -Not -Throw
        }
    }
}

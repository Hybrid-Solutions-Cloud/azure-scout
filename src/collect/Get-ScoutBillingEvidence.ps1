#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#+
.SYNOPSIS
    Collects the caller-visible Azure billing hierarchy, billing roles, and billing benefits.

.DESCRIPTION
    Uses read-only Azure Resource Manager endpoints. Billing access is independent of subscription
    Reader, so every request records Success, Empty, or Unavailable. Returned wire objects are kept
    intact under properties.Raw and stamped with the exact source request.
#>
function Get-ScoutBillingEvidence {
    [CmdletBinding()]
    param()

    $resources = [System.Collections.Generic.List[object]]::new()
    $sourceOperations = [System.Collections.Generic.List[object]]::new()
    $collectionHealth = [System.Collections.Generic.List[object]]::new()

    function Get-BillingValue {
        param([AllowNull()][object] $InputObject, [Parameter(Mandatory)][string] $Path)
        $current = $InputObject
        foreach ($segment in $Path.Split('.')) {
            if ($null -eq $current) { return $null }
            if ($current -is [System.Collections.IDictionary]) {
                $key = @($current.Keys | Where-Object { [string]$_ -ieq $segment } | Select-Object -First 1)
                if ($key.Count -eq 0) { return $null }
                $current = $current[$key[0]]
                continue
            }
            $property = @($current.PSObject.Properties | Where-Object Name -ieq $segment | Select-Object -First 1)
            if ($property.Count -eq 0) { return $null }
            $current = $property[0].Value
        }
        return $current
    }

    function Get-BillingStatusCode {
        param([System.Management.Automation.ErrorRecord] $ErrorRecord)
        if ($ErrorRecord.Exception.Data.Contains('StatusCode')) {
            try { return [int]$ErrorRecord.Exception.Data['StatusCode'] } catch { return $null }
        }
        if ($ErrorRecord.Exception.PSObject.Properties['Response'] -and $ErrorRecord.Exception.Response) {
            $status = $ErrorRecord.Exception.Response.PSObject.Properties['StatusCode']
            if ($status) { try { return [int]$status.Value } catch { return $null } }
        }
        if ([string]$ErrorRecord.Exception.Message -match '(?i)(?:status(?: code)?|HTTP)\D*(\d{3})') { return [int]$Matches[1] }
        return $null
    }

    function Add-BillingEnvelope {
        param(
            [Parameter(Mandatory)][string] $Dataset,
            [Parameter(Mandatory)][object] $Raw,
            [Parameter(Mandatory)][string] $Uri,
            [Parameter(Mandatory)][string] $Method,
            [Parameter(Mandatory)][datetime] $CollectedAt
        )
        $rawId = [string](Get-BillingValue -InputObject $Raw -Path 'id')
        $rawName = [string](Get-BillingValue -InputObject $Raw -Path 'name')
        if ([string]::IsNullOrWhiteSpace($rawName)) { $rawName = "$Dataset-$($resources.Count + 1)" }
        if ([string]::IsNullOrWhiteSpace($rawId)) { $rawId = "/providers/AzureScout/billing/$Dataset/$([uri]::EscapeDataString($rawName))" }
        $resources.Add([pscustomobject][ordered]@{
                id = "$rawId/providers/AzureScout/evidence"
                name = $rawName
                type = "AZSC/Billing/$Dataset"
                properties = [pscustomobject][ordered]@{ Raw = $Raw }
                AZSC = [pscustomobject][ordered]@{
                    Source = 'Azure Resource Manager Billing API'
                    Dataset = $Dataset
                    Operation = $Method
                    Uri = $Uri
                    ApiVersion = if ($Uri -match '(?i)[?&]api-version=([^&]+)') { [uri]::UnescapeDataString($Matches[1]) } else { $null }
                    CollectedAt = $CollectedAt.ToString('o')
                }
            })
    }

    function Invoke-BillingList {
        param(
            [Parameter(Mandatory)][string] $Dataset,
            [Parameter(Mandatory)][string] $Uri,
            [ValidateSet('GET', 'POST')][string] $Method = 'GET',
            [switch] $OptionalForAgreement
        )
        $items = [System.Collections.Generic.List[object]]::new()
        $seenUris = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $currentUri = $Uri
        $currentMethod = $Method
        while ($currentUri) {
            if (-not $seenUris.Add($currentUri)) { throw "Billing API returned a repeated nextLink '$currentUri'." }
            $startedAt = Get-Date
            try {
                $request = @{ Method = $currentMethod; ErrorAction = 'Stop' }
                if ([uri]::IsWellFormedUriString($currentUri, [System.UriKind]::Absolute)) { $request.Uri = $currentUri } else { $request.Path = $currentUri }
                if ($currentMethod -eq 'POST') { $request.Payload = '{}' }
                $response = Invoke-AzRestMethod @request
                if ($null -eq $response) { throw 'ARM returned no response.' }
                $statusProperty = $response.PSObject.Properties['StatusCode']
                if ($statusProperty -and ([int]$statusProperty.Value -lt 200 -or [int]$statusProperty.Value -ge 300)) {
                    throw "ARM returned HTTP $($statusProperty.Value)."
                }
                $contentProperty = $response.PSObject.Properties['Content']
                $content = if ($contentProperty) { $contentProperty.Value } else { $null }
                if ($content -is [string] -and -not [string]::IsNullOrWhiteSpace($content)) { $content = $content | ConvertFrom-Json }
                [object[]]$pageItems = @()
                if ($null -ne $content) {
                    if ($content.PSObject.Properties['value']) {
                        $pageItems = @($content.value | Where-Object { $null -ne $_ })
                    }
                    else {
                        $pageItems = @($content)
                    }
                }
                $collectedAt = Get-Date
                foreach ($item in $pageItems) {
                    $items.Add($item)
                    Add-BillingEnvelope -Dataset $Dataset -Raw $item -Uri $currentUri -Method $currentMethod -CollectedAt $collectedAt
                }
                $sourceOperations.Add([pscustomobject][ordered]@{
                        Source = 'Azure Resource Manager Billing API'
                        Dataset = $Dataset
                        Operation = $currentMethod
                        Uri = $currentUri
                        Status = if ($pageItems.Count -gt 0) { 'Success' } else { 'Empty' }
                        Count = $pageItems.Count
                        Reason = $null
                        StartedAt = $startedAt.ToString('o')
                        CompletedAt = $collectedAt.ToString('o')
                    })
                $nextLink = if ($null -ne $content -and $content.PSObject.Properties['nextLink']) { [string]$content.nextLink } else { $null }
                $currentUri = if ([string]::IsNullOrWhiteSpace($nextLink)) { $null } else { $nextLink }
                $currentMethod = 'GET'
            }
            catch {
                $statusCode = Get-BillingStatusCode -ErrorRecord $_
                $expectedAgreementGap = $OptionalForAgreement -and $statusCode -in @(400, 404, 409)
                $status = if ($expectedAgreementGap) { 'NotApplicable' } else { 'Unavailable' }
                $reason = $_.Exception.Message
                $sourceOperations.Add([pscustomobject][ordered]@{
                        Source = 'Azure Resource Manager Billing API'
                        Dataset = $Dataset
                        Operation = $currentMethod
                        Uri = $currentUri
                        Status = $status
                        Count = 0
                        Reason = $reason
                        StartedAt = $startedAt.ToString('o')
                        CompletedAt = (Get-Date).ToString('o')
                    })
                if (-not $expectedAgreementGap) {
                    $collectionHealth.Add([pscustomobject]@{
                            Dataset = "Billing/$Dataset"
                            Operation = $currentMethod
                            Status = 'Unavailable'
                            Reason = $reason
                            ResourceTypes = @("AZSC/Billing/$Dataset")
                        })
                }
                break
            }
        }
        return @($items)
    }

    $billingAccounts = @(Invoke-BillingList -Dataset 'BillingAccounts' -Uri '/providers/Microsoft.Billing/billingAccounts?api-version=2024-04-01')
    foreach ($account in $billingAccounts) {
        $accountName = [string](Get-BillingValue -InputObject $account -Path 'name')
        if ([string]::IsNullOrWhiteSpace($accountName)) { continue }
        $accountPath = "/providers/Microsoft.Billing/billingAccounts/$accountName"
        $agreementType = [string](Get-BillingValue -InputObject $account -Path 'properties.agreementType')

        $null = Invoke-BillingList -Dataset 'BillingRoleAssignments' -Uri "$accountPath/billingRoleAssignments?api-version=2024-04-01"
        $null = Invoke-BillingList -Dataset 'BillingRoleDefinitions' -Uri "$accountPath/billingRoleDefinitions?api-version=2024-04-01"

        if ($agreementType -in @('MicrosoftCustomerAgreement', 'MicrosoftPartnerAgreement')) {
            $profiles = @(Invoke-BillingList -Dataset 'BillingProfiles' -Uri "$accountPath/billingProfiles?api-version=2024-04-01")
            foreach ($profile in $profiles) {
                $profileName = [string](Get-BillingValue -InputObject $profile -Path 'name')
                if ($profileName) {
                    $null = Invoke-BillingList -Dataset 'InvoiceSections' -Uri "$accountPath/billingProfiles/$profileName/invoiceSections?api-version=2024-04-01"
                }
            }
        }
        elseif ($agreementType -eq 'EnterpriseAgreement') {
            $null = Invoke-BillingList -Dataset 'Departments' -Uri "$accountPath/departments?api-version=2024-04-01"
            $null = Invoke-BillingList -Dataset 'EnrollmentAccounts' -Uri "$accountPath/enrollmentAccounts?api-version=2024-04-01"
        }

        if ($agreementType -eq 'MicrosoftCustomerAgreement') {
            $null = Invoke-BillingList -Dataset 'SubscriptionCreationPermissions' -Uri "$accountPath/listInvoiceSectionsWithCreateSubscriptionPermission?api-version=2024-04-01" -Method POST
        }
    }

    $null = Invoke-BillingList -Dataset 'ReservationOrders' -Uri '/providers/Microsoft.Capacity/reservationOrders?api-version=2022-11-01'
    $null = Invoke-BillingList -Dataset 'SavingsPlanOrders' -Uri '/providers/Microsoft.BillingBenefits/savingsPlanOrders?api-version=2022-11-01'

    # Subscription vending is an organizational process, not an Azure control-plane object. Keep
    # that evidence gap explicit rather than inventing an answer from role assignments.
    $collectionHealth.Add([pscustomobject]@{
            Dataset = 'Billing/SubscriptionVendingProcess'
            Operation = 'Organizational process evidence'
            Status = 'NotAssessed'
            Reason = 'Subscription vending workflow requires operator-supplied process evidence; Azure APIs expose permissions but not the ticket/IaC/portal process used.'
            ResourceTypes = @('AZSC/Billing/SubscriptionVendingProcess')
        })

    [pscustomobject]@{
        Resources = @($resources)
        SourceOperations = @($sourceOperations)
        CollectionHealth = @($collectionHealth)
    }
}

#
# Hand-authored collector (AB#9300): Playwright Workspaces (Azure App Testing), the successor to the retired Microsoft Playwright Testing, had no collector. Property paths from the Microsoft.LoadTestService playwrightWorkspaces reference (2025-09-01 and later).
#
@{
    ResourceTypes = @('microsoft.loadtestservice/playwrightworkspaces')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
'@

    AdditionalRowLoops = @()

    TagLoop = @{
        Variable = 'Tag'
        Source = '$Tags'
        Preamble = ''
    }

    Fields = @(
        @{ Name = 'ID'; Expression = '$1.id' }
        @{ Name = 'Subscription'; Expression = '(Get-AZSCSafeProperty -InputObject $sub1 -Path ''name'')' }
        @{ Name = 'Resource Group'; Expression = '$1.RESOURCEGROUP' }
        @{ Name = 'Name'; Expression = '$1.NAME' }
        @{ Name = 'Location'; Expression = '$1.LOCATION' }
        @{ Name = 'Local Authentication'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''localAuth'')' }
        @{ Name = 'Regional Affinity'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''regionalAffinity'')' }
        @{ Name = 'Reporting'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''reporting'')' }
        @{ Name = 'Session Artifacts'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''sessionArtifacts'')' }
        @{ Name = 'Subnet'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''subnetId''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Provisioning State'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''provisioningState'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'App Testing Workspaces'
        TableNamePrefix = 'PlaywrightWorkspaces_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Local Authentication'
            'Regional Affinity'
            'Reporting'
            'Session Artifacts'
            'Subnet'
            'Provisioning State'
            'Resource U'
        )
        TagColumns = @(
            'Tag Name'
            'Tag Value'
        )
        TagColumnsBefore = 'Resource U'
        NumberFormat = '0'
        ConditionalText = @()
    }

    SourceCollector = 'manifests/collectors/DevOps/PlaywrightWorkspaces.psd1'

    ManualConversionReason = 'Playwright Workspaces (Azure App Testing), the successor to the retired Microsoft Playwright Testing, had no collector. Property paths from the Microsoft.LoadTestService playwrightWorkspaces reference (2025-09-01 and later).'
}

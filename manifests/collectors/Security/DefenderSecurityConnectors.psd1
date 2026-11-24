#
# Hand-authored collector (AB#9300): Defender for Cloud connectors to AWS, GCP, GitHub, Azure DevOps and GitLab had no collector. Property paths from the Microsoft.Security securityConnectors reference.
#
@{
    ResourceTypes = @('microsoft.security/securityconnectors')

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
        @{ Name = 'Environment'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''environmentName'')' }
        @{ Name = 'Environment Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''environmentData.environmentType'')' }
        @{ Name = 'Hierarchy Identifier'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''hierarchyIdentifier'')' }
        @{ Name = 'Offerings'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''offerings.offeringType'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Defender Connectors'
        TableNamePrefix = 'DefenderConnectors_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Environment'
            'Environment Type'
            'Hierarchy Identifier'
            'Offerings'
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

    SourceCollector = 'manifests/collectors/Security/DefenderSecurityConnectors.psd1'

    ManualConversionReason = 'Defender for Cloud connectors to AWS, GCP, GitHub, Azure DevOps and GitLab had no collector. Property paths from the Microsoft.Security securityConnectors reference.'
}

#
# Hand-authored collector (AB#9300): Defender for Cloud security standard assignments were discovered but not read. Fields verified against live rows on 2026-11-24.
#
@{
    ResourceTypes = @('microsoft.security/standardassignments')

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
        @{ Name = 'Display Name'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''displayName'')' }
        @{ Name = 'Standard'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''assignedStandard.id''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Effect'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''effect'')' }
        @{ Name = 'Description'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''description'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Defender Standard Assignments'
        TableNamePrefix = 'DefenderStdAssign_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Display Name'
            'Standard'
            'Effect'
            'Description'
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

    SourceCollector = 'manifests/collectors/Security/DefenderStandardAssignments.psd1'

    ManualConversionReason = 'Defender for Cloud security standard assignments were discovered but not read. Fields verified against live rows on 2026-11-24.'
}

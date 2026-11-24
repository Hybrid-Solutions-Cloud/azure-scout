#
# Hand-authored collector (AB#9300): Machine configuration (guest configuration) assignments and their compliance were discovered but not read. Fields verified against live rows on 2026-11-24.
#
@{
    ResourceTypes = @('microsoft.guestconfiguration/guestconfigurationassignments')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$target = [string](Get-AZSCSafeProperty -InputObject $data -Path 'targetResourceId')
$targetParts = @($target -split '/' | Where-Object { $_ })
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
        @{ Name = 'Machine'; Expression = 'if ($targetParts.Count) { $targetParts[-1] } else { $null }' }
        @{ Name = 'Machine Type'; Expression = 'if ($targetParts.Count -ge 2) { $targetParts[-2] } else { $null }' }
        @{ Name = 'Configuration'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''guestConfiguration.name'')' }
        @{ Name = 'Compliance Status'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''complianceStatus'')' }
        @{ Name = 'Assignment Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''guestConfiguration.assignmentType'')' }
        @{ Name = 'Assignment Source'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''guestConfiguration.assignmentSource'')' }
        @{ Name = 'Content Type'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''guestConfiguration.contentType'')' }
        @{ Name = 'Last Checked'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''lastComplianceStatusChecked'')' }
        @{ Name = 'Policy Assignment'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''policyAssignmentId''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Machine Configuration'
        TableNamePrefix = 'GuestConfig_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Machine'
            'Machine Type'
            'Configuration'
            'Compliance Status'
            'Assignment Type'
            'Assignment Source'
            'Content Type'
            'Last Checked'
            'Policy Assignment'
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

    SourceCollector = 'manifests/collectors/Management/GuestConfigurationAssignments.psd1'

    ManualConversionReason = 'Machine configuration (guest configuration) assignments and their compliance were discovered but not read. Fields verified against live rows on 2026-11-24.'
}

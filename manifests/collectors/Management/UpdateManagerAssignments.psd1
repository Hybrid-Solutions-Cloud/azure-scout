#
# Hand-authored collector (AB#9300): Update Manager maintenance configuration assignments (which machines follow which patch schedule) were discovered but not read. Fields verified against live rows on 2026-11-24.
#
@{
    ResourceTypes = @('microsoft.maintenance/configurationassignments')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$filter = Get-AZSCSafeProperty -InputObject $data -Path 'filter'
$targetId = [string](Get-AZSCSafeProperty -InputObject $data -Path 'resourceId')
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
        @{ Name = 'Maintenance Configuration'; Expression = '& { $v = [string](Get-AZSCSafeProperty -InputObject $data -Path ''maintenanceConfigurationId''); if ($v) { ($v -split ''/'')[-1] } }' }
        @{ Name = 'Scope'; Expression = 'if ($filter) { ''Dynamic'' } else { ''Resource'' }' }
        @{ Name = 'Target'; Expression = 'if ($targetId -and -not $filter) { ($targetId -split ''/'')[-1] } else { $null }' }
        @{ Name = 'Filter Resource Groups'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''filter.resourceGroups'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Filter Locations'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''filter.locations'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Filter OS Types'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''filter.osTypes'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Filter Resource Types'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''filter.resourceTypes'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Update Manager Assignments'
        TableNamePrefix = 'UpdateAssign_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Maintenance Configuration'
            'Scope'
            'Target'
            'Filter Resource Groups'
            'Filter Locations'
            'Filter OS Types'
            'Filter Resource Types'
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

    SourceCollector = 'manifests/collectors/Management/UpdateManagerAssignments.psd1'

    ManualConversionReason = 'Update Manager maintenance configuration assignments (which machines follow which patch schedule) were discovered but not read. Fields verified against live rows on 2026-11-24.'
}

#
# Hand-authored collector (AB#9300): Alert processing rules, which can add action groups or silently suppress alerts, were discovered but not read. Fields verified against live rows on 2026-11-24.
#
@{
    ResourceTypes = @('microsoft.alertsmanagement/actionrules')

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
$data = $1.PROPERTIES
$Tags = if (![string]::IsNullOrEmpty($1.tags.psobject.properties)) { $1.tags.psobject.properties } else { '0' }
$conditionText = (@(Get-AZSCSafeProperty -InputObject $data -Path 'conditions') | Where-Object { $null -ne $_ } | ForEach-Object { '{0} {1} {2}' -f (Get-AZSCSafeProperty -InputObject $_ -Path 'field'), (Get-AZSCSafeProperty -InputObject $_ -Path 'operator'), (@(Get-AZSCSafeProperty -InputObject $_ -Path 'values') -join '|') }) -join '; '
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
        @{ Name = 'Enabled'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''enabled'')' }
        @{ Name = 'Action'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''actions.actionType'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Action Groups'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''actions.actionGroupIds'' -Enumerate | Where-Object { $_ }).Count' }
        @{ Name = 'Scopes'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''scopes'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Conditions'; Expression = '$conditionText' }
        @{ Name = 'Description'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''description'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Alert Processing Rules'
        TableNamePrefix = 'AlertProcRules_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Enabled'
            'Action'
            'Action Groups'
            'Scopes'
            'Conditions'
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

    SourceCollector = 'manifests/collectors/Monitor/AlertProcessingRules.psd1'

    ManualConversionReason = 'Alert processing rules, which can add action groups or silently suppress alerts, were discovered but not read. Fields verified against live rows on 2026-11-24.'
}

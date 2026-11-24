#
# Hand-authored collector (AB#9300): Defender for Cloud workflow automations and continuous export were discovered but not read. Fields verified against live rows on 2026-11-24.
#
@{
    ResourceTypes = @('microsoft.security/automations')

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
        @{ Name = 'Enabled'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''isEnabled'')' }
        @{ Name = 'Event Sources'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''sources.eventSource'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Action Types'; Expression = '((@(Get-AZSCSafeProperty -InputObject $data -Path ''actions.actionType'' -Enumerate) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join '', '')' }
        @{ Name = 'Scopes'; Expression = '@(Get-AZSCSafeProperty -InputObject $data -Path ''scopes'' | Where-Object { $null -ne $_ }).Count' }
        @{ Name = 'Description'; Expression = '(Get-AZSCSafeProperty -InputObject $data -Path ''description'')' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = '[string]$Tag.Name' }
        @{ Name = 'Tag Value'; Expression = '[string]$Tag.Value' }
    )

    Export = @{
        WorksheetName = 'Defender Automations'
        TableNamePrefix = 'DefenderAutomations_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Enabled'
            'Event Sources'
            'Action Types'
            'Scopes'
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

    SourceCollector = 'manifests/collectors/Security/DefenderAutomations.psd1'

    ManualConversionReason = 'Defender for Cloud workflow automations and continuous export were discovered but not read. Fields verified against live rows on 2026-11-24.'
}

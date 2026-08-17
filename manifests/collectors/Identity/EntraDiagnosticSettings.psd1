@{
    ResourceTypes = @('AZSC/Entra/DiagnosticSettings')
    ResourceTypeMatching='Grouped'; AdditionalFilter=$null; FilterPreamble=''; RowLoopVariable='1'
    Preamble='$raw=Get-AZSCSafeProperty -InputObject $1 -Path ''properties.Raw'';$data=Get-AZSCSafeProperty -InputObject $raw -Path ''properties'''; AdditionalRowLoops=@(); TagLoop=$null
    Fields=@(
        @{Name='ID';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''id'''}
        @{Name='Name';Expression='Get-AZSCSafeProperty -InputObject $1 -Path ''name'''}
        @{Name='Log Analytics Workspace ID';Expression='Get-AZSCSafeProperty -InputObject $data -Path ''workspaceId'''}
        @{Name='Storage Account ID';Expression='Get-AZSCSafeProperty -InputObject $data -Path ''storageAccountId'''}
        @{Name='Event Hub Authorization Rule ID';Expression='Get-AZSCSafeProperty -InputObject $data -Path ''eventHubAuthorizationRuleId'''}
        @{Name='Event Hub Name';Expression='Get-AZSCSafeProperty -InputObject $data -Path ''eventHubName'''}
        @{Name='Enabled Log Categories';Expression='& { $logs=@(Get-AZSCSafeProperty -InputObject $data -Path ''logs'');[string]::Join('', '', @($logs | Where-Object { Get-AZSCSafeProperty -InputObject $_ -Path ''enabled'' } | ForEach-Object { Get-AZSCSafeProperty -InputObject $_ -Path ''category'' })) }'}
    )
    Export=@{WorksheetName='Entra Log Export';TableNamePrefix='EntraLogExport_';Columns=@('Name','Log Analytics Workspace ID','Storage Account ID','Event Hub Authorization Rule ID','Event Hub Name','Enabled Log Categories');TagColumns=@();TagColumnsBefore=$null;NumberFormat='0';ConditionalText=@()}
    SourceCollector='src/collect/Get-ScoutEntraDiagnosticSettingEvidence.ps1'
    ManualConversionReason='Hand-authored for AB#7441 against a typed evidence adapter; SourceCollector is provenance, not a legacy Standard-contract collector. Focused collection and renderer tests are the behavioural evidence.'
}

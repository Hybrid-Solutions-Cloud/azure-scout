@{
    ResourceTypes=@('AZSC/HybridIdentity/EntraConnectScheduler','AZSC/HybridIdentity/EntraConnectConnectors','AZSC/HybridIdentity/EntraConnectGlobalSettings','AZSC/HybridIdentity/EntraConnectService','AZSC/HybridIdentity/EntraConnectHealthAgents','AZSC/HybridIdentity/ActiveDirectoryForest','AZSC/HybridIdentity/ActiveDirectoryDomain','AZSC/HybridIdentity/ActiveDirectoryTrusts')
    ResourceTypeMatching='Grouped';AdditionalFilter=$null;FilterPreamble='';RowLoopVariable='1'
    Preamble='$raw=Get-AZSCSafeProperty -InputObject $1 -Path ''properties.Raw''';AdditionalRowLoops=@();TagLoop=$null
    Fields=@(
        @{Name='ID';Expression='Get-AZSCSafeProperty -InputObject $1 -Path ''id'''}
        @{Name='Evidence Type';Expression='Get-AZSCSafeProperty -InputObject $1 -Path ''type'''}
        @{Name='Name';Expression='Get-AZSCSafeProperty -InputObject $1 -Path ''name'''}
        @{Name='Sync Cycle Enabled';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''SyncCycleEnabled'''}
        @{Name='Next Sync Policy';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''NextSyncCyclePolicyType'''}
        @{Name='Staging Mode';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''StagingModeEnabled'''}
        @{Name='Connector Type';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''ConnectorTypeName'''}
        @{Name='Forest Mode';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''ForestMode'''}
        @{Name='Domain Mode';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''DomainMode'''}
        @{Name='Trust Type';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''TrustType'''}
        @{Name='Trust Direction';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''Direction'''}
    )
    Export=@{WorksheetName='Hybrid Identity Local';TableNamePrefix='HybridIdentityLocal_';Columns=@('Evidence Type','Name','Sync Cycle Enabled','Next Sync Policy','Staging Mode','Connector Type','Forest Mode','Domain Mode','Trust Type','Trust Direction');TagColumns=@();TagColumnsBefore=$null;NumberFormat='0';ConditionalText=@()}
    SourceCollector='src/collect/Get-ScoutHybridIdentityLocalEvidence.ps1'
    ManualConversionReason='Hand-authored for AB#7441 against a typed evidence adapter; SourceCollector is provenance, not a legacy Standard-contract collector. Focused collection and renderer tests are the behavioural evidence.'
}

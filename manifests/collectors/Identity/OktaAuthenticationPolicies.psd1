@{
    ResourceTypes=@('AZSC/Okta/Policies','AZSC/Okta/PolicyRules','AZSC/Okta/NetworkZones','AZSC/Okta/ThreatInsight')
    ResourceTypeMatching='Grouped';AdditionalFilter=$null;FilterPreamble='';RowLoopVariable='1'
    Preamble='$raw=Get-AZSCSafeProperty -InputObject $1 -Path ''properties.Raw''';AdditionalRowLoops=@();TagLoop=$null
    Fields=@(
        @{Name='ID';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''id'''}
        @{Name='Evidence Type';Expression='Get-AZSCSafeProperty -InputObject $1 -Path ''type'''}
        @{Name='Name';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''name'''}
        @{Name='Type';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''type'''}
        @{Name='Status';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''status'''}
        @{Name='Priority';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''priority'''}
        @{Name='Conditions';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''conditions'' | ConvertTo-Json -Depth 20 -Compress'}
        @{Name='Actions / Settings';Expression='@{actions=(Get-AZSCSafeProperty -InputObject $raw -Path ''actions'');settings=(Get-AZSCSafeProperty -InputObject $raw -Path ''settings'')} | ConvertTo-Json -Depth 20 -Compress'}
        @{Name='Parent Policy ID';Expression='Get-AZSCSafeProperty -InputObject $1 -Path ''PARENTID'''}
    )
    Export=@{WorksheetName='Okta Auth Policies';TableNamePrefix='OktaAuthPolicies_';Columns=@('Evidence Type','Name','Type','Status','Priority','Conditions','Actions / Settings','Parent Policy ID');TagColumns=@();TagColumnsBefore=$null;NumberFormat='0';ConditionalText=@()}
    SourceCollector='src/collect/Get-ScoutOktaEvidence.ps1'
    ManualConversionReason='Hand-authored for AB#7441 against the optional Okta evidence adapter; SourceCollector is provenance, not a legacy Standard-contract collector. Focused collection and renderer tests are the behavioural evidence.'
}

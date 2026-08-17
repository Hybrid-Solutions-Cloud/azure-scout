@{
    ResourceTypes=@('AZSC/Okta/AdminRoleSummary')
    ResourceTypeMatching='Grouped';AdditionalFilter=$null;FilterPreamble='';RowLoopVariable='1'
    Preamble='$data=Get-AZSCSafeProperty -InputObject $1 -Path ''properties''';AdditionalRowLoops=@();TagLoop=$null
    Fields=@(
        @{Name='ID';Expression='Get-AZSCSafeProperty -InputObject $1 -Path ''id'''}
        @{Name='Role Type';Expression='Get-AZSCSafeProperty -InputObject $data -Path ''RoleType'''}
        @{Name='Assignment Count';Expression='Get-AZSCSafeProperty -InputObject $data -Path ''AssignmentCount'''}
    )
    Export=@{WorksheetName='Okta Admin Summary';TableNamePrefix='OktaAdminSummary_';Columns=@('Role Type','Assignment Count');TagColumns=@();TagColumnsBefore=$null;NumberFormat='0';ConditionalText=@()}
    SourceCollector='src/collect/Get-ScoutOktaEvidence.ps1'
    ManualConversionReason='Hand-authored for AB#7441 against the optional Okta evidence adapter; SourceCollector is provenance, not a legacy Standard-contract collector. Focused collection and renderer tests are the behavioural evidence.'
}

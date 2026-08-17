@{
    ResourceTypes=@('AZSC/Okta/Applications','AZSC/Okta/MicrosoftAppGroupAssignments','AZSC/Okta/MicrosoftAppUserAssignments','AZSC/Okta/IdentityProviders')
    ResourceTypeMatching='Grouped';AdditionalFilter=$null;FilterPreamble='';RowLoopVariable='1'
    Preamble='$raw=Get-AZSCSafeProperty -InputObject $1 -Path ''properties.Raw''';AdditionalRowLoops=@();TagLoop=$null
    Fields=@(
        @{Name='ID';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''id'''}
        @{Name='Evidence Type';Expression='Get-AZSCSafeProperty -InputObject $1 -Path ''type'''}
        @{Name='Name';Expression='& { $label=Get-AZSCSafeProperty -InputObject $raw -Path ''label'';if($label){$label}else{Get-AZSCSafeProperty -InputObject $raw -Path ''name''} }'}
        @{Name='Status';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''status'''}
        @{Name='Sign-On Mode';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''signOnMode'''}
        @{Name='Provisioning Mode';Expression='Get-AZSCSafeProperty -InputObject $raw -Path ''settings.app.emOptInStatus'''}
        @{Name='Parent App ID';Expression='Get-AZSCSafeProperty -InputObject $1 -Path ''PARENTID'''}
    )
    Export=@{WorksheetName='Okta Federation';TableNamePrefix='OktaFederation_';Columns=@('Evidence Type','Name','Status','Sign-On Mode','Provisioning Mode','Parent App ID');TagColumns=@();TagColumnsBefore=$null;NumberFormat='0';ConditionalText=@()}
    SourceCollector='src/collect/Get-ScoutOktaEvidence.ps1'
    ManualConversionReason='Hand-authored for AB#7441 against the optional Okta evidence adapter; SourceCollector is provenance, not a legacy Standard-contract collector. Focused collection and renderer tests are the behavioural evidence.'
}

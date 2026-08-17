@{
    ResourceTypes=@('AZSC/Okta/FactorEnrollmentSummary')
    ResourceTypeMatching='Grouped';AdditionalFilter=$null;FilterPreamble='';RowLoopVariable='1'
    Preamble='$data=Get-AZSCSafeProperty -InputObject $1 -Path ''properties''';AdditionalRowLoops=@();TagLoop=$null
    Fields=@(
        @{Name='ID';Expression='Get-AZSCSafeProperty -InputObject $1 -Path ''id'''}
        @{Name='Factor Type';Expression='Get-AZSCSafeProperty -InputObject $data -Path ''FactorType'''}
        @{Name='Enrollment Count';Expression='Get-AZSCSafeProperty -InputObject $data -Path ''EnrollmentCount'''}
        @{Name='Active User Count';Expression='Get-AZSCSafeProperty -InputObject $data -Path ''ActiveUserCount'''}
        @{Name='Active Users Without Any Factor';Expression='Get-AZSCSafeProperty -InputObject $data -Path ''ActiveUsersWithoutFactorCount'''}
        @{Name='Weak Factor';Expression='Get-AZSCSafeProperty -InputObject $data -Path ''WeakFactor'''}
    )
    Export=@{WorksheetName='Okta MFA Summary';TableNamePrefix='OktaMfaSummary_';Columns=@('Factor Type','Enrollment Count','Active User Count','Active Users Without Any Factor','Weak Factor');TagColumns=@();TagColumnsBefore=$null;NumberFormat='0';ConditionalText=@()}
    SourceCollector='src/collect/Get-ScoutOktaEvidence.ps1'
    ManualConversionReason='Hand-authored for AB#7441 against the optional Okta evidence adapter; SourceCollector is provenance, not a legacy Standard-contract collector. Focused collection and renderer tests are the behavioural evidence.'
}

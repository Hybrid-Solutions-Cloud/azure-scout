@{
    ResourceTypes=@('AZSC/Okta/ApplicationUsageSummary','AZSC/Okta/Directories','AZSC/Okta/DirectoryAgents','AZSC/Okta/DefaultUserSchema')
    ResourceTypeMatching='Grouped';AdditionalFilter=$null;FilterPreamble='';RowLoopVariable='1'
    Preamble='$data=Get-AZSCSafeProperty -InputObject $1 -Path ''properties''; $raw=Get-AZSCSafeProperty -InputObject $data -Path ''Raw''';AdditionalRowLoops=@();TagLoop=$null
    Fields=@(
        @{Name='ID';Expression='Get-AZSCSafeProperty -InputObject $1 -Path ''id'''}
        @{Name='Evidence Type';Expression='Get-AZSCSafeProperty -InputObject $1 -Path ''type'''}
        @{Name='Name';Expression='& { $app=Get-AZSCSafeProperty -InputObject $data -Path ''ApplicationName'';$rawName=Get-AZSCSafeProperty -InputObject $raw -Path ''name'';if($app){$app}elseif($rawName){$rawName}else{Get-AZSCSafeProperty -InputObject $1 -Path ''name''} }'}
        @{Name='Application ID';Expression='Get-AZSCSafeProperty -InputObject $data -Path ''ApplicationId'''}
        @{Name='Sign-ons (30 days)';Expression='Get-AZSCSafeProperty -InputObject $data -Path ''SignOnCount30Days'''}
        @{Name='Parent Directory ID';Expression='Get-AZSCSafeProperty -InputObject $1 -Path ''PARENTID'''}
        @{Name='Configuration';Expression='if ($raw) {$raw | ConvertTo-Json -Depth 20 -Compress} else {$null}'}
    )
    Export=@{WorksheetName='Okta Apps and Directories';TableNamePrefix='OktaAppsDirectories_';Columns=@('Evidence Type','Name','Application ID','Sign-ons (30 days)','Parent Directory ID','Configuration');TagColumns=@();TagColumnsBefore=$null;NumberFormat='0';ConditionalText=@()}
    SourceCollector='src/collect/Get-ScoutOktaEvidence.ps1'
    ManualConversionReason='Hand-authored for AB#7441 against the optional Okta evidence adapter; SourceCollector is provenance, not a legacy Standard-contract collector. Focused collection and renderer tests are the behavioural evidence.'
}

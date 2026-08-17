@{
    ResourceTypes = @('entra/mfaregistrationsummary')
    SourceDependencies = @('entra/users','entra/authenticationmethodregistrations')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    Preamble = '$ResUCount = 1; $data = $1.properties'
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = '$1.id' }
        @{ Name = 'Enabled Users'; Expression = '$data.enabledUserCount' }
        @{ Name = 'Enabled MFA Registered'; Expression = '$data.enabledMfaRegisteredCount' }
        @{ Name = 'Enabled MFA Percent'; Expression = '$data.enabledMfaRegisteredPercent' }
        @{ Name = 'Admins'; Expression = '$data.adminCount' }
        @{ Name = 'Admins MFA Registered'; Expression = '$data.adminMfaRegisteredCount' }
        @{ Name = 'Admin MFA Percent'; Expression = '$data.adminMfaRegisteredPercent' }
        @{ Name = 'Phishing Resistant Registered'; Expression = '$data.phishingResistantRegisteredCount' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'MFA Summary'
        TableNamePrefix = 'MFASummary_'
        Columns = @('Enabled Users','Enabled MFA Registered','Enabled MFA Percent','Admins','Admins MFA Registered','Admin MFA Percent','Phishing Resistant Registered','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}

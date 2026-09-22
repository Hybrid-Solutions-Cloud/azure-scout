@{
    ResourceTypes = @('entra/legacyauthsummary')
    SourceDependencies = @('entra/signins')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    Preamble = '$ResUCount = 1; $data = $1.properties'
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = '$1.id' }
        @{ Name = 'Masked User'; Expression = '$data.maskedUserPrincipalName' }
        @{ Name = 'Successful Sign-ins'; Expression = '$data.successfulSignIns' }
        @{ Name = 'Client Apps'; Expression = '@($data.clientApps) -join '', ''' }
        @{ Name = 'Last Sign-in'; Expression = '$data.lastSignInDateTime' }
        @{ Name = 'Window Days'; Expression = '$data.windowDays' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Legacy Authentication'
        TableNamePrefix = 'LegacyAuth_'
        Columns = @('Masked User','Successful Sign-ins','Client Apps','Last Sign-in','Window Days','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}

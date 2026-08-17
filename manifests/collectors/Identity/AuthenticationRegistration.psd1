@{
    ResourceTypes = @('entra/authenticationmethodregistrations')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    Preamble = '$ResUCount = 1; $data = $1.properties'
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = '$1.id' }
        @{ Name = 'User Principal Name'; Expression = '$data.userPrincipalName' }
        @{ Name = 'Is Admin'; Expression = '$data.isAdmin' }
        @{ Name = 'MFA Registered'; Expression = '$data.isMfaRegistered' }
        @{ Name = 'MFA Capable'; Expression = '$data.isMfaCapable' }
        @{ Name = 'Passwordless Capable'; Expression = '$data.isPasswordlessCapable' }
        @{ Name = 'Methods Registered'; Expression = '@($data.methodsRegistered) -join '', ''' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'MFA Registration'
        TableNamePrefix = 'MFARegistration_'
        Columns = @('User Principal Name','Is Admin','MFA Registered','MFA Capable','Passwordless Capable','Methods Registered','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}

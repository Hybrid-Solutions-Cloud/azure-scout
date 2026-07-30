@{
    IncludeDefaultRules = $true
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseBOMForUnicodeEncodedFile'
    )
}

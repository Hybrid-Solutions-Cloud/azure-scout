@{
    ResourceTypes = @('entra/conditionalaccessreportonlyimpact')
    SourceDependencies = @('entra/conditionalaccesspolicies','entra/signins')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    Preamble = '$ResUCount = 1; $data = $1.properties'
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = '$1.id' }
        @{ Name = 'Policy'; Expression = '$data.displayName' }
        @{ Name = 'Would Fail'; Expression = '$data.reportOnlyFailure' }
        @{ Name = 'Would Succeed'; Expression = '$data.reportOnlySuccess' }
        @{ Name = 'Would Interrupt'; Expression = '$data.reportOnlyInterrupted' }
        @{ Name = 'Other Result'; Expression = '$data.otherResult' }
        @{ Name = 'Observed Sign-ins'; Expression = '$data.observedSignIns' }
        @{ Name = 'Window Days'; Expression = '$data.windowDays' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'CA Report-Only Impact'
        TableNamePrefix = 'CAImpact_'
        Columns = @('Policy','Would Fail','Would Succeed','Would Interrupt','Other Result','Observed Sign-ins','Window Days','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}

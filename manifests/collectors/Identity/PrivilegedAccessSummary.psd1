@{
    ResourceTypes = @('entra/privilegedassignmentsummary')
    SourceDependencies = @('entra/roleassignmentschedules','entra/roleeligibilityschedules')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    Preamble = '$ResUCount = 1; $data = $1.properties'
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = '$1.id' }
        @{ Name = 'Role'; Expression = '$data.roleName' }
        @{ Name = 'Permanent'; Expression = '$data.permanentCount' }
        @{ Name = 'Eligible'; Expression = '$data.eligibleCount' }
        @{ Name = 'Active Time-Bound'; Expression = '$data.activeTimeBoundCount' }
        @{ Name = 'Stale Permanent 90 Days'; Expression = '$data.stalePermanent90DaysCount' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Privileged Summary'
        TableNamePrefix = 'PrivilegedSummary_'
        Columns = @('Role','Permanent','Eligible','Active Time-Bound','Stale Permanent 90 Days','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}

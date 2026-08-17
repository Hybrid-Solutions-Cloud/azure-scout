@{
    ResourceTypes = @('entra/privilegedassignments')
    SourceDependencies = @('entra/roleassignmentschedules','entra/roleeligibilityschedules','entra/users','entra/groups','entra/serviceprincipals','entra/signins')
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
        @{ Name = 'Principal'; Expression = '$data.principalName' }
        @{ Name = 'Principal Type'; Expression = '$data.principalType' }
        @{ Name = 'Assignment Type'; Expression = '$data.assignmentType' }
        @{ Name = 'Membership'; Expression = '$data.membership' }
        @{ Name = 'Start'; Expression = '$data.startDateTime' }
        @{ Name = 'End'; Expression = '$data.endDateTime' }
        @{ Name = 'Account Enabled'; Expression = '$data.accountEnabled' }
        @{ Name = 'Last Sign-in'; Expression = '$data.lastSignInDateTime' }
        @{ Name = 'Stale Permanent 90 Days'; Expression = '$data.stalePermanent90Days' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Privileged Access'
        TableNamePrefix = 'PrivilegedAccess_'
        Columns = @('Role','Principal','Principal Type','Assignment Type','Membership','Start','End','Account Enabled','Last Sign-in','Stale Permanent 90 Days','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}

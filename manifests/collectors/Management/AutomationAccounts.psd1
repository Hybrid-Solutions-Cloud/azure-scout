#
# Declarative equivalent of Management/AutomationAccounts.ps1.
#
# The legacy collector's two branches differ only by whether a matching runbook exists.
# A conditional loop source retains that topology without teaching the shared interpreter any
# collector-specific behavior: no match supplies one null iteration, exactly as the legacy else
# branch did.  The legacy `$Tags` expression reads `$1` before the runbook loop binds it, so its
# observable value is always the `'0'` sentinel; retain that historical output until the collector
# is separately corrected with a migration note.
#
@{
    ResourceTypes = @('microsoft.automation/automationaccounts')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '0'
    ManualConversionReason = 'The imperative branches have different loop depth. A conditional loop source preserves their row cardinality; tests/ConditionalTopologyCollector.Tests.ps1 proves both branches against the imperative collector.'

    SetupPreamble = @'
$runbook = $Resources | Where-Object {$_.TYPE -eq 'microsoft.automation/automationaccounts/runbooks'}
'@
    SetupVariables = @('runbook')

    Preamble = @'
$ResUCount = 1
$sub1 = $SUB | Where-Object { $_.Id -eq $0.subscriptionId }
$rbs = $runbook | Where-Object { $_.id.split('/')[8] -eq $0.name }
$Tags = '0'
$data0 = $0.properties
$timecreated = $data0.creationTime
$timecreated = [datetime]$timecreated
$timecreated = $timecreated.ToString("yyyy-MM-dd HH:mm")
# In the source this executes before the `$1` runbook loop exists, so the legacy non-StrictMode
# value is always $null and no retirement can match.
$Retired = $null
if ($Retired) {
    $RetiredFeature = foreach ($Retire in $Retired) {
        $RetiredServiceID = $Unsupported | Where-Object {$_.Id -eq $Retired.ServiceID}
        [pscustomobject]@{
            'RetiredFeature' = $RetiredServiceID.RetiringFeature
            'RetiredDate' = $RetiredServiceID.RetirementDate
        }
    }
    $RetiringFeature = if (@($RetiredFeature.RetiredFeature).count -gt 1) { $RetiredFeature.RetiredFeature | ForEach-Object { $_ + ' ,' } } else { $RetiredFeature.RetiredFeature }
    $RetiringFeature = [string]$RetiringFeature
    $RetiringFeature = if ($RetiringFeature -like '* ,*') { $RetiringFeature -replace ".$" } else { $RetiringFeature }
    $RetiringDate = if (@($RetiredFeature.RetiredDate).count -gt 1) { $RetiredFeature.RetiredDate | ForEach-Object { $_ + ' ,' } } else { $RetiredFeature.RetiredDate }
    $RetiringDate = [string]$RetiringDate
    $RetiringDate = if ($RetiringDate -like '* ,*') { $RetiringDate -replace ".$" } else { $RetiringDate }
} else {
    $RetiringFeature = $null
    $RetiringDate = $null
}
'@

    AdditionalRowLoops = @(
        @{
            Variable = '1'
            Source = '$rbs'
            EmitNullWhenEmpty = $true
            Preamble = '$data = if ($null -ne $1) { $1.PROPERTIES } else { $null }'
        }
    )
    TagLoop = @{ Variable = 'Tag'; Source = '$Tags'; Preamble = '' }

    Fields = @(
        @{ Name = 'ID'; Expression = 'if ($null -ne $1) { $1.id } else { $null }' }
        @{ Name = 'Subscription'; Expression = '$sub1.Name' }
        @{ Name = 'Resource Group'; Expression = '$0.RESOURCEGROUP' }
        @{ Name = 'Automation Account Name'; Expression = '$0.NAME' }
        @{ Name = 'Retiring Feature'; Expression = '$RetiringFeature' }
        @{ Name = 'Retiring Date'; Expression = '$RetiringDate' }
        @{ Name = 'Automation Account State'; Expression = '$0.properties.State' }
        @{ Name = 'Automation Account SKU'; Expression = '$0.properties.sku.name' }
        @{ Name = 'Automation Account Created Time'; Expression = '$timecreated' }
        @{ Name = 'Location'; Expression = '$0.LOCATION' }
        @{ Name = 'Runbook Name'; Expression = 'if ($null -ne $1) { $1.Name } else { $null }' }
        @{ Name = 'Last Modified Time'; Expression = 'if ($null -ne $data) { ([datetime]$data.lastModifiedTime).tostring(''MM/dd/yyyy hh:mm'') } else { $null }' }
        @{ Name = 'Runbook State'; Expression = 'if ($null -ne $data) { $data.state } else { $null }' }
        @{ Name = 'Runbook Type'; Expression = 'if ($null -ne $data) { $data.runbookType } else { $null }' }
        @{ Name = 'Runbook Description'; Expression = 'if ($null -ne $data) { $data.description } else { $null }' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
        @{ Name = 'Tag Name'; Expression = 'if ($Tag -is [string]) { [string]$null } else { [string]$Tag.Name }' }
        @{ Name = 'Tag Value'; Expression = 'if ($Tag -is [string]) { [string]$null } else { [string]$Tag.Value }' }
    )

    Export = @{
        WorksheetName = 'Runbooks'
        TableNamePrefix = 'AutAccTable_'
        Columns = @('Subscription','Resource Group','Automation Account Name','Retiring Feature','Retiring Date','Automation Account State','Automation Account SKU','Automation Account Created Time','Location','Runbook Name','Last Modified Time','Runbook State','Runbook Type','Runbook Description','Resource U')
        TagColumns = @('Tag Name','Tag Value')
        TagColumnsBefore = 'Resource U'
        NumberFormat = '0'
        ConditionalText = @('New-ConditionalText -Range D2:D100 -ConditionalType ContainsText')
    }
    SourceCollector = 'Modules/Public/InventoryModules/Management/AutomationAccounts.ps1'
}

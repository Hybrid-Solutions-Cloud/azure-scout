#Requires -Version 7.0
Set-StrictMode -Version Latest

# Hermetic command surface for Pester suites that mock Search-AzGraph. Importing the real
# Az.ResourceGraph module can refresh the operator's cached Az context and open an ARM connection
# before a test runs. The production query parameters used by Scout are declared explicitly so
# Pester parameter filters retain the real command contract without loading the Azure module.
function Search-AzGraph {
    [CmdletBinding()]
    param(
        [string]$Query,
        [int]$First,
        [int]$Skip,
        [string]$SkipToken,
        [string]$ManagementGroup,
        [string[]]$Subscription,
        [switch]$UseTenantScope
    )
    return @()
}


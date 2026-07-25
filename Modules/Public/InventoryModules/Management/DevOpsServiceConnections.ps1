<#
.Synopsis
Inventory for Azure DevOps Service Connections

.DESCRIPTION
This script consolidates information for all devops/serviceconnections resources, and
cross-references Azure Resource Manager connections against the subscriptions in scope so
you can see which of your subscriptions are reachable from a pipeline.

Excel Sheet Name: ADO Service Connections

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Management/DevOpsServiceConnections.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 1.0.0
Work item: AB#327
Authors: AzureScout Contributors
#>

<######## Default Parameters. Don't modify this ########>

param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task, $File, $SmaResources, $TableStyle, $Unsupported)

If ($Task -eq 'Processing')
{
    $devOpsEndpoints = $Resources | Where-Object { $_.TYPE -eq 'devops/serviceconnections' }

    if ($devOpsEndpoints)
    {
        # Subscription IDs in scope for this scan. A service connection pointing at one of
        # these is a pipeline with a path into the estate being inventoried; one pointing
        # elsewhere is a connection into a subscription this report does not cover.
        $inScopeSubs = @{}
        foreach ($s in $Sub) {
            if ($s -and $s.PSObject.Properties.Name -contains 'Id' -and $s.Id) {
                $inScopeSubs[[string]$s.Id] = if ($s.PSObject.Properties.Name -contains 'Name') { $s.Name } else { '' }
            }
        }

        $tmp = foreach ($1 in $devOpsEndpoints) {
            $ResUCount = 1
            $data = $1.properties

            $endpointData = if ($data.PSObject.Properties.Name -contains 'data') { $data.data } else { $null }

            $subId = if ($endpointData -and $endpointData.PSObject.Properties.Name -contains 'subscriptionId') {
                $endpointData.subscriptionId
            } else { $null }

            $subName = if ($endpointData -and $endpointData.PSObject.Properties.Name -contains 'subscriptionName') {
                $endpointData.subscriptionName
            } else { $null }

            $authScheme = if ($data.PSObject.Properties.Name -contains 'authorization' -and $data.authorization) {
                $data.authorization.scheme
            } else { $null }

            $servicePrincipalId = if ($data.PSObject.Properties.Name -contains 'authorization' -and $data.authorization -and
                                      $data.authorization.PSObject.Properties.Name -contains 'parameters' -and $data.authorization.parameters -and
                                      $data.authorization.parameters.PSObject.Properties.Name -contains 'serviceprincipalid') {
                $data.authorization.parameters.serviceprincipalid
            } else { $null }

            $inScope = if ($subId -and $inScopeSubs.ContainsKey([string]$subId)) { 'Yes' } else { 'No' }

            # Workload identity federation is the credential-free scheme; anything else on
            # an ARM connection is a secret or certificate that has to be rotated.
            $credentialFree = if ($authScheme -eq 'WorkloadIdentityFederation') { 'Yes' } else { 'No' }

            $isShared = if ($data.PSObject.Properties.Name -contains 'isShared') { [string]$data.isShared } else { $null }
            $isReady  = if ($data.PSObject.Properties.Name -contains 'isReady')  { [string]$data.isReady }  else { $null }

            $obj = @{
                'ID'                       = $1.id;
                'Organization'             = $1.organization;
                'Project'                  = $data.projectName;
                'Connection Name'          = $1.name;
                'Connection Type'          = $data.type;
                'Authorization Scheme'     = $authScheme;
                'Credential Free'          = $credentialFree;
                'Service Principal ID'     = $servicePrincipalId;
                'Target Subscription ID'   = $subId;
                'Target Subscription Name' = $subName;
                'Subscription In Scope'    = $inScope;
                'Shared'                   = $isShared;
                'Ready'                    = $isReady;
                'Resource U'               = $ResUCount
            }
            $obj
        }
        $tmp
    }
}

<######## Resource Excel Reporting Begins Here ########>

Else
{
    if ($SmaResources)
    {
        $TableName = ('ADOServiceConnectionsTable_' + (($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'

        # Column letters follow the $Exc ordering below: F = Credential Free,
        # J = Subscription In Scope.
        $condtxt = @()
        # A connection into a subscription this scan covers is the one worth reviewing.
        $condtxt += New-ConditionalText -Text 'Yes' -Range J:J -ConditionalType ContainsText -BackgroundColor Yellow
        # Secret-based ARM connections carry rotation risk that federated ones do not.
        $condtxt += New-ConditionalText -Text 'No'  -Range F:F -ConditionalType ContainsText -BackgroundColor Orange

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Organization')
        $Exc.Add('Project')
        $Exc.Add('Connection Name')
        $Exc.Add('Connection Type')
        $Exc.Add('Authorization Scheme')
        $Exc.Add('Credential Free')
        $Exc.Add('Service Principal ID')
        $Exc.Add('Target Subscription ID')
        $Exc.Add('Target Subscription Name')
        $Exc.Add('Subscription In Scope')
        $Exc.Add('Shared')
        $Exc.Add('Ready')
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources |
        ForEach-Object { $_ } | Select-Object $Exc |
        Export-Excel -Path $File -WorksheetName 'ADO Service Connections' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -ConditionalText $condtxt -Style $Style
    }
}

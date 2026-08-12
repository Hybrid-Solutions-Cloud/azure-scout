<#
.Synopsis
Inventory for Azure DevOps Agent Pools

.DESCRIPTION
This script consolidates information for all devops/agentpools resources, separating
Microsoft-hosted pools from self-hosted ones so the infrastructure you are responsible
for is distinguishable at a glance.

Excel Sheet Name: ADO Agent Pools

.Link
https://github.com/Hybrid-Solutions-Cloud/azure-scout/Modules/Public/InventoryModules/Management/DevOpsAgentPools.ps1

.COMPONENT
This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
Version: 1.0.0
Work item: AB#327
Authors: AzureScout Contributors
#>

<######## Default Parameters. Don't modify this ########>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SCPath', Justification = "Shared collector call-signature (see 'Default Parameters' comment) -- the orchestration loop invokes every InventoryModules script with the same fixed positional parameter list; this module simply does not need this one.")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Sub', Justification = "Shared collector call-signature (see 'Default Parameters' comment) -- the orchestration loop invokes every InventoryModules script with the same fixed positional parameter list; this module simply does not need this one.")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Intag', Justification = "Shared collector call-signature (see 'Default Parameters' comment) -- the orchestration loop invokes every InventoryModules script with the same fixed positional parameter list; this module simply does not need this one.")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Retirements', Justification = "Shared collector call-signature (see 'Default Parameters' comment) -- the orchestration loop invokes every InventoryModules script with the same fixed positional parameter list; this module simply does not need this one.")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Unsupported', Justification = "Shared collector call-signature (see 'Default Parameters' comment) -- the orchestration loop invokes every InventoryModules script with the same fixed positional parameter list; this module simply does not need this one.")]
param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task, $File, $SmaResources, $TableStyle, $Unsupported)

If ($Task -eq 'Processing')
{
    $devOpsPools = $Resources | Where-Object { $_.TYPE -eq 'devops/agentpools' }

    if ($devOpsPools)
    {
        $tmp = foreach ($1 in $devOpsPools) {
            $ResUCount = 1
            $data = $1.properties

            # isHosted true means Microsoft runs the agents; false means the customer does,
            # which is the set that carries patching and capacity obligations.
            $hosting = if ($data.PSObject.Properties.Name -contains 'isHosted' -and $data.isHosted) {
                'Microsoft-hosted'
            } else { 'Self-hosted' }

            $createdOn = if ($data.PSObject.Properties.Name -contains 'createdOn' -and $data.createdOn) {
                ([datetime]$data.createdOn).ToString('MM/dd/yyyy HH:mm')
            } else { $null }

            $owner = if ($data.PSObject.Properties.Name -contains 'owner' -and $data.owner) {
                $data.owner.displayName
            } else { $null }

            $isLegacy = if ($data.PSObject.Properties.Name -contains 'isLegacy') { [string]$data.isLegacy } else { $null }
            $autoProvision = if ($data.PSObject.Properties.Name -contains 'autoProvision') { [string]$data.autoProvision } else { $null }

            $obj = @{
                'ID'             = $1.id;
                'Organization'   = $1.organization;
                'Pool Name'      = $1.name;
                'Pool ID'        = $data.id;
                'Hosting Model'  = $hosting;
                'Pool Type'      = $data.poolType;
                'Agent Size'     = $data.size;
                'Auto Provision' = $autoProvision;
                'Legacy'         = $isLegacy;
                'Created On'     = $createdOn;
                'Owner'          = $owner;
                'Resource U'     = $ResUCount
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
        $TableName = ('ADOAgentPoolsTable_' + (($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'

        # Column D is Hosting Model, following the $Exc ordering below.
        $condtxt = @()
        $condtxt += New-ConditionalText -Text 'Self-hosted' -Range D:D -ConditionalType ContainsText -BackgroundColor Yellow

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Organization')
        $Exc.Add('Pool Name')
        $Exc.Add('Pool ID')
        $Exc.Add('Hosting Model')
        $Exc.Add('Pool Type')
        $Exc.Add('Agent Size')
        $Exc.Add('Auto Provision')
        $Exc.Add('Legacy')
        $Exc.Add('Created On')
        $Exc.Add('Owner')
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources |
        ForEach-Object { $_ } | Select-Object $Exc |
        Export-Excel -Path $File -WorksheetName 'ADO Agent Pools' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -ConditionalText $condtxt -Style $Style
    }
}

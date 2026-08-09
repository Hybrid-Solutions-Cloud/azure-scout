<#
.Synopsis
Inventory for Azure DevOps Projects

.DESCRIPTION
This script consolidates information for all devops/projects resources.
Excel Sheet Name: ADO Projects

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Management/DevOpsProjects.ps1

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
    $devOpsProjects = $Resources | Where-Object { $_.TYPE -eq 'devops/projects' }

    if ($devOpsProjects)
    {
        $tmp = foreach ($1 in $devOpsProjects) {
            $ResUCount = 1
            $data = $1.properties

            $lastUpdate = if ($data.PSObject.Properties.Name -contains 'lastUpdateTime' -and $data.lastUpdateTime) {
                ([datetime]$data.lastUpdateTime).ToString('MM/dd/yyyy HH:mm')
            } else { $null }

            $obj = @{
                'ID'            = $1.id;
                'Organization'  = $1.organization;
                'Project Name'  = $1.name;
                'Description'   = $data.description;
                'State'         = $data.state;
                'Visibility'    = $data.visibility;
                'Revision'      = $data.revision;
                'Last Updated'  = $lastUpdate;
                'URL'           = $data.url;
                'Resource U'    = $ResUCount
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
        $TableName = ('ADOProjectsTable_' + (($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Organization')
        $Exc.Add('Project Name')
        $Exc.Add('Description')
        $Exc.Add('State')
        $Exc.Add('Visibility')
        $Exc.Add('Revision')
        $Exc.Add('Last Updated')
        $Exc.Add('URL')
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources |
        ForEach-Object { $_ } | Select-Object $Exc |
        Export-Excel -Path $File -WorksheetName 'ADO Projects' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -Style $Style
    }
}

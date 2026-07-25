<#
.Synopsis
Inventory for Azure DevOps Repositories

.DESCRIPTION
This script consolidates information for all devops/repositories resources.
Excel Sheet Name: ADO Repositories

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Management/DevOpsRepositories.ps1

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
    $devOpsRepos = $Resources | Where-Object { $_.TYPE -eq 'devops/repositories' }

    if ($devOpsRepos)
    {
        $tmp = foreach ($1 in $devOpsRepos) {
            $ResUCount = 1
            $data = $1.properties

            $defaultBranch = if ($data.PSObject.Properties.Name -contains 'defaultBranch' -and $data.defaultBranch) {
                # API returns the full ref; the short name is what a reader expects.
                $data.defaultBranch -replace '^refs/heads/', ''
            } else { $null }

            $sizeMb = if ($data.PSObject.Properties.Name -contains 'size' -and $data.size) {
                [math]::Round($data.size / 1MB, 2)
            } else { $null }

            $isDisabled = if ($data.PSObject.Properties.Name -contains 'isDisabled') { [string]$data.isDisabled } else { $null }

            $obj = @{
                'ID'              = $1.id;
                'Organization'    = $1.organization;
                'Project'         = $data.projectName;
                'Repository Name' = $1.name;
                'Default Branch'  = $defaultBranch;
                'Size (MB)'       = $sizeMb;
                'Disabled'        = $isDisabled;
                'Web URL'         = $data.webUrl;
                'Resource U'      = $ResUCount
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
        $TableName = ('ADORepositoriesTable_' + (($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Organization')
        $Exc.Add('Project')
        $Exc.Add('Repository Name')
        $Exc.Add('Default Branch')
        $Exc.Add('Size (MB)')
        $Exc.Add('Disabled')
        $Exc.Add('Web URL')
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources |
        ForEach-Object { $_ } | Select-Object $Exc |
        Export-Excel -Path $File -WorksheetName 'ADO Repositories' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -Style $Style
    }
}

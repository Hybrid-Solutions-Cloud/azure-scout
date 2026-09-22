<#
.Synopsis
Inventory for Azure DevOps Pipelines

.DESCRIPTION
This script consolidates information for all devops/pipelines resources.
Excel Sheet Name: ADO Pipelines

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Management/DevOpsPipelines.ps1

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
    $devOpsPipelines = $Resources | Where-Object { $_.TYPE -eq 'devops/pipelines' }

    if ($devOpsPipelines)
    {
        $tmp = foreach ($1 in $devOpsPipelines) {
            $ResUCount = 1
            $data = $1.properties

            # 'folder' is '\' at the root, which reads as noise in a report column.
            $folder = if ($data.PSObject.Properties.Name -contains 'folder' -and $data.folder -and $data.folder -ne '\') {
                $data.folder
            } else { '(root)' }

            $configType = if ($data.PSObject.Properties.Name -contains 'configuration' -and $data.configuration) {
                $data.configuration.type
            } else { $null }

            $yamlPath = if ($data.PSObject.Properties.Name -contains 'configuration' -and $data.configuration -and
                            $data.configuration.PSObject.Properties.Name -contains 'path') {
                $data.configuration.path
            } else { $null }

            $obj = @{
                'ID'                  = $1.id;
                'Organization'        = $1.organization;
                'Project'             = $data.projectName;
                'Pipeline Name'       = $1.name;
                'Pipeline ID'         = $data.id;
                'Folder'              = $folder;
                'Configuration Type'  = $configType;
                'YAML Path'           = $yamlPath;
                'Revision'            = $data.revision;
                'URL'                 = $data.url;
                'Resource U'          = $ResUCount
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
        $TableName = ('ADOPipelinesTable_' + (($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Organization')
        $Exc.Add('Project')
        $Exc.Add('Pipeline Name')
        $Exc.Add('Pipeline ID')
        $Exc.Add('Folder')
        $Exc.Add('Configuration Type')
        $Exc.Add('YAML Path')
        $Exc.Add('Revision')
        $Exc.Add('URL')
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources |
        ForEach-Object { $_ } | Select-Object $Exc |
        Export-Excel -Path $File -WorksheetName 'ADO Pipelines' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -Style $Style
    }
}

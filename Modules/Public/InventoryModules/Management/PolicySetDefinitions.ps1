<#
.Synopsis
Inventory for Azure Policy Initiative Definitions (Custom)

.DESCRIPTION
This script consolidates information for all custom Azure Policy Set Definitions (Initiatives).
Excel Sheet Name: Policy Initiatives

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Management/PolicySetDefinitions.ps1

.COMPONENT
This powershell Module is part of Azure Scout (AZSC)

.NOTES
Version: 1.0.0
First Release Date: February 24, 2026
Authors: AzureScout Contributors

#>

<######## Default Parameters. Don't modify this ########>

param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task ,$File, $SmaResources, $TableStyle, $Unsupported)

If ($Task -eq 'Processing')
{
    <######### Insert the resource extraction here ########>

        # Get all policy set definitions (custom only)
        $policySetDefs = Get-AzPolicySetDefinition -Custom -ErrorAction SilentlyContinue

    <######### Insert the resource Process here ########>

    if($policySetDefs)
        {
            $tmp = foreach ($policySet in $policySetDefs) {
                $ResUCount = 1

                # AB#5671, and the same two-part story as PolicyDefinitions.ps1: the StrictMode fault
                # is that `Properties` is an ABSENT member (an absent member throws, a $null one does
                # not), and the reason it is absent is that Az.Resources 7+ returns a FLATTENED
                # policy set definition -- no `Properties` sub-object, `Parameter` not `Parameters`,
                # and `Id` in place of `PolicySetDefinitionId`. That second part is a real,
                # pre-existing defect (this collector already emitted mostly-empty rows on any modern
                # Az, silently) and is deliberately NOT fixed here: re-pointing the reads at the
                # flattened shape would change every emitted value. Safe reads only.
                $props = Get-AZSCSafeProperty -InputObject $policySet -Path 'Properties'

                # Parse parameters
                $paramsBlock = Get-AZSCSafeProperty -InputObject $props -Path 'Parameters'
                $params = if ($paramsBlock) {
                    ($paramsBlock.PSObject.Properties | ForEach-Object { "$($_.Name) ($(Get-AZSCSafeProperty -InputObject $_.Value -Path 'type'))" }) -join '; '
                } else { 'None' }

                # Parse metadata
                $category = Get-AZSCSafeProperty -InputObject $props -Path 'Metadata.category'
                $version  = Get-AZSCSafeProperty -InputObject $props -Path 'Metadata.version'
                if (-not $category) { $category = 'Uncategorized' }
                if (-not $version)  { $version  = 'N/A' }

                # Count policy definitions in the initiative
                $policyDefinitionRefs = Get-AZSCSafeProperty -InputObject $props -Path 'PolicyDefinitions'
                $policyCount = if ($policyDefinitionRefs) { @($policyDefinitionRefs).Count } else { 0 }

                # Get list of policy definition references
                $policyRefs = if ($policyDefinitionRefs) {
                    (@($policyDefinitionRefs) | ForEach-Object {
                        $refId = (Get-AZSCSafeProperty -InputObject $_ -Path 'policyDefinitionId') -split '/' | Select-Object -Last 1
                        $refId
                    }) -join '; '
                } else { 'None' }

                # Parse policy groups
                $policyGroups = Get-AZSCSafeProperty -InputObject $props -Path 'PolicyDefinitionGroups'
                $groupCount = if ($policyGroups) { @($policyGroups).Count } else { 0 }

                $obj = @{
                    'ID'                        = (Get-AZSCSafeProperty -InputObject $policySet -Path 'PolicySetDefinitionId');
                    'Name'                      = $policySet.Name;
                    'Display Name'              = (Get-AZSCSafeProperty -InputObject $props -Path 'DisplayName');
                    'Description'               = (Get-AZSCSafeProperty -InputObject $props -Path 'Description');
                    'Policy Type'               = (Get-AZSCSafeProperty -InputObject $props -Path 'PolicyType');
                    'Category'                  = $category;
                    'Version'                   = $version;
                    'Policy Count'              = $policyCount;
                    'Policy Definition Groups'  = $groupCount;
                    'Policy References'         = $policyRefs;
                    'Parameters'                = $params;
                    'Management Group'          = (Get-AZSCSafeProperty -InputObject $policySet -Path 'ManagementGroupName');
                    'Subscription'              = (Get-AZSCSafeProperty -InputObject $policySet -Path 'SubscriptionId');
                    'Resource U'                = $ResUCount;
                }
                $obj
            }
            $tmp
        }
}

<######## Resource Excel Reporting Begins Here ########>

Else
{
    <######## $SmaResources.(RESOURCE FILE NAME) ##########>

    if($SmaResources)
    {

        $TableName = ('PolicyInitTable_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'
        $StyleExt = New-ExcelStyle -HorizontalAlignment Left -Range D:D,J:K -Width 60 -WrapText

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Name')
        $Exc.Add('Display Name')
        $Exc.Add('Description')
        $Exc.Add('Policy Type')
        $Exc.Add('Category')
        $Exc.Add('Version')
        $Exc.Add('Policy Count')
        $Exc.Add('Policy Definition Groups')
        $Exc.Add('Policy References')
        $Exc.Add('Parameters')
        $Exc.Add('Management Group')
        $Exc.Add('Subscription')
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources |
        ForEach-Object { $_ } | Select-Object $Exc |
        Export-Excel -Path $File -WorksheetName 'Policy Initiatives' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -Style $Style, $StyleExt

    }
}

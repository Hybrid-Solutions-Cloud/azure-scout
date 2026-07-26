<#
.Synopsis
Inventory for Azure Policy Definitions (Custom)

.DESCRIPTION
This script consolidates information for all custom Azure Policy definitions.
Excel Sheet Name: Policy Definitions

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Management/PolicyDefinitions.ps1

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

        # Get all policy definitions (custom only)
        $policyDefs = Get-AzPolicyDefinition -Custom -ErrorAction SilentlyContinue

    <######### Insert the resource Process here ########>

    if($policyDefs)
        {
            $tmp = foreach ($policy in $policyDefs) {
                $ResUCount = 1

                # AB#5671. Two separate things are going on here, and only the first is in scope.
                #
                # 1. StrictMode: `$policy.Properties` is an ABSENT member, not a $null one, so the
                #    read itself throws. Every read below is made safe.
                #
                # 2. A REAL, PRE-EXISTING DEFECT this exposed, deliberately NOT fixed here: as of
                #    Az.Resources 7 the object Get-AzPolicyDefinition returns is FLATTENED. There is
                #    no `Properties` sub-object at all (DisplayName, Mode, PolicyType, Metadata and
                #    PolicyRule sit directly on the object), `Parameters` was renamed `Parameter`,
                #    and `PolicyDefinitionId` / `ManagementGroupName` / `SubscriptionId` are gone --
                #    `Id` replaces the first. So on any modern Az this collector already emitted a
                #    row per policy with almost every column EMPTY, quietly, before StrictMode was
                #    ever involved. Reading through the safe accessor keeps that output byte for
                #    byte identical; re-pointing the reads at the flattened shape would change every
                #    emitted value, which is a behaviour change and belongs in its own work item.
                $props = Get-AZSCSafeProperty -InputObject $policy -Path 'Properties'

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

                # Parse policy rule effect
                $effect = Get-AZSCSafeProperty -InputObject $props -Path 'PolicyRule.then.effect'
                if (-not $effect) { $effect = 'Unknown' }

                $obj = @{
                    'ID'                    = (Get-AZSCSafeProperty -InputObject $policy -Path 'PolicyDefinitionId');
                    'Name'                  = $policy.Name;
                    'Display Name'          = (Get-AZSCSafeProperty -InputObject $props -Path 'DisplayName');
                    'Description'           = (Get-AZSCSafeProperty -InputObject $props -Path 'Description');
                    'Policy Type'           = (Get-AZSCSafeProperty -InputObject $props -Path 'PolicyType');
                    'Mode'                  = (Get-AZSCSafeProperty -InputObject $props -Path 'Mode');
                    'Category'              = $category;
                    'Version'               = $version;
                    'Effect'                = $effect;
                    'Parameters'            = $params;
                    'Management Group'      = (Get-AZSCSafeProperty -InputObject $policy -Path 'ManagementGroupName');
                    'Subscription'          = (Get-AZSCSafeProperty -InputObject $policy -Path 'SubscriptionId');
                    'Resource U'            = $ResUCount;
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

        $TableName = ('PolicyDefsTable_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'
        $StyleExt = New-ExcelStyle -HorizontalAlignment Left -Range D:D,J:J -Width 60 -WrapText

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Name')
        $Exc.Add('Display Name')
        $Exc.Add('Description')
        $Exc.Add('Policy Type')
        $Exc.Add('Mode')
        $Exc.Add('Category')
        $Exc.Add('Version')
        $Exc.Add('Effect')
        $Exc.Add('Parameters')
        $Exc.Add('Management Group')
        $Exc.Add('Subscription')
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources |
        ForEach-Object { $_ } | Select-Object $Exc |
        Export-Excel -Path $File -WorksheetName 'Policy Definitions' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -Style $Style, $StyleExt

    }
}

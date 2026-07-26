<#
.Synopsis
Inventory for Azure Container App Environment

.DESCRIPTION
This script consolidates information for all microsoft.app/managedenvironments resource provider in $Resources variable. 
Excel Sheet Name: Container App Env

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Container/ContainerAppEnv.ps1

.COMPONENT
This powershell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.0
First Release Date: 19th November, 2020
Authors: Claudio Merola and Renato Gregio 

#>

<######## Default Parameters. Don't modify this ########>

param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task ,$File, $SmaResources, $TableStyle, $Unsupported)

If ($Task -eq 'Processing')
{

    <######### Insert the resource extraction here ########>

        $CONTAINERENV = $Resources | Where-Object {$_.TYPE -eq 'microsoft.app/managedenvironments'}
        $CONTAINER = $Resources | Where-Object {$_.TYPE -eq 'microsoft.app/containerapps'}

    <######### Insert the resource Process here ########>

    if($CONTAINERENV)
        {
            $tmp = foreach ($1 in $CONTAINERENV) {
                $ResUCount = 1
                # An EMPTY $sub1 -- subscription outside the requested scope -- is not $null, and
                # `.Name` on it throws under StrictMode (AB#5671).
                $sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
                $SubscriptionName = if ($sub1) { @($sub1)[0].Name } else { '' }
                $data = $1.PROPERTIES
                $Retired = $Retirements | Where-Object { $_.id -eq $1.id }
                if ($Retired) 
                    {
                        $RetiredFeature = foreach ($Retire in $Retired)
                            {
                                $RetiredServiceID = $Unsupported | Where-Object {$_.Id -eq $Retired.ServiceID}
                                $tmp0 = [pscustomobject]@{
                                        'RetiredFeature'            = $RetiredServiceID.RetiringFeature
                                        'RetiredDate'               = $RetiredServiceID.RetirementDate 
                                    }
                                $tmp0
                            }
                        $RetiringFeature = if (@($RetiredFeature.RetiredFeature).count -gt 1) { $RetiredFeature.RetiredFeature | ForEach-Object { $_ + ' ,' } }else { $RetiredFeature.RetiredFeature}
                        $RetiringFeature = [string]$RetiringFeature
                        $RetiringFeature = if ($RetiringFeature -like '* ,*') { $RetiringFeature -replace ".$" }else { $RetiringFeature }

                        $RetiringDate = if (@($RetiredFeature.RetiredDate).count -gt 1) { $RetiredFeature.RetiredDate | ForEach-Object { $_ + ' ,' } }else { $RetiredFeature.RetiredDate}
                        $RetiringDate = [string]$RetiringDate
                        $RetiringDate = if ($RetiringDate -like '* ,*') { $RetiringDate -replace ".$" }else { $RetiringDate }
                    }
                else 
                    {
                        $RetiringFeature = $null
                        $RetiringDate = $null
                    }
                # An untagged resource's Resource Graph row OMITS `tags`; the historic '0' sentinel
                # existed only to run the loop once for that case, and `'0'.Name` throws under
                # StrictMode. An empty tag object does the same job and emits the identical row.
                $RowTags  = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
                $Tags = if(![string]::IsNullOrEmpty($TagProps)){$TagProps}else{[pscustomobject]@{ Name = $null; Value = $null }}
                $Apps = @($CONTAINER | Where-Object { (Get-AZSCSafeProperty -InputObject $_ -Path 'properties.environmentId') -eq $1.id }).count

                # `workloadProfiles` is absent entirely on a Consumption-only environment, and each
                # profile omits minimumCount/maximumCount unless the profile is a dedicated one.
                # NOT wrapped in @(). @($null) has ONE element, so wrapping would run this loop body
                # once for a Consumption-only environment (no workloadProfiles at all) and emit a row
                # with empty profile columns where the original emitted NO row -- `foreach` over a
                # bare $null iterates zero times, which is the behaviour being preserved.
                foreach ($2 in (Get-AZSCSafeProperty -InputObject $data -Path 'workloadProfiles')) {
                        foreach ($Tag in $Tags) {
                            $obj = @{
                                'ID'                        = $1.id;
                                'Subscription'              = $SubscriptionName;
                                'Resource Group'            = $1.RESOURCEGROUP;
                                'Name'                      = $1.NAME;
                                'Location'                  = $1.LOCATION;
                                'Retiring Feature'          = $RetiringFeature;
                                'Retiring Date'             = $RetiringDate;
                                'Public Access'             = (Get-AZSCSafeProperty -InputObject $data -Path 'publicNetworkAccess');
                                'Zone Redundant'            = (Get-AZSCSafeProperty -InputObject $data -Path 'zoneRedundant');
                                'Static IP'                 = (Get-AZSCSafeProperty -InputObject $data -Path 'staticIp');
                                'KEDA version'              = (Get-AZSCSafeProperty -InputObject $data -Path 'kedaconfiguration.Version');
                                'Dapr version'              = (Get-AZSCSafeProperty -InputObject $data -Path 'daprconfiguration.Version');
                                'Workload Profile'          = (Get-AZSCSafeProperty -InputObject $2 -Path 'name');
                                'Workload Profile Type'     = (Get-AZSCSafeProperty -InputObject $2 -Path 'workloadProfileType');
                                'Workload Profile Min'      = (Get-AZSCSafeProperty -InputObject $2 -Path 'minimumCount');
                                'Workload Profile Max'      = (Get-AZSCSafeProperty -InputObject $2 -Path 'maximumCount');
                                'Resource U'            = $ResUCount;
                                'Tag Name'                  = [string]$Tag.Name;
                                'Tag Value'                 = [string]$Tag.Value
                            }
                            $obj
                            if ($ResUCount -eq 1) { $ResUCount = 0 } 
                        }                    
                }
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
        $TableName = ('ContEnvTb_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'

        $condtxt = @()
        #Retirement
        $condtxt += New-ConditionalText -Range E2:E100 -ConditionalType ContainsText
        #Public Network Access
        $condtxt += New-ConditionalText Enabled -Range G:G -ConditionalType ContainsText
        #Zone Redundant
        $condtxt += New-ConditionalText False -Range H:H -ConditionalType ContainsText
        #Workload Type
        $condtxt += New-ConditionalText Consumption -Range M:M -ConditionalType ContainsText

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Name')
        $Exc.Add('Location')
        $Exc.Add('Retiring Feature')
        $Exc.Add('Retiring Date')
        $Exc.Add('Public Access')
        $Exc.Add('Zone Redundant')
        $Exc.Add('Static IP')
        $Exc.Add('KEDA version')
        $Exc.Add('Dapr version')
        $Exc.Add('Workload Profile')
        $Exc.Add('Workload Profile Type')
        $Exc.Add('Workload Profile Min')
        $Exc.Add('Workload Profile Max')
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value') 
            }
        $Exc.Add('Resource U')

        $SmaResources | 
        ForEach-Object { [PSCustomObject]$_ } | Select-Object $Exc | 
        Export-Excel -Path $File -WorksheetName 'Container App Env' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -ConditionalText $condtxt -TableStyle $tableStyle -Style $Style

    }
}
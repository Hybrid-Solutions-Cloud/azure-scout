<#
.Synopsis
Inventory for Azure Application Insights

.DESCRIPTION
This script consolidates information for all  resource provider in $Resources variable. 
Excel Sheet Name: AppInsights

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Monitoring/AppInsights.ps1

.COMPONENT
    This PowerShell Module is part of Azure Scout (AZSC).

.CATEGORY Monitor

.NOTES
Version: 3.6.0
First Release Date: 19th November, 2020
Authors: Claudio Merola and Renato Gregio 

#>

<######## Default Parameters. Don't modify this ########>

param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task ,$File, $SmaResources, $TableStyle, $Unsupported)

If ($Task -eq 'Processing') {

    <######### Insert the resource extraction here ########>

    $AppInsights = $Resources | Where-Object { $_.TYPE -eq 'microsoft.insights/components' }

    if($AppInsights)
        {
            $tmp = foreach ($1 in $AppInsights) {
                $ResUCount = 1
                # An EMPTY $sub1 is not $null -- the match is empty for any resource whose subscription
                # is outside the requested scope -- and reading .Name off an empty collection throws
                # under StrictMode (AB#5671). Resolved once here, as VirtualMachine.ps1 already does.
                $sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
                # The else arm is $null, NOT '': with StrictMode off $sub1.Name on an unmatched ($null)
                # $sub1 evaluated to $null, and the ~110 collectors that still read $sub1.Name directly
                # emit $null here. '' was a silent behaviour change -- the declarative equivalence proof
                # caught it on 11 collectors, and it would have been invisible on the rest (AB#5659).
                $SubscriptionName = if ($sub1) { @($sub1)[0].Name } else { $null }
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
                # The CreationDate field is absent (not present-and-null) on older API versions and some
                # resource kinds, so the raw read throws under StrictMode -- and [datetime] of a null
                # produced a bogus 0001-01-01 before that (AB#5671).
                $timecreated = Get-AZSCSafeProperty -InputObject $data -Path 'CreationDate'
                $timecreated = if ($timecreated) { ([datetime]$timecreated).ToString("yyyy-MM-dd HH:mm") } else { '' }
                $Sampling = if([string]::IsNullOrEmpty((Get-AZSCSafeProperty -InputObject $data -Path 'SamplingPercentage' -Enumerate))){'Disabled'}else{(Get-AZSCSafeProperty -InputObject $data -Path 'SamplingPercentage' -Enumerate)}
                # AB#5671: an untagged resource's Resource Graph row OMITS the tags property rather
                # than carrying an empty object, so the raw read throws under StrictMode -- and so
                # does psobject.properties on a $null. The historic '0' sentinel existed only to make
                # the tag loop below run ONCE for an untagged resource, but '0'.Name throws too; an
                # empty tag object runs it once AND emits the identical [string]-cast empty Name/Value.
                $RowTags  = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
                $Tags = if (![string]::IsNullOrEmpty($TagProps)) { $TagProps } else { [pscustomobject]@{ Name = $null; Value = $null } }
                    foreach ($Tag in $Tags) {
                        $obj = @{
                            'ID'                                = $1.id;
                            'Subscription'                      = $SubscriptionName;
                            'Resource Group'                    = $1.RESOURCEGROUP;
                            'Name'                              = $1.NAME;
                            'Location'                          = $1.LOCATION;
                            'Retiring Feature'                  = $RetiringFeature;
                            'Retiring Date'                     = $RetiringDate;
                            'Application Type'                  = (Get-AZSCSafeProperty -InputObject $data -Path 'Application_Type' -Enumerate);
                            # $RetDate and $RetFeature are never assigned anywhere in this file, so
                            # under StrictMode the READ is the error ("cannot be retrieved because it
                            # has not been set"). They are written as explicit nulls rather than
                            # deleted: both columns are part of this collector's emitted shape, and
                            # [string]$null is '' -- exactly what the unset variables contributed
                            # before. Note the separately-computed 'Retiring Date' / 'Retiring
                            # Feature' columns two lines up, which is what these two look like a
                            # half-finished duplicate of; wiring them up would change emitted values
                            # and so belongs in its own work item, not in a StrictMode fix (AB#5671).
                            'Retirement Date'                   = [string]$null;
                            'Retirement Feature'                = $null;
                            'Flow Type'                         = (Get-AZSCSafeProperty -InputObject $data -Path 'Flow_Type' -Enumerate);
                            'Version'                           = (Get-AZSCSafeProperty -InputObject $data -Path 'Ver' -Enumerate);
                            'Request Source'                    = (Get-AZSCSafeProperty -InputObject $data -Path 'Request_Source' -Enumerate);
                            'Data Sampling %'                   = [string]$Sampling;
                            'Retention In Days'                 = (Get-AZSCSafeProperty -InputObject $data -Path 'RetentionInDays' -Enumerate);
                            'Ingestion Mode'                    = (Get-AZSCSafeProperty -InputObject $data -Path 'IngestionMode' -Enumerate);
                            'Public Access For Ingestion'       = (Get-AZSCSafeProperty -InputObject $data -Path 'publicNetworkAccessForIngestion' -Enumerate);
                            'Public Access For Query'           = (Get-AZSCSafeProperty -InputObject $data -Path 'publicNetworkAccessForQuery' -Enumerate);
                            'Created Time'                      = $timecreated;     
                            'Resource U'                       = $ResUCount;                       
                            'Tag Name'                          = [string]$Tag.Name;
                            'Tag Value'                         = [string]$Tag.Value
                        }
                        $obj
                        if ($ResUCount -eq 1) { $ResUCount = 0 } 
                    }                
            }
            $tmp
        }
}
<######## Resource Excel Reporting Begins Here ########>

Else {
    <######## $SmaResources.(RESOURCE FILE NAME) ##########>

    if ($SmaResources) {

        $TableName = ('AppInsightsTable_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat 0

        $condtxt = @()
        $condtxt += New-ConditionalText Disabled -Range K:K
        $condtxt += New-ConditionalText enabled -Range N:N
        $condtxt += New-ConditionalText enabled -Range O:O
        #Retirement
        $condtxt += New-ConditionalText -Range E2:E100 -ConditionalType ContainsText
        
        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Name')
        $Exc.Add('Location')
        $Exc.Add('Retiring Feature')
        $Exc.Add('Retiring Date')
        $Exc.Add('Application Type')
        $Exc.Add('Flow Type')
        $Exc.Add('Version')
        $Exc.Add('Request Source')
        $Exc.Add('Data Sampling %')
        $Exc.Add('Retention In Days')
        $Exc.Add('Ingestion Mode')
        $Exc.Add('Public Access For Ingestion')
        $Exc.Add('Public Access For Query')
        $Exc.Add('Created Time')
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value') 
            }
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources | 
        ForEach-Object { $_ } | Select-Object $Exc | 
        Export-Excel -Path $File -WorksheetName 'AppInsights' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -Style $Style -ConditionalText $condtxt

    }
}
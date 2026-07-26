<#
.Synopsis
Inventory for Azure Container App instance

.DESCRIPTION
This script consolidates information for all microsoft.app/containerapps resource provider in $Resources variable. 
Excel Sheet Name: Container App

.Link
https://github.com/thisismydemo/azure-scout/Modules/Public/InventoryModules/Container/ContainerApp.ps1

.COMPONENT
This powershell Module is part of Azure Scout (AZSC)

.NOTES
Version: 3.6.7
First Release Date: 19th November, 2020
Authors: Claudio Merola and Renato Gregio 

#>

<######## Default Parameters. Don't modify this ########>

param($SCPath, $Sub, $Intag, $Resources, $Retirements, $Task ,$File, $SmaResources, $TableStyle, $Unsupported)

If ($Task -eq 'Processing')
{

    <######### Insert the resource extraction here ########>

        $CONTAINER = $Resources | Where-Object {$_.TYPE -eq 'microsoft.app/containerapps'}

    <######### Insert the resource Process here ########>

    if($CONTAINER)
        {
            $tmp = foreach ($1 in $CONTAINER) {
                $ResUCount = 1
                # An EMPTY $sub1 -- a resource whose subscription is outside the requested scope --
                # is not $null, and `.Name` on it throws under StrictMode.
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
                # AB#5671. `ingress` is ABSENT on an internal-only container app (which is the
                # whole point of an internal app), `dapr` and `secrets` are absent unless
                # configured, and every read hanging off `ingress` -- targetPort, external,
                # allowInsecure, transport -- therefore threw on the first such app.
                $RowTags  = Get-AZSCSafeProperty -InputObject $1 -Path 'tags'
                $TagProps = if ($null -ne $RowTags) { $RowTags.psobject.properties } else { $null }
                # The historic '0' sentinel only made this loop run once for an untagged resource;
                # `'0'.Name` throws under StrictMode, an empty tag object emits the identical row.
                $Tags = if(![string]::IsNullOrEmpty($TagProps)){$TagProps}else{[pscustomobject]@{ Name = $null; Value = $null }}
                $IngressConfig = Get-AZSCSafeProperty -InputObject $data -Path 'configuration.ingress'
                $DaprConfig    = Get-AZSCSafeProperty -InputObject $data -Path 'configuration.dapr'
                $SecretsConfig = Get-AZSCSafeProperty -InputObject $data -Path 'configuration.secrets'
                $ingress = if(![string]::IsNullOrEmpty($IngressConfig)){$true}else{$false}
                $dapr = if(![string]::IsNullOrEmpty($DaprConfig)){$true}else{$false}
                $secrets = if(![string]::IsNullOrEmpty($SecretsConfig)){@($SecretsConfig).count}else{0}
                $Env = Get-AZSCIdSegment -Id (Get-AZSCSafeProperty -InputObject $data -Path 'environmentId') -Index 8
                # Deliberately NOT wrapped in @(): @($null) has ONE element, so wrapping would run the
                # loop body once for an app with no template/containers and emit a row where the
                # original emitted none (`foreach` over a bare $null iterates zero times).
                foreach ($2 in (Get-AZSCSafeProperty -InputObject $data -Path 'template')) {
                    foreach ($3 in (Get-AZSCSafeProperty -InputObject $2 -Path 'containers')) {
                        foreach ($Tag in $Tags) {
                            $obj = @{
                                'ID'                        = $1.id;
                                'Subscription'              = $SubscriptionName;
                                'Resource Group'            = $1.RESOURCEGROUP;
                                'Name'                      = $1.NAME;
                                'Location'                  = $1.LOCATION;
                                'Retiring Feature'          = $RetiringFeature;
                                'Retiring Date'             = $RetiringDate;
                                'Running Status'            = (Get-AZSCSafeProperty -InputObject $data -Path 'runningStatus');
                                'Container App Environment' = $Env;
                                'Workload Profile'          = (Get-AZSCSafeProperty -InputObject $data -Path 'workloadProfileName');
                                'Ingress'                   = $ingress;
                                'Ingress Port'              = (Get-AZSCSafeProperty -InputObject $IngressConfig -Path 'targetPort');
                                'External Ingress'          = (Get-AZSCSafeProperty -InputObject $IngressConfig -Path 'external');
                                'Insecure Connections'      = (Get-AZSCSafeProperty -InputObject $IngressConfig -Path 'allowInsecure');
                                'Ingress Transport'         = (Get-AZSCSafeProperty -InputObject $IngressConfig -Path 'transport');
                                'Dapr'                      = $dapr;
                                'Secrets'                   = [string]$secrets;
                                'Container'                 = (Get-AZSCSafeProperty -InputObject $3 -Path 'name');
                                'CPU Cores'                 = (Get-AZSCSafeProperty -InputObject $3 -Path 'resources.cpu');
                                'Memory Size (Gi)'          = (Get-AZSCSafeProperty -InputObject $3 -Path 'resources.memory');
                                'Ephemeral Storage (Gi)'    = (Get-AZSCSafeProperty -InputObject $3 -Path 'resources.ephemeralStorage');
                                'Container Image'           = (Get-AZSCSafeProperty -InputObject $3 -Path 'image');
                                'Resource U'                = $ResUCount;
                                'Tag Name'                  = [string]$Tag.Name;
                                'Tag Value'                 = [string]$Tag.Value
                            }
                            $obj
                            if ($ResUCount -eq 1) { $ResUCount = 0 } 
                        }
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
        $TableName = ('ContsTb_'+(($SmaResources.'Resource U' | Measure-Object -Sum).Sum))
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0'

        $condtxt = @()
        #Retirement
        $condtxt += New-ConditionalText -Range E2:E100 -ConditionalType ContainsText
        #External Ingress
        $condtxt += New-ConditionalText true -Range L:L -ConditionalType ContainsText
        #Allow Insecure
        $condtxt += New-ConditionalText true -Range M:M -ConditionalType ContainsText

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Name')
        $Exc.Add('Location')
        $Exc.Add('Retiring Feature')
        $Exc.Add('Retiring Date')
        $Exc.Add('Running Status')
        $Exc.Add('Container App Environment')
        $Exc.Add('Workload Profile')
        $Exc.Add('Ingress')
        $Exc.Add('Ingress Port')
        $Exc.Add('External Ingress')
        $Exc.Add('Insecure Connections')
        $Exc.Add('Ingress Transport')
        $Exc.Add('Dapr')
        $Exc.Add('Secrets')
        $Exc.Add('Container')
        $Exc.Add('CPU Cores')
        $Exc.Add('Memory Size (Gi)')
        $Exc.Add('Ephemeral Storage (Gi)')
        $Exc.Add('Container Image')
        if($InTag)
            {
                $Exc.Add('Tag Name')
                $Exc.Add('Tag Value') 
            }
        $Exc.Add('Resource U')

        [PSCustomObject]$SmaResources | 
        ForEach-Object { $_ } | Select-Object $Exc | 
        Export-Excel -Path $File -WorksheetName 'Container Apps' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -ConditionalText $condtxt -TableStyle $tableStyle -Style $Style

    }
}
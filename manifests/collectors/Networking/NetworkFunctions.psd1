#
# AB#7091 (folds in AB#7071 -- zero collector anywhere for this type; Story AB#7059, Feature
# AB#7069, Epic AB#7099). Authored by hand in the same shape
# scripts/ConvertTo-ScoutCollectorDefinition.ps1 produces for the other ARM-backed Networking
# collectors (see NATGateway.psd1) -- there is no source .ps1 to convert from, this service
# never had one. Networking coverage-gap close-out: `microsoft.hybridnetwork/networkfunctions`
# is Azure Network Function Manager's deployed network-function instance -- a real gap, see
# docs/reference/service-coverage-gap.md.
#
@{
    ResourceTypes = @(
        'microsoft.hybridnetwork/networkfunctions'
    )

    ResourceTypeMatching = 'Grouped'

    AdditionalFilter = $null

    FilterPreamble = ''

    RowLoopVariable = '1'

    Preamble = @'
$ResUCount = 1
                $sub1 = $SUB | Where-Object { $_.Id -eq $1.subscriptionId }
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
                $Tags = if(![string]::IsNullOrEmpty($1.tags.psobject.properties)){$1.tags.psobject.properties}else{'0'}
'@

    AdditionalRowLoops = @()

    TagLoop = @{
        Variable = 'Tag'
        Source = '$Tags'
        Preamble = ''
    }

    Fields = @(
        @{
            Name = 'ID'
            Expression = '$1.id'
        }
        @{
            Name = 'Subscription'
            Expression = '$sub1.Name'
        }
        @{
            Name = 'Resource Group'
            Expression = '$1.RESOURCEGROUP'
        }
        @{
            Name = 'Name'
            Expression = '$1.NAME'
        }
        @{
            Name = 'Location'
            Expression = '$1.LOCATION'
        }
        @{
            Name = 'Retiring Feature'
            Expression = '$RetiringFeature'
        }
        @{
            Name = 'Retiring Date'
            Expression = '$RetiringDate'
        }
        @{
            Name = 'Provisioning State'
            Expression = '$data.provisioningState'
        }
        @{
            Name = 'Vendor Provisioning State'
            Expression = '$data.vendorProvisioningState'
        }
        @{
            Name = 'Service Key'
            Expression = '$data.serviceKey'
        }
        @{
            Name = 'Resource U'
            Expression = '$ResUCount'
        }
        @{
            Name = 'Tag Name'
            Expression = '[string]$Tag.Name'
        }
        @{
            Name = 'Tag Value'
            Expression = '[string]$Tag.Value'
        }
    )

    Export = @{
        WorksheetName = 'Network Functions'
        TableNamePrefix = 'NetworkFunctionsTable_'
        Columns = @(
            'Subscription'
            'Resource Group'
            'Name'
            'Location'
            'Retiring Feature'
            'Retiring Date'
            'Provisioning State'
            'Vendor Provisioning State'
            'Service Key'
            'Resource U'
        )
        TagColumns = @(
            'Tag Name'
            'Tag Value'
        )
        TagColumnsBefore = 'Resource U'
        NumberFormat = '0'
        ConditionalText = @(
            'New-ConditionalText -Range F2:F100 -ConditionalType ContainsText'
        )
    }

    SourceCollector = $null
}

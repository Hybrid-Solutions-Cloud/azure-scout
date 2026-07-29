function Get-AZSCCostInventory {
    Param($Subscriptions, $Days, $Granularity)

    #$Days = 60
    #$Granularity = 'Monthly'
    $Today = Get-Date
    $EndDate = Get-Date -Year $Today.Year -Month $Today.Month -Day $Today.Day -Hour 23 -Minute 59 -Second 59 -Millisecond 0

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Starting Cost Inventory Extraction')

    $Grouping = @()
    $GTemp = @{Name='ResourceType';Type='Dimension'}
    $Grouping += $GTemp
    $GTemp = @{Name='ResourceGroup';Type='Dimension'}
    $Grouping += $GTemp
    $GTemp = @{Name='ResourceLocation';Type='Dimension'}
    $Grouping += $GTemp
    $GTemp = @{Name='ServiceName';Type='Dimension'}
    $Grouping += $GTemp


    $Hash = @{name="PreTaxCost";function="Sum"}
    $MHash = @{totalCost=$Hash}

    if ($Days -ge 365)
        {
            $StartDate = Get-date -Year $EndDate.AddYears(-1).Year -Month 1 -Day 1 -Hour 0 -Minute 0 -Second 0 -Millisecond 1
            $EndDate = Get-Date -Year $StartDate.Year -Month 12 -Day 31 -Hour 23 -Minute 59 -Second 59 -Millisecond 0
        }
    else
        {
            #$StartDate = ($EndDate).AddDays(-$Days)
            $StartDate = (Get-Date -Day 1).AddMonths(-2)
        }  

    $Result = Foreach ($Subscription in $Subscriptions)
        {
            $SubId = $Subscription.id
            $SubName = $Subscription.name
            $Scope = ('/subscriptions/'+$SubId+'/')
            $Costs = @()
            try
                {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Extracting Cost Data for: ' + $SubName)
                    $Costs = Invoke-AzCostManagementQuery -Type ActualCost -Scope $Scope -Timeframe Custom -DatasetGranularity $Granularity -DatasetGrouping $Grouping -DatasetAggregation $MHash -TimePeriodFrom $StartDate -TimePeriodTo $EndDate -Debug:$false
                }
            catch
                {
                    # Cost data is optional enrichment -- it must never cost the caller their
                    # inventory. The previous `throw $_.Exception.Message` aborted the entire run
                    # whenever Cost Management was unavailable, and the `$Costs = @()` that
                    # followed it was unreachable, so the intended fallback never ran. A machine
                    # without Az.CostManagement installed lost the whole report to this. (AB#5636)
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - ' + 'Error Extracting Cost Data for Subscription: ' + $SubName)
                    $Costs = @()

                    if ($_.Exception.Message -like '*Invoke-AzCostManagementQuery*not recognized*')
                        {
                            Write-Warning ("[AzureScout] Cost data skipped: the Az.CostManagement module is not installed. " +
                                           "Install it with 'Install-Module Az.CostManagement -Scope CurrentUser' and rerun with -IncludeCosts.")
                        }
                    else
                        {
                            Write-Warning ("[AzureScout] Cost data skipped for subscription '" + $SubName + "': " + $_.Exception.Message)
                        }

                    Write-AZSCLog -Message ("Cost extraction failed for '" + $SubName + "': " + $_.Exception.Message) -Level 'WARN'
                }

            $obj = @{
                SubscriptionId = $SubId
                SubscriptionName = $SubName
                CostData = $Costs
            }
            Start-Sleep -Milliseconds 100
            $obj
        }

    return $Result

}
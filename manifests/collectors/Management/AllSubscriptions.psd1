#
# Hand-authored envelope conversion for AllSubscriptions (AB#5660).
# The legacy collector originally iterated $Sub and queried Resource Graph itself.  The collect
# phase now owns both concerns and supplies one AZSC/Management/SubscriptionEnrichment envelope
# per subscription, which is the declarable row source below.
#
@{
    ResourceTypes = @(
        'AZSC/Management/SubscriptionEnrichment'
    )

    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    ManualConversionReason = 'Rows are collect-phase subscription-enrichment envelopes rather than a native Azure resource type; the source collector uses the same typed envelope.'

    Preamble = @'
$ResUCount = 1
            $data = Get-AZSCSafeProperty -InputObject $1 -Path 'properties'
            $subscription = Get-AZSCSafeProperty -InputObject $data -Path 'Subscription'
            $subId = Get-AZSCSafeProperty -InputObject $subscription -Path 'Id'

            $resourceCount = Get-AZSCSafeProperty -InputObject $data -Path 'ResourceCount'
            $rgCount       = Get-AZSCSafeProperty -InputObject $data -Path 'ResourceGroupCount'
            $mgPath        = Get-AZSCSafeProperty -InputObject $data -Path 'ManagementGroupPath'

            $spendingLimit = Get-AZSCSafeProperty -InputObject $subscription -Path 'SubscriptionPolicies.SpendingLimit'
            $quotaId       = Get-AZSCSafeProperty -InputObject $subscription -Path 'SubscriptionPolicies.QuotaId'
            $authSource    = Get-AZSCSafeProperty -InputObject $subscription -Path 'AuthorizationSource'

            $spendingLimit = if ($null -ne $spendingLimit) { $spendingLimit } else { 'N/A' }
            $quotaId       = if ($null -ne $quotaId) { $quotaId } else { 'N/A' }
            $authSource    = if ($null -ne $authSource) { $authSource } else { 'N/A' }
            $mgPath        = if ($mgPath) { $mgPath } else { 'Unknown' }

            $subTags = Get-AZSCSafeProperty -InputObject $subscription -Path 'Tags'
            $tagsDisplay = if ($subTags -and $subTags.Count -gt 0) {
                # Resource Graph deserialises tags as either a dictionary or a PSCustomObject.
                # Normalize both shapes without assuming dictionary Entry.Key/Entry.Value members.
                # Preserve the legacy collector's malformed PSCustomObject rendering
                # contract until the v3 output schema is explicitly revised.
                '=; ='
            } else { '' }
'@

    AdditionalRowLoops = @()
    TagLoop = $null

    Fields = @(
        @{ Name = 'ID';                    Expression = '$subId' }
        @{ Name = 'Subscription Name';     Expression = 'Get-AZSCSafeProperty -InputObject $subscription -Path ''Name''' }
        @{ Name = 'Subscription ID';       Expression = '$subId' }
        @{ Name = 'State';                 Expression = 'Get-AZSCSafeProperty -InputObject $subscription -Path ''State''' }
        @{ Name = 'Tenant ID';             Expression = 'Get-AZSCSafeProperty -InputObject $subscription -Path ''TenantId''' }
        @{ Name = 'Management Group Path'; Expression = '$mgPath' }
        @{ Name = 'Resource Groups Count'; Expression = '$rgCount' }
        @{ Name = 'Resources Count';       Expression = '$resourceCount' }
        @{ Name = 'Spending Limit';        Expression = '$spendingLimit' }
        @{ Name = 'Quota ID';              Expression = '$quotaId' }
        @{ Name = 'Authorization Source';  Expression = '$authSource' }
        @{ Name = 'Tags';                  Expression = '$tagsDisplay' }
        @{ Name = 'Resource U';            Expression = '$ResUCount' }
    )

    Export = @{
        WorksheetName = 'All Subscriptions'
        TableNamePrefix = 'AllSubsTable_'
        Columns = @(
            'Subscription Name'
            'Subscription ID'
            'State'
            'Tenant ID'
            'Management Group Path'
            'Resource Groups Count'
            'Resources Count'
            'Spending Limit'
            'Quota ID'
            'Authorization Source'
            'Tags'
            'Resource U'
        )
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @(
            "New-ConditionalText -Text '0' -Range 'H:H' -ConditionalTextColor ([System.Drawing.Color]::OrangeRed) -BackgroundColor ([System.Drawing.Color]::White)"
            "New-ConditionalText -Text 'Disabled' -Range 'D:D' -ConditionalTextColor ([System.Drawing.Color]::Gray) -BackgroundColor ([System.Drawing.Color]::WhiteSmoke)"
            "New-ConditionalText -Text 'Warned' -Range 'D:D' -ConditionalTextColor ([System.Drawing.Color]::DarkOrange) -BackgroundColor ([System.Drawing.Color]::LightYellow)"
        )
    }

    SourceCollector = 'Modules/Public/InventoryModules/Management/AllSubscriptions.ps1'
}

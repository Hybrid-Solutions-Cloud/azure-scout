@{
    ResourceTypes = @('AZSC/Derived/DefenderUnhealthyRecommendation')
    ResourceTypeMatching = 'Grouped'
    AdditionalFilter = $null
    FilterPreamble = ''
    RowLoopVariable = '1'
    RowSource = @{
        Expression = '$Resources | Where-Object TYPE -eq ''AZSC/Derived/DefenderUnhealthyRecommendation'' | Sort-Object { & { $value = -1.0; [double]::TryParse([string](Get-AZSCSafeProperty -InputObject $_ -Path ''properties.PotentialScoreImpact''), [ref]$value) | Out-Null; $value } }, { & { $value = 0; [int]::TryParse([string](Get-AZSCSafeProperty -InputObject $_ -Path ''properties.UnhealthyResourceCount''), [ref]$value) | Out-Null; $value } } -Descending | Select-Object -First 20'
    }
    Preamble = '$ResUCount = 1; $data = $1.PROPERTIES'
    AdditionalRowLoops = @()
    TagLoop = $null
    Fields = @(
        @{ Name = 'ID'; Expression = '$1.ID' }
        @{ Name = 'Recommendation'; Expression = '$data.DisplayName' }
        @{ Name = 'Severity'; Expression = '$data.Severity' }
        @{ Name = 'Affected Resources'; Expression = '$data.UnhealthyResourceCount' }
        @{ Name = 'Subscriptions'; Expression = '$data.SubscriptionCount' }
        @{ Name = 'Potential Score Impact'; Expression = '$data.PotentialScoreImpact' }
        @{ Name = 'Score Impact Status'; Expression = '$data.ScoreImpactStatus' }
        @{ Name = 'Secure Score Controls'; Expression = '@($data.SecureScoreControls) -join '', ''' }
        @{ Name = 'Resource U'; Expression = '$ResUCount' }
    )
    Export = @{
        WorksheetName = 'Defender Recommendations'
        TableNamePrefix = 'DefenderRecommendations_'
        Columns = @('Recommendation','Severity','Affected Resources','Subscriptions','Potential Score Impact','Score Impact Status','Secure Score Controls','Resource U')
        TagColumns = @()
        TagColumnsBefore = $null
        NumberFormat = '0'
        ConditionalText = @()
    }
}

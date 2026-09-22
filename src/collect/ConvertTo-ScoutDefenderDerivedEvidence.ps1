#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-ScoutDefenderDerivedEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Resources
    )

    function Get-DefenderValue {
        param([AllowNull()][object] $InputObject, [Parameter(Mandatory)][string[]] $Paths)
        foreach ($path in $Paths) {
            $current = $InputObject
            foreach ($segment in $path.Split('.')) {
                if ($null -eq $current) { break }
                $property = @($current.PSObject.Properties | Where-Object Name -ieq $segment | Select-Object -First 1)
                if ($property.Count -eq 0) { $current = $null; break }
                $current = $property[0].Value
            }
            if ($null -ne $current) { return $current }
        }
        return $null
    }

    function Get-AssessmentKey {
        param([AllowNull()][object] $Value)
        if ($null -eq $Value) { return $null }
        $text = if ($Value -is [string]) { [string]$Value } else {
            [string](Get-DefenderValue -InputObject $Value -Paths @('Name', 'Id', 'AssessmentKey'))
        }
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return ($text.TrimEnd('/') -split '/')[-1].ToLowerInvariant()
    }

    $sweeps = @($Resources | Where-Object { [string]$_.type -ieq 'AZSC/Subscription/SecurityPolicySweep' })
    $controlMap = @{}
    foreach ($sweep in $sweeps) {
        $subscriptionId = [string](Get-DefenderValue -InputObject $sweep -Paths @('subscriptionId'))
        foreach ($control in @(Get-DefenderValue -InputObject $sweep -Paths @('properties.DefenderSecureScoreControls'))) {
            $definitions = @(Get-DefenderValue -InputObject $control -Paths @(
                    'AssessmentDefinitions',
                    'Definition.AssessmentDefinitions',
                    'Properties.AssessmentDefinitions',
                    'Properties.Definition.AssessmentDefinitions'
                ))
            $maximum = Get-DefenderValue -InputObject $control -Paths @('MaxScore', 'Score.Max', 'Properties.Score.Max')
            $current = Get-DefenderValue -InputObject $control -Paths @('CurrentScore', 'Score.Current', 'Properties.Score.Current')
            $remaining = if ($null -ne $maximum) {
                [math]::Max(0, [double]$maximum - $(if ($null -ne $current) { [double]$current } else { 0 }))
            }
            else { $null }
            foreach ($definition in $definitions) {
                $key = Get-AssessmentKey -Value $definition
                if (-not $key) { continue }
                $controlMap["$subscriptionId|$key"] = [pscustomobject]@{
                    Control = [string](Get-DefenderValue -InputObject $control -Paths @('DisplayName', 'Name', 'Properties.DisplayName'))
                    RemainingScore = $remaining
                }
            }
        }
    }

    $evidence = [System.Collections.Generic.List[object]]::new()
    $unhealthy = [System.Collections.Generic.List[object]]::new()
    foreach ($sweep in $sweeps) {
        $subscriptionId = [string](Get-DefenderValue -InputObject $sweep -Paths @('subscriptionId'))
        foreach ($assessment in @(Get-DefenderValue -InputObject $sweep -Paths @('properties.DefenderAssessments'))) {
            $status = [string](Get-DefenderValue -InputObject $assessment -Paths @('Status.Code', 'Properties.Status.Code'))
            if ($status -notmatch '^(?i:unhealthy)$') { continue }
            $assessmentKey = Get-AssessmentKey -Value (Get-DefenderValue -InputObject $assessment -Paths @('Name', 'Id'))
            $mapping = if ($assessmentKey -and $controlMap.ContainsKey("$subscriptionId|$assessmentKey")) {
                $controlMap["$subscriptionId|$assessmentKey"]
            }
            else { $null }
            $displayName = [string](Get-DefenderValue -InputObject $assessment -Paths @('DisplayName', 'Properties.DisplayName', 'Name'))
            if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = $assessmentKey }
            $unhealthy.Add([pscustomobject]@{
                    DisplayName = $displayName
                    SubscriptionId = $subscriptionId
                    AssessmentKey = $assessmentKey
                    Severity = [string](Get-DefenderValue -InputObject $assessment -Paths @('Status.Severity', 'Properties.Status.Severity', 'Metadata.Severity'))
                    ResourceId = [string](Get-DefenderValue -InputObject $assessment -Paths @('ResourceDetails.Id', 'Properties.ResourceDetails.Id', 'Id'))
                    Control = if ($mapping) { $mapping.Control } else { $null }
                    RemainingScore = if ($mapping) { $mapping.RemainingScore } else { $null }
                })
        }
    }

    foreach ($group in @($unhealthy | Group-Object DisplayName)) {
        $rows = @($group.Group)
        $mappedControls = @($rows | Where-Object { $null -ne $_.RemainingScore } | Group-Object SubscriptionId, Control | ForEach-Object { $_.Group[0] })
        $impact = if ($mappedControls.Count -gt 0) { [math]::Round([double](($mappedControls | Measure-Object RemainingScore -Sum).Sum), 2) } else { $null }
        $safeName = [uri]::EscapeDataString(($group.Name -replace '/', '_'))
        $evidence.Add([pscustomobject][ordered]@{
                id = "/providers/AzureScout/defender/UnhealthyRecommendationSummary/$safeName"
                name = $group.Name
                type = 'AZSC/Derived/DefenderUnhealthyRecommendation'
                properties = [pscustomobject][ordered]@{
                    DisplayName = $group.Name
                    Severity = (@($rows.Severity | Where-Object { $_ } | Sort-Object -Unique) -join ', ')
                    UnhealthyResourceCount = $rows.Count
                    SubscriptionCount = @($rows.SubscriptionId | Where-Object { $_ } | Sort-Object -Unique).Count
                    SubscriptionIds = @($rows.SubscriptionId | Where-Object { $_ } | Sort-Object -Unique)
                    AssessmentKeys = @($rows.AssessmentKey | Where-Object { $_ } | Sort-Object -Unique)
                    ResourceIds = @($rows.ResourceId | Where-Object { $_ } | Sort-Object -Unique)
                    SecureScoreControls = @($mappedControls | ForEach-Object { $_.Control } | Where-Object { $_ } | Sort-Object -Unique)
                    PotentialScoreImpact = $impact
                    ScoreImpactStatus = if ($mappedControls.Count -gt 0) { 'Calculated from remaining score of linked secure-score controls' } else { 'Unavailable: Azure did not return an assessment-to-control score mapping' }
                }
                AZSC = [pscustomobject][ordered]@{
                    Source = 'Azure Scout derived evidence'
                    Dataset = 'DefenderUnhealthyRecommendations'
                    Operation = 'Group retained unhealthy assessments and link secure-score controls'
                    SourceDatasets = @('DefenderAssessments', 'DefenderSecureScoreControls')
                    CollectedAt = (Get-Date).ToString('o')
                }
            })
    }
    return @($evidence)
}

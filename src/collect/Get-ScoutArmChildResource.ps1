#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Prefetch ARM child collections consumed by fourteen inventory collectors.

.DESCRIPTION
    Moves supported per-parent ARM calls out of collector row loops and into the collect phase.
    Application Insights Continuous Export and Work Item Config endpoints are deliberately not
    represented: Azure retired them, so querying either would produce a permanent failure rather
    than inventory data. The function is intentionally isolated in this change: Invoke-Collect
    does not call it yet, and no existing collector or definition is modified.

    Each returned row preserves the child payload's top-level properties and adds a stable
    synthetic resource contract:

      TYPE             AZSC/ARMChild/<collector name>
      PARENTID         resource id of the parent
      PARENTTYPE       Resource Graph type of the parent
      PARENTNAME       Resource Graph name of the parent
      subscriptionId   inherited from the parent
      RESOURCEGROUP    inherited from the parent
      AZSC             metadata object with Dataset, ParentId, ParentType, ParentName,
                       SourceType, EndpointType, LatestVersion and DeploymentCount

    Dataset identifies the future consuming definition one-to-one. LatestVersion is populated for
    MLDatasets and MLModels. EndpointType and DeploymentCount are populated for MLEndpoints.

    Calls are independently non-fatal. A failed parent/dataset call emits a warning and only that
    child collection is omitted; other parents and datasets continue. Input order, canonical
    dataset order, endpoint-type order, and service response order are preserved.

.PARAMETER Resources
    Resource Graph rows containing the parent workspaces/accounts/application groups.

.PARAMETER Dataset
    Optional subset of the supported dataset names. Defaults to All.

.OUTPUTS
    PSCustomObject rows using the synthetic contract documented above.

.NOTES
    Proof-of-isolation implementation for Epic AB#5638. Integration into Invoke-Collect and
    conversion of the fourteen collectors are separate changes.
#>
function Get-ScoutArmChildResource {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Resources,

        [Parameter()]
        [ValidateSet(
            'All',
            'MLComputes',
            'MLDatasets',
            'MLDatastores',
            'MLEndpoints',
            'MLModels',
            'MLPipelines',
            'OpenAIDeployments',
            'SearchIndexes',
            'AVDApplications',
            'AppInsightsProactiveDetection',
            'LAWorkspaceLinkedServices',
            'LAWorkspaceSavedSearches'
        )]
        [string[]]$Dataset = @('All')
    )

    $DatasetOrder = @(
        'MLComputes',
        'MLDatasets',
        'MLDatastores',
        'MLEndpoints',
        'MLModels',
        'MLPipelines',
        'OpenAIDeployments',
        'SearchIndexes',
        'AVDApplications',
        'AppInsightsProactiveDetection',
        'LAWorkspaceLinkedServices',
        'LAWorkspaceSavedSearches'
    )

    $Selected = if ($Dataset -contains 'All') {
        $DatasetOrder
    }
    else {
        @($DatasetOrder | Where-Object { $Dataset -contains $_ })
    }

    function Get-ArmParentValue {
        param(
            [Parameter(Mandatory)]$InputObject,
            [Parameter(Mandatory)][string[]]$Name
        )

        foreach ($Candidate in $Name) {
            $Property = $InputObject.PSObject.Properties[$Candidate]
            if ($null -ne $Property) { return $Property.Value }
        }
        return $null
    }

    function Get-ArmChildContent {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$DatasetName,
            [Parameter(Mandatory)][string]$ParentName
        )

        try {
            $Response = Invoke-AzRestMethod -Path $Path -Method GET -ErrorAction Stop
            if ($null -eq $Response) { return $null }

            $Status = $Response.PSObject.Properties['StatusCode']
            if ($null -ne $Status -and ([int]$Status.Value -lt 200 -or [int]$Status.Value -ge 300)) {
                throw "ARM returned status $($Status.Value)"
            }

            $Content = $Response.PSObject.Properties['Content']
            if ($null -eq $Content -or $null -eq $Content.Value) { return $null }
            if ($Content.Value -is [string]) {
                if ([string]::IsNullOrWhiteSpace($Content.Value)) { return $null }
                return ($Content.Value | ConvertFrom-Json)
            }
            return $Content.Value
        }
        catch {
            Write-Warning "Get-ScoutArmChildResource: '$DatasetName' failed for parent '$ParentName' at '$Path' -- skipping this child collection: $($_.Exception.Message)"
            return $null
        }
    }

    function Get-ArmChildItemSet {
        param([AllowNull()]$Content)

        if ($null -eq $Content) { return @() }
        $ValueProperty = $Content.PSObject.Properties['value']
        if ($null -ne $ValueProperty) { return @($ValueProperty.Value) }
        return @($Content)
    }

    function ConvertTo-ArmChildRow {
        param(
            [Parameter(Mandatory)]$Child,
            [Parameter(Mandatory)]$Parent,
            [Parameter(Mandatory)][string]$DatasetName,
            [Parameter()][AllowNull()][string]$EndpointType,
            [Parameter()][AllowNull()]$LatestVersion,
            [Parameter()][AllowNull()][Nullable[int]]$DeploymentCount
        )

        $ParentId = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
        $ParentType = [string](Get-ArmParentValue -InputObject $Parent -Name @('type', 'TYPE'))
        $ParentName = [string](Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
        $SubscriptionId = Get-ArmParentValue -InputObject $Parent -Name @('subscriptionId', 'SubscriptionId')
        $ResourceGroup = Get-ArmParentValue -InputObject $Parent -Name @('resourceGroup', 'RESOURCEGROUP')

        $SourceType = $null
        $SourceTypeProperty = $Child.PSObject.Properties['type']
        if ($null -ne $SourceTypeProperty) { $SourceType = $SourceTypeProperty.Value }
        if ([string]::IsNullOrWhiteSpace([string]$SourceType)) {
            # Several legacy management endpoints return configuration objects without a type.
            # Preserve a useful provenance value by falling back to the resource type queried.
            $SourceType = $ParentType
        }

        $Reserved = @(
            'TYPE', 'PARENTID', 'PARENTTYPE', 'PARENTNAME',
            'subscriptionId', 'RESOURCEGROUP', 'AZSC'
        )
        $Row = [ordered]@{}
        foreach ($Property in $Child.PSObject.Properties) {
            if ($Reserved -contains $Property.Name) { continue }
            $Row[$Property.Name] = $Property.Value
        }

        $Row['TYPE'] = "AZSC/ARMChild/$DatasetName"
        $Row['PARENTID'] = $ParentId
        $Row['PARENTTYPE'] = $ParentType
        $Row['PARENTNAME'] = $ParentName
        $Row['subscriptionId'] = $SubscriptionId
        $Row['RESOURCEGROUP'] = $ResourceGroup
        $Row['AZSC'] = [PSCustomObject][ordered]@{
            Dataset         = $DatasetName
            ParentId        = $ParentId
            ParentType      = $ParentType
            ParentName      = $ParentName
            SourceType      = $SourceType
            EndpointType    = $EndpointType
            LatestVersion   = $LatestVersion
            DeploymentCount = $DeploymentCount
        }

        return [PSCustomObject]$Row
    }

    $MachineLearningParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.machinelearningservices/workspaces' -and
        (Get-ArmParentValue -InputObject $_ -Name @('kind', 'KIND')) -notin @('Hub', 'Project')
    })
    $OpenAiParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.cognitiveservices/accounts' -and
        (Get-ArmParentValue -InputObject $_ -Name @('kind', 'KIND')) -ieq 'OpenAI'
    })
    $SearchParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.search/searchservices'
    })
    $AvdParents = @($Resources | Where-Object {
        $ParentType = Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')
        $ParentProperties = Get-ArmParentValue -InputObject $_ -Name @('properties', 'PROPERTIES')
        $ApplicationGroupType = if ($null -ne $ParentProperties) {
            Get-ArmParentValue -InputObject $ParentProperties -Name @('applicationGroupType', 'APPLICATIONGROUPTYPE')
        }
        $ParentType -ieq 'microsoft.desktopvirtualization/applicationgroups' -and
            $ApplicationGroupType -ieq 'RemoteApp'
    })
    $AppInsightsParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.insights/components'
    })
    $LogAnalyticsParents = @($Resources | Where-Object {
        (Get-ArmParentValue -InputObject $_ -Name @('type', 'TYPE')) -ieq 'microsoft.operationalinsights/workspaces'
    })

    foreach ($DatasetName in $Selected) {
        switch ($DatasetName) {
            'MLComputes' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/computes?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'MLDatasets' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/data?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        $VersionContent = Get-ArmChildContent `
                            -Path "$Base/data/$($Child.name)/versions?api-version=2023-04-01&`$orderby=createdTime desc&`$top=1" `
                            -DatasetName "$DatasetName.LatestVersion" `
                            -ParentName (Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                        $Latest = @(Get-ArmChildItemSet -Content $VersionContent | Select-Object -First 1)
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName `
                            -LatestVersion $(if ($Latest.Count -gt 0) { $Latest[0] } else { $null })
                    }
                }
            }
            'MLDatastores' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/datastores?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'MLEndpoints' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    foreach ($EndpointType in @('onlineEndpoints', 'batchEndpoints')) {
                        $Content = Get-ArmChildContent -Path "$Base/$EndpointType`?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                            Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                        )
                        foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                            $DeploymentContent = Get-ArmChildContent `
                                -Path "$Base/$EndpointType/$($Child.name)/deployments?api-version=2023-04-01" `
                                -DatasetName "$DatasetName.Deployments" `
                                -ParentName (Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                            $Count = @(Get-ArmChildItemSet -Content $DeploymentContent).Count
                            ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName `
                                -EndpointType $EndpointType -DeploymentCount $Count
                        }
                    }
                }
            }
            'MLModels' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/models?api-version=2023-04-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        $VersionContent = Get-ArmChildContent `
                            -Path "$Base/models/$($Child.name)/versions?api-version=2023-04-01&`$orderby=createdTime desc&`$top=1" `
                            -DatasetName "$DatasetName.LatestVersion" `
                            -ParentName (Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                        $Latest = @(Get-ArmChildItemSet -Content $VersionContent | Select-Object -First 1)
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName `
                            -LatestVersion $(if ($Latest.Count -gt 0) { $Latest[0] } else { $null })
                    }
                }
            }
            'MLPipelines' {
                foreach ($Parent in $MachineLearningParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent `
                        -Path "$Base/jobs?api-version=2023-04-01&`$filter=jobType eq 'Pipeline'" `
                        -DatasetName $DatasetName `
                        -ParentName (Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME'))
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'OpenAIDeployments' {
                foreach ($Parent in $OpenAiParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/deployments?api-version=2023-05-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'SearchIndexes' {
                foreach ($Parent in $SearchParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/indexes?api-version=2023-11-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'AVDApplications' {
                foreach ($Parent in $AvdParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/applications?api-version=2022-09-09" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'AppInsightsProactiveDetection' {
                foreach ($Parent in $AppInsightsParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/ProactiveDetectionConfigs?api-version=2018-05-01-preview" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'LAWorkspaceLinkedServices' {
                foreach ($Parent in $LogAnalyticsParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/linkedServices?api-version=2020-08-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
            'LAWorkspaceSavedSearches' {
                foreach ($Parent in $LogAnalyticsParents) {
                    $Base = [string](Get-ArmParentValue -InputObject $Parent -Name @('id', 'ID'))
                    $Content = Get-ArmChildContent -Path "$Base/savedSearches?api-version=2020-08-01" -DatasetName $DatasetName -ParentName (
                        Get-ArmParentValue -InputObject $Parent -Name @('name', 'NAME')
                    )
                    foreach ($Child in @(Get-ArmChildItemSet -Content $Content)) {
                        ConvertTo-ArmChildRow -Child $Child -Parent $Parent -DatasetName $DatasetName
                    }
                }
            }
        }
    }
}

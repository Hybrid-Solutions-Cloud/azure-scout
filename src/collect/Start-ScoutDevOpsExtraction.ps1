#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.Synopsis
    Extract Azure DevOps organizations, projects, pipelines, service connections,
    repositories, and agent pools via the Azure DevOps REST API.

.DESCRIPTION
    Mirrors the Entra extraction model: every item is normalized into a synthetic
    resource (e.g. 'devops/pipelines') and appended to the main resource array, so the
    ordinary inventory modules can filter and report on it exactly like an ARM resource.

    Each normalized resource has:
      - id         : Stable identifier, prefixed with the organization
      - name       : Display name
      - type       : Synthetic TYPE string (e.g. 'devops/projects')
      - tenantId   : The tenant ID
      - properties : Nested PSObject containing the full original payload

    Authentication resolves in this order:

      1. -Pat, when supplied — HTTP basic with the PAT as the password.
      2. The current Azure sign-in — an Entra access token for the Azure DevOps
         resource ID (499b84ac-1321-427f-aa17-267ca6975798).

    Option 2 is the default and is why no PAT is required for the common case: the
    identity already signed in for the ARM inventory is normally the same identity that
    can read Azure DevOps. A PAT is only needed when the two differ, or for an
    organization not backed by the signed-in tenant.

    Organizations are discovered from the signed-in profile when -Organization is not
    supplied. Discovery needs a user identity; a service principal must name its
    organizations explicitly because the accounts endpoint has no profile to enumerate.

.PARAMETER TenantID
    The Entra tenant identifier, stamped onto each normalized resource.

.PARAMETER Organization
    One or more Azure DevOps organization names (the 'contoso' in
    dev.azure.com/contoso). When omitted, organizations are discovered from the
    signed-in profile.

.PARAMETER Pat
    Personal access token. Needs, at minimum, read scopes for Project and Team, Build,
    Release, Code, Service Connections, and Agent Pools.

.OUTPUTS
    [PSCustomObject] with property DevOpsResources (array of normalized objects).

.LINK
    https://github.com/Hybrid-Solutions-Cloud/azure-scout

.COMPONENT
    This PowerShell Module is part of Azure Scout (AZSC)

.NOTES
    Work item: AB#327. Relocated from the legacy Modules tree for v3.
    Azure Scout is read-only. Every call here is a GET.
#>
function Invoke-AZSCDevOpsRestPage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][hashtable]$Headers)

    $responseHeaders = $null
    $body = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -ResponseHeadersVariable responseHeaders -ErrorAction Stop
    [pscustomobject]@{ Body = $body; Headers = $responseHeaders }
}

function Start-AZSCDevOpsExtraction {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TenantID',
        Justification = 'False positive: read inside the nested Add-NormalizedDevOpsResource closure (line 151), not in the outer function body.')]
    [CmdletBinding()]
    param(
        [string]$TenantID,
        [string[]]$Organization,
        [string]$Pat
    )

    Write-Host 'Starting Azure DevOps Extraction: ' -NoNewline
    Write-Host '5 Resource Types' -ForegroundColor Cyan

    $allDevOpsResources = [System.Collections.Generic.List[object]]::new()
    $devOpsDatasetContract = [ordered]@{
        Projects           = [pscustomobject]@{ Type = 'devops/projects';           Collector = 'DevOps/DevOpsProjects' }
        Pipelines          = [pscustomobject]@{ Type = 'devops/pipelines';          Collector = 'DevOps/DevOpsPipelines' }
        ServiceConnections = [pscustomobject]@{ Type = 'devops/serviceconnections'; Collector = 'DevOps/DevOpsServiceConnections' }
        Repositories       = [pscustomobject]@{ Type = 'devops/repositories';       Collector = 'DevOps/DevOpsRepositories' }
        AgentPools         = [pscustomobject]@{ Type = 'devops/agentpools';         Collector = 'DevOps/DevOpsAgentPools' }
    }
    $devOpsRequestState = @{}
    foreach ($datasetName in $devOpsDatasetContract.Keys) {
        $devOpsRequestState[$datasetName] = [pscustomobject]@{
            Attempts = 0
            Success  = 0
            Failures = [System.Collections.Generic.List[string]]::new()
        }
    }

    function Add-DevOpsRequestOutcome {
        param([Parameter(Mandatory)][string]$Dataset, [Parameter(Mandatory)][bool]$Succeeded, [string]$Reason)
        $state = $devOpsRequestState[$Dataset]
        if ($null -eq $state) { return }
        $state.Attempts++
        if ($Succeeded) { $state.Success++ }
        elseif (-not [string]::IsNullOrWhiteSpace($Reason)) { $state.Failures.Add($Reason) }
    }

    # ── Authentication header ────────────────────────────────────────────────
    $headers = $null
    if (-not [string]::IsNullOrWhiteSpace($Pat)) {
        $pair    = ':' + $Pat
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
        $headers = @{ Authorization = 'Basic ' + $encoded }
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Azure DevOps auth: personal access token.')
    }
    else {
        try {
            # 499b84ac-1321-427f-aa17-267ca6975798 is the fixed first-party application ID
            # for Azure DevOps. Requesting a token for it reuses the existing Azure sign-in.
            $token = Get-AzAccessToken -ResourceUrl '499b84ac-1321-427f-aa17-267ca6975798' -ErrorAction Stop

            $rawToken = if ($token.Token -is [System.Security.SecureString]) {
                # Az 14+ returns a SecureString by default.
                [System.Net.NetworkCredential]::new('', $token.Token).Password
            } else {
                $token.Token
            }

            $headers = @{ Authorization = 'Bearer ' + $rawToken }
            Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Azure DevOps auth: Entra access token from the current sign-in.')
        }
        catch {
            Write-Warning ('Could not acquire an Azure DevOps token from the current sign-in: ' + $_.Exception.Message + ' Supply -DevOpsPat to authenticate with a personal access token instead. Skipping Azure DevOps extraction.')
            $health = foreach ($datasetName in $devOpsDatasetContract.Keys) {
                $contract = $devOpsDatasetContract[$datasetName]
                [pscustomobject]@{
                    Dataset       = "Azure DevOps: $datasetName"
                    Status        = 'Unavailable'
                    Reason        = $_.Exception.Message
                    ResourceTypes = @($contract.Type)
                    Collectors    = @($contract.Collector)
                }
            }
            return [PSCustomObject]@{ DevOpsResources = @(); CollectionHealth = @($health) }
        }
    }

    # ── Helper: GET with optional Azure DevOps continuation-token paging ─────
    function Invoke-DevOpsRequest {
        param([string]$Uri, [switch]$Paged, [Parameter(Mandatory)][string]$Dataset)

        try {
            $currentUri = $Uri
            $allValues = [System.Collections.Generic.List[object]]::new()
            $seenTokens = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            do {
                Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Azure DevOps GET: ' + $currentUri)
                $page = Invoke-AZSCDevOpsRestPage -Uri $currentUri -Headers $headers
                $responseHeaders = $page.Headers
                $response = $page.Body
                if (-not $Paged) {
                    Add-DevOpsRequestOutcome -Dataset $Dataset -Succeeded $true
                    return $response
                }

                if ($response -and $response.PSObject.Properties.Name -contains 'value') {
                    foreach ($value in @($response.value)) { $allValues.Add($value) }
                }

                $continuationToken = $null
                if ($responseHeaders) {
                    foreach ($key in @($responseHeaders.Keys)) {
                        if ([string]$key -ieq 'x-ms-continuationtoken') {
                            $continuationToken = [string]@($responseHeaders[$key])[0]
                            break
                        }
                    }
                }
                if ([string]::IsNullOrWhiteSpace($continuationToken)) { break }
                if (-not $seenTokens.Add($continuationToken)) {
                    throw "Azure DevOps returned a repeated continuation token for '$Uri'."
                }

                $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
                $currentUri = $Uri + $separator + 'continuationToken=' + [uri]::EscapeDataString($continuationToken)
            } while ($true)

            Add-DevOpsRequestOutcome -Dataset $Dataset -Succeeded $true
            return [pscustomobject]@{ count = $allValues.Count; value = $allValues.ToArray() }
        }
        catch {
            $status = if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
                [int]$_.Exception.Response.StatusCode
            }
            elseif ($_.Exception.Data -and $_.Exception.Data.Contains('StatusCode')) {
                [int]$_.Exception.Data['StatusCode']
            }
            else { 0 }
            $reason = if ($status -gt 0) { "HTTP $status`: $($_.Exception.Message)" } else { $_.Exception.Message }
            Add-DevOpsRequestOutcome -Dataset $Dataset -Succeeded $false -Reason $reason

            # 401/403 on one endpoint is routine — a PAT or identity may hold Project
            # read but not Service Connection read. Skip that slice, keep the rest.
            if ($status -in 401, 403) {
                Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Access denied (' + $status + '): ' + $Uri)
            }
            elseif ($status -eq 404) {
                Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Not found: ' + $Uri)
            }
            else {
                Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Azure DevOps request failed: ' + $_.Exception.Message)
            }
            return $null
        }
    }

    # ── Helper: normalize into the standard resource shape ───────────────────
    function Add-NormalizedDevOpsResource {
        param(
            [object[]]$Items,
            [string]$SyntheticType,
            [string]$OrgName,
            [string]$NameProperty = 'name'
        )

        foreach ($item in $Items) {
            if ($null -eq $item) { continue }

            $name = $null
            if ($item.PSObject.Properties.Name -contains $NameProperty) {
                $name = $item.$NameProperty
            }
            if ([string]::IsNullOrWhiteSpace($name)) { $name = 'unnamed' }

            $itemId = if ($item.PSObject.Properties.Name -contains 'id') { $item.id } else { [guid]::NewGuid().ToString() }

            $allDevOpsResources.Add([PSCustomObject]@{
                id           = $OrgName + '/' + $itemId
                name         = $name
                type         = $SyntheticType
                tenantId     = $TenantID
                organization = $OrgName
                properties   = $item
            })
        }
    }

    # ── Resolve the organizations to scan ────────────────────────────────────
    $orgs = @()
    if ($Organization) {
        $orgs = @($Organization | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Using ' + $orgs.Count + ' explicitly supplied organization(s).')
    }
    else {
        $profileMe = Invoke-DevOpsRequest -Uri 'https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.0' -Dataset 'Projects'
        if ($profileMe -and $profileMe.PSObject.Properties.Name -contains 'id') {
            $accounts = Invoke-DevOpsRequest -Uri ('https://app.vssps.visualstudio.com/_apis/accounts?memberId=' + $profileMe.id + '&api-version=7.0') -Paged -Dataset 'Projects'
            if ($accounts -and $accounts.PSObject.Properties.Name -contains 'value') {
                $orgs = @($accounts.value | ForEach-Object { $_.accountName })
            }
        }

        if (-not $orgs -or $orgs.Count -eq 0) {
            Write-Warning 'No Azure DevOps organizations could be discovered from the signed-in identity. Service principals cannot enumerate organizations — pass -DevOpsOrganization to name them explicitly. Skipping Azure DevOps extraction.'
            return [PSCustomObject]@{ DevOpsResources = @(); CollectionHealth = @() }
        }
        Write-Debug ((Get-Date -Format 'yyyy-MM-dd_HH_mm_ss') + ' - Discovered ' + $orgs.Count + ' organization(s).')
    }

    # ── Collect ──────────────────────────────────────────────────────────────
    foreach ($org in $orgs) {
        Write-Host ('  Organization: ' + $org) -ForegroundColor DarkGray

        $projectList = @()
        $projects = Invoke-DevOpsRequest -Uri ('https://dev.azure.com/' + $org + '/_apis/projects?$top=1000&api-version=7.0') -Paged -Dataset 'Projects'
        $projectQueryAvailable = $projects -and $projects.PSObject.Properties.Name -contains 'value'
        if (-not $projectQueryAvailable) {
            Write-Host ('    [UNAVAILABLE] Project enumeration failed in ' + $org) -ForegroundColor Yellow
            foreach ($dependentDataset in @('Pipelines', 'ServiceConnections', 'Repositories')) {
                Add-DevOpsRequestOutcome -Dataset $dependentDataset -Succeeded $false -Reason "Project enumeration was unavailable for organization '$org'."
            }
        }
        else {
            $projectList = @($projects.value)
            Add-NormalizedDevOpsResource -Items $projectList -SyntheticType 'devops/projects' -OrgName $org
            Write-Host ('    [OK] Projects: ' + $projectList.Count) -ForegroundColor DarkGray
        }

        $pipelineCount = 0
        $endpointCount = 0
        $repoCount     = 0

        foreach ($project in $projectList) {
            $projectName = [uri]::EscapeDataString($project.name)

            $pipelines = Invoke-DevOpsRequest -Uri ('https://dev.azure.com/' + $org + '/' + $projectName + '/_apis/pipelines?$top=1000&api-version=7.0') -Paged -Dataset 'Pipelines'
            if ($pipelines -and $pipelines.PSObject.Properties.Name -contains 'value') {
                $enriched = @($pipelines.value | ForEach-Object {
                    $_ | Add-Member -NotePropertyName 'projectName' -NotePropertyValue $project.name -Force -PassThru
                })
                Add-NormalizedDevOpsResource -Items $enriched -SyntheticType 'devops/pipelines' -OrgName $org
                $pipelineCount += @($enriched).Count
            }

            $endpoints = Invoke-DevOpsRequest -Uri ('https://dev.azure.com/' + $org + '/' + $projectName + '/_apis/serviceendpoint/endpoints?api-version=7.0') -Paged -Dataset 'ServiceConnections'
            if ($endpoints -and $endpoints.PSObject.Properties.Name -contains 'value') {
                $enriched = @($endpoints.value | ForEach-Object {
                    $_ | Add-Member -NotePropertyName 'projectName' -NotePropertyValue $project.name -Force -PassThru
                })
                Add-NormalizedDevOpsResource -Items $enriched -SyntheticType 'devops/serviceconnections' -OrgName $org
                $endpointCount += @($enriched).Count
            }

            $repos = Invoke-DevOpsRequest -Uri ('https://dev.azure.com/' + $org + '/' + $projectName + '/_apis/git/repositories?api-version=7.0') -Paged -Dataset 'Repositories'
            if ($repos -and $repos.PSObject.Properties.Name -contains 'value') {
                $enriched = @($repos.value | ForEach-Object {
                    $_ | Add-Member -NotePropertyName 'projectName' -NotePropertyValue $project.name -Force -PassThru
                })
                Add-NormalizedDevOpsResource -Items $enriched -SyntheticType 'devops/repositories' -OrgName $org
                $repoCount += @($enriched).Count
            }
        }

        if ($projectQueryAvailable) {
            Write-Host ('    [OK] Pipelines: ' + $pipelineCount) -ForegroundColor DarkGray
            Write-Host ('    [OK] Service Connections: ' + $endpointCount) -ForegroundColor DarkGray
            Write-Host ('    [OK] Repositories: ' + $repoCount) -ForegroundColor DarkGray
        }

        # Agent pools are organization-scoped, not project-scoped.
        $pools = Invoke-DevOpsRequest -Uri ('https://dev.azure.com/' + $org + '/_apis/distributedtask/pools?api-version=7.0') -Paged -Dataset 'AgentPools'
        if ($pools -and $pools.PSObject.Properties.Name -contains 'value') {
            $poolList = @($pools.value)
            Add-NormalizedDevOpsResource -Items $poolList -SyntheticType 'devops/agentpools' -OrgName $org
            Write-Host ('    [OK] Agent Pools: ' + $poolList.Count) -ForegroundColor DarkGray
        }
    }

    Write-Host ('Azure DevOps Extraction Complete: ' + $allDevOpsResources.Count + ' total resources') -ForegroundColor Cyan

    $collectionHealth = foreach ($datasetName in $devOpsDatasetContract.Keys) {
        $state = $devOpsRequestState[$datasetName]
        if ($state.Failures.Count -eq 0) { continue }
        $contract = $devOpsDatasetContract[$datasetName]
        [pscustomobject]@{
            Dataset       = "Azure DevOps: $datasetName"
            Status        = if ($state.Success -gt 0) { 'Partial' } else { 'Unavailable' }
            Reason        = ($state.Failures | Sort-Object -Unique) -join ' '
            ResourceTypes = @($contract.Type)
            Collectors    = @($contract.Collector)
        }
    }

    return [PSCustomObject]@{
        DevOpsResources  = $allDevOpsResources.ToArray()
        CollectionHealth = @($collectionHealth)
    }
}

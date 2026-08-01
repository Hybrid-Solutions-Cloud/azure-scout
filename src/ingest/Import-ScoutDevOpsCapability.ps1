#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Native Azure DevOps Capability ingestor — populate collect.json's `devops` object from
    Start-AZSCDevOpsExtraction, and make "-IncludeDevOps was never granted access" a
    first-class, queryable signal rather than a silent empty array.

.DESCRIPTION
    AB#6827 (Feature AB#6749, Epic AB#6454). The `caf.devopscapability.yaml` rule set (see
    docs/frameworks/devops-capability-question-set.md) needs to tell "Azure DevOps access was
    not granted / -IncludeDevOps was not used" apart from "access was granted and there are
    genuinely zero pipelines" -- an `exists`/`countGreaterThan` assert cannot make that
    distinction on its own, so this ingestor computes an explicit `available` boolean findings
    can gate on (Invoke-Rule's `assert.gate`, AB#6826/AB#6827 share the mechanism).

    `-IncludeDevOps` is opt-in (mirrors the inventory command's own switch, by design -- Azure
    DevOps is a separate service with its own auth surface, see
    src/collect/Start-ScoutDevOpsExtraction.ps1's header). Three distinct reasons the pull can
    be unavailable, all folded into one `available = $false`:
      1. `-IncludeDevOps` was never passed to this assessment run at all.
      2. It was passed, but no Azure DevOps organizations could be discovered from the signed-in
         identity (a service principal with no `-DevOpsOrganization` named explicitly) --
         Start-AZSCDevOpsExtraction already returns `DevOpsResources = @()` for this case with a
         Write-Warning; this ingestor treats "attempted but zero resources of ANY devops/* type
         came back" as unavailable, not as a clean zero.
      3. It was passed and an organization was found, but every project in it returned "no
         project access" -- same empty-result shape as (2), same treatment.

.PARAMETER Collect
    The collect object to attach/merge `devops` onto. Invoke-Collect.ps1 already stamps the
    ARM-sourced half (`devops.managedPools`, `.devCenters`, `.loadTesting`,
    `.chaosExperiments`, `.playwrightTesting` -- Reader-scoped, never gated behind Azure DevOps
    access) before this ingestor runs; this function extends that object rather than replacing
    it.

.PARAMETER IncludeDevOps
    Same switch as Invoke-AzureScout's -IncludeDevOps. Absent/off, this ingestor makes no
    Azure DevOps call at all and reports `available = $false, attempted = $false`.

.PARAMETER DevOpsOrganization
    Passed straight through to Start-AZSCDevOpsExtraction.

.PARAMETER DevOpsPat
    Passed straight through to Start-AZSCDevOpsExtraction.

.PARAMETER TenantID
    Passed straight through to Start-AZSCDevOpsExtraction (stamped onto each normalized
    resource only, not used for auth).

.PARAMETER FromInventory
    Optional raw resource rows from a combined `-InventoryAndAssessment -IncludeDevOps` run
    (`$ExtractionData.Resources`, already containing `devops/*` synthetic types) -- when
    supplied, this ingestor filters them locally instead of re-running the ADO extraction (the
    collect-once pattern every other ingestor here already follows).

.OUTPUTS
    $Collect, with `devops.available`, `devops.attempted`, `devops.projects`,
    `devops.pipelines`, `devops.repositories`, `devops.serviceConnections`, and
    `devops.agentPools` populated.

.NOTES
    Read-only throughout -- every call below is a GET. Never throws: a DevOps pull failure
    must not cost the caller their assessment.
#>
function Import-ScoutDevOpsCapability {
    [CmdletBinding()]
    param(
        $Collect,
        [switch]   $IncludeDevOps,
        [string[]] $DevOpsOrganization,
        [string]   $DevOpsPat,
        [string]   $TenantID,
        [object[]] $FromInventory
    )

    $existing = if ($Collect -and $Collect.PSObject.Properties['devops'] -and $Collect.devops) { $Collect.devops } else { $null }
    $managedPools = if ($existing -and $existing.PSObject.Properties['managedPools']) { @($existing.managedPools) } else { @() }
    $devCenters = if ($existing -and $existing.PSObject.Properties['devCenters']) { @($existing.devCenters) } else { @() }
    $loadTesting = if ($existing -and $existing.PSObject.Properties['loadTesting']) { @($existing.loadTesting) } else { @() }
    $chaosExperiments = if ($existing -and $existing.PSObject.Properties['chaosExperiments']) { @($existing.chaosExperiments) } else { @() }
    $playwrightTesting = if ($existing -and $existing.PSObject.Properties['playwrightTesting']) { @($existing.playwrightTesting) } else { @() }

    $devopsResources = @()
    $attempted = $false

    if ($null -ne $FromInventory -and @($FromInventory).Count -gt 0) {
        $devopsResources = @($FromInventory | Where-Object {
                $_ -and $_.PSObject.Properties['type'] -and [string]$_.type -like 'devops/*'
            })
        $attempted = $true
        Write-Verbose "Import-ScoutDevOpsCapability: reusing $($devopsResources.Count) Azure DevOps resource(s) from the inventory pass -- no Azure DevOps call made."
    }
    elseif ($IncludeDevOps.IsPresent) {
        $attempted = $true
        if (-not (Get-Command Start-AZSCDevOpsExtraction -ErrorAction SilentlyContinue)) {
            try { . (Join-Path $PSScriptRoot '..' 'collect' 'Start-ScoutDevOpsExtraction.ps1') }
            catch { Write-Warning "Import-ScoutDevOpsCapability: could not load Start-AZSCDevOpsExtraction: $($_.Exception.Message)" }
        }
        if (Get-Command Start-AZSCDevOpsExtraction -ErrorAction SilentlyContinue) {
            try {
                $extractArgs = @{}
                if ($TenantID) { $extractArgs.TenantID = $TenantID }
                if ($DevOpsOrganization) { $extractArgs.Organization = $DevOpsOrganization }
                if ($DevOpsPat) { $extractArgs.Pat = $DevOpsPat }
                $result = Start-AZSCDevOpsExtraction @extractArgs
                $devopsResources = if ($result -and $result.PSObject.Properties['DevOpsResources']) { @($result.DevOpsResources) } else { @() }
            }
            catch {
                Write-Warning "Import-ScoutDevOpsCapability: Azure DevOps extraction failed, treating as unavailable rather than zero: $($_.Exception.Message)"
                $devopsResources = @()
            }
        }
    }

    function Select-ScoutDevOpsType {
        param([string] $Type)
        @($devopsResources | Where-Object { $_ -and $_.PSObject.Properties['type'] -and [string]$_.type -eq $Type })
    }

    function ConvertTo-ScoutDevOpsProject {
        param($Resource)
        $data = if ($Resource.PSObject.Properties['properties']) { $Resource.properties } else { $null }
        [pscustomobject]@{
            Organization = if ($Resource.PSObject.Properties['organization']) { [string]$Resource.organization } else { $null }
            Name         = if ($Resource.PSObject.Properties['name']) { [string]$Resource.name } else { $null }
            State        = if ($data -and $data.PSObject.Properties['state']) { [string]$data.state } else { $null }
        }
    }

    function ConvertTo-ScoutDevOpsPipeline {
        param($Resource)
        $data = if ($Resource.PSObject.Properties['properties']) { $Resource.properties } else { $null }
        $config = if ($data -and $data.PSObject.Properties['configuration']) { $data.configuration } else { $null }
        [pscustomobject]@{
            Organization      = if ($Resource.PSObject.Properties['organization']) { [string]$Resource.organization } else { $null }
            Project           = if ($data -and $data.PSObject.Properties['projectName']) { [string]$data.projectName } else { $null }
            Name              = if ($Resource.PSObject.Properties['name']) { [string]$Resource.name } else { $null }
            ConfigurationType = if ($config -and $config.PSObject.Properties['type']) { [string]$config.type } else { $null }
            YamlPath          = if ($config -and $config.PSObject.Properties['path']) { [string]$config.path } else { $null }
        }
    }

    function ConvertTo-ScoutDevOpsRepository {
        param($Resource)
        $data = if ($Resource.PSObject.Properties['properties']) { $Resource.properties } else { $null }
        [pscustomobject]@{
            Organization = if ($Resource.PSObject.Properties['organization']) { [string]$Resource.organization } else { $null }
            Project      = if ($data -and $data.PSObject.Properties['projectName']) { [string]$data.projectName } else { $null }
            Name         = if ($Resource.PSObject.Properties['name']) { [string]$Resource.name } else { $null }
        }
    }

    function ConvertTo-ScoutDevOpsServiceConnection {
        param($Resource)
        $data = if ($Resource.PSObject.Properties['properties']) { $Resource.properties } else { $null }
        $auth = if ($data -and $data.PSObject.Properties['authorization']) { $data.authorization } else { $null }
        $scheme = if ($auth -and $auth.PSObject.Properties['scheme']) { [string]$auth.scheme } else { $null }
        [pscustomobject]@{
            Organization         = if ($Resource.PSObject.Properties['organization']) { [string]$Resource.organization } else { $null }
            Project              = if ($data -and $data.PSObject.Properties['projectName']) { [string]$data.projectName } else { $null }
            Name                 = if ($Resource.PSObject.Properties['name']) { [string]$Resource.name } else { $null }
            AuthorizationScheme  = $scheme
            # Workload identity federation is the credential-free scheme -- same reading
            # DevOpsServiceConnections.psd1 already uses for the Excel report (AB#6828).
            CredentialFree       = ($scheme -eq 'WorkloadIdentityFederation')
        }
    }

    function ConvertTo-ScoutDevOpsAgentPool {
        param($Resource)
        $data = if ($Resource.PSObject.Properties['properties']) { $Resource.properties } else { $null }
        $isHosted = [bool]($data -and $data.PSObject.Properties['isHosted'] -and $data.isHosted)
        [pscustomobject]@{
            Organization = if ($Resource.PSObject.Properties['organization']) { [string]$Resource.organization } else { $null }
            Name         = if ($Resource.PSObject.Properties['name']) { [string]$Resource.name } else { $null }
            Hosted       = $isHosted
        }
    }

    $projects = @(Select-ScoutDevOpsType 'devops/projects' | ForEach-Object { ConvertTo-ScoutDevOpsProject $_ })
    $pipelines = @(Select-ScoutDevOpsType 'devops/pipelines' | ForEach-Object { ConvertTo-ScoutDevOpsPipeline $_ })
    $repositories = @(Select-ScoutDevOpsType 'devops/repositories' | ForEach-Object { ConvertTo-ScoutDevOpsRepository $_ })
    $serviceConnections = @(Select-ScoutDevOpsType 'devops/serviceconnections' | ForEach-Object { ConvertTo-ScoutDevOpsServiceConnection $_ })
    $agentPools = @(Select-ScoutDevOpsType 'devops/agentpools' | ForEach-Object { ConvertTo-ScoutDevOpsAgentPool $_ })

    # `available`: an attempt was actually made (the switch was on, or a combined run already
    # made one) AND at least one Azure DevOps resource of ANY type came back. `-IncludeDevOps`
    # left off, no organization discoverable, and "no project access" everywhere all collapse
    # to the SAME unavailable signal on purpose -- a rule reading `devops.available == false`
    # never has to know which of the three happened, only that it must not score a zero.
    $available = $attempted -and (@($devopsResources).Count -gt 0)

    $devops = [pscustomobject]@{
        available          = [bool]$available
        attempted          = [bool]$attempted
        projects           = $projects
        pipelines          = $pipelines
        repositories       = $repositories
        serviceConnections = $serviceConnections
        agentPools         = $agentPools
        managedPools       = @($managedPools)
        devCenters         = @($devCenters)
        loadTesting        = @($loadTesting)
        chaosExperiments   = @($chaosExperiments)
        playwrightTesting  = @($playwrightTesting)
    }
    $Collect | Add-Member -NotePropertyName devops -NotePropertyValue $devops -Force
    return $Collect
}

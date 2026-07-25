#
# Module manifest for module 'AzureScout'
#
# Author: Kristopher Turner
#
# Created: 2026-02-22
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'AzureScout.psm1'

# Version number of this module.
ModuleVersion = '2.4.0'

# Supported PSEditions
CompatiblePSEditions = @('Core')

# ID used to uniquely identify this module
GUID = 'a0785538-fd96-4960-bf93-c733f88519e0'

# Author of this module
Author = 'Kristopher Turner'

# Company or vendor of this module
CompanyName = 'Hybrid Cloud Solutions'

# Copyright statement for this module
Copyright = '(c) 2026 Hybrid Cloud Solutions. All rights reserved.'

# Description of the functionality provided by this module
Description = 'AzureScout — discover, inventory, and assess everything in your Azure environment from one command. Run Invoke-AzureScout with no parameters for a guided wizard, or drive it with switches: by default it inventories Azure resources, Entra ID, and identity objects (Excel, JSON, Markdown, AsciiDoc); add -Assessment and it runs a read-only CAF/WAF landing-zone assessment, scoring the tenant against Cloud Adoption Framework design areas and Well-Architected pillars and producing Power BI, self-contained HTML, executive PowerPoint, and JSON/Excel evidence. See everything. Own your cloud. (Requires PowerShell 7 on PowerShell Core.)'

# Minimum version of the PowerShell engine required by this module
# AzureScout requires PowerShell 7+. Declaring this here makes Import-Module reject
# Windows PowerShell 5.1 (Desktop) cleanly and immediately, instead of the module
# loading and later crashing deep inside a strict-mode-sensitive code path (e.g. the
# Entra/Graph permission audit — see Invoke-AZTIPermissionAudit.ps1).
PowerShellVersion = '7.0'

# Name of the PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# DotNetFrameworkVersion = ''

# Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# ClrVersion = ''

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = ''

# Modules that must be imported into the global environment prior to importing this module
RequiredModules = @()

# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
# ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
# NestedModules = @()

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = @(
            #Public Jobs
            'Start-AZSCAdvisoryJob',
            'Start-AZSCPolicyJob',
            'Start-AZSCSecCenterJob',
            'Start-AZSCSubscriptionJob',
            'Wait-AZSCJob',

            #Public Diagram Functions
            'Build-AZSCDiagramSubnet',
            'Set-AZSCDiagramFile',
            'Start-AZSCDiagramJob',
            'Start-AZSCDiagramNetwork',
            'Start-AZSCDiagramOrganization',
            'Start-AZSCDiagramSubscription',
            'Start-AZSCDrawIODiagram',

            #Main Functions
            'Invoke-AzureScout',
            'Test-AZSCPermissions',

            #Guided setup wizard (AB#5541) -- what a bare Invoke-AzureScout opens
            'Start-AZSCWizard',

            #Assessment platform entry points (Epics AB#5023 / AB#5056, AB#5024)
            'Invoke-ScoutAssessment',
            'Test-ScoutPermission',

            #Unattended pipeline entry point (AB#5050)
            'Invoke-ScoutPipeline',

            #Analysis functions -- offline, never call Azure (AB#324/AB#325/AB#326)
            'Get-ScoutInventoryDrift',
            'Get-ScoutCostAnomaly',
            'Get-ScoutIacGap',

            #Assessment config load/save (AB#373/AB#374)
            'Import-ScoutConfig',
            'Export-ScoutConfig'
)

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = @()

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @()

# DSC resources to export from this module
# DscResourcesToExport = @()

# List of all modules packaged with this module
# ModuleList = @()

# List of all files packaged with this module
# FileList = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @('Azure','AzureScout','Discovery','Inventory','Assessment','CAF','WAF','WellArchitected','CloudAdoptionFramework','LandingZone','Governance','AZSC','EntraID','Resources','ARM','Graph','Reporting','Excel','PowerBI')

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/thisismydemo/azure-scout/blob/main/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://thisismydemo.cloud/azure-scout/'

        # A URL to an icon representing this module.
        IconUri = 'https://raw.githubusercontent.com/thisismydemo/azure-scout/main/docs/images/azurescout-icon.svg'

        # ReleaseNotes of this module
        ReleaseNotes = 'v2.4.0 -- One command, and a guided wizard. Inventory and assessment are now modes of a single Invoke-AzureScout rather than two separate cmdlets: Invoke-AzureScout -Assessment LandingZone runs the CAF/WAF assessment, and without -Assessment the command behaves exactly as before. -CollectOnly and -FromCollect moved onto Invoke-AzureScout too, and assessment mode now honours the inventory sign-in parameters (-TenantID, -DeviceLogin, -AppId/-Secret, certificate auth), which the standalone cmdlet never did -- it silently required a pre-existing Connect-AzAccount context. -OutputFormat widens from [string] to [string[]] so one run can request several renderers (-OutputFormat Html,Pptx); its ValidateSet grows from 8 to 15 values to span both modes, and asking for a format from the wrong mode now throws an error naming the switch you actually wanted instead of silently producing nothing. DEPRECATED: Invoke-ScoutAssessment still works and is still exported, but will be removed in v3.0.0 -- every parameter maps across unchanged except -OutputPath, which is -ReportDir on Invoke-AzureScout. NEW: running Invoke-AzureScout with no parameters in an interactive session opens a guided wizard -- it confirms or establishes the Azure sign-in, lets you pick the tenant when the account can see more than one, verifies the account holds the rights the run needs, then presents checklists for the run type, the resource categories or assessments, the report formats, and the report directory, with everything pre-selected so you uncheck what you do not want. The final step prints the equivalent one-line command. The wizard never fires in a non-interactive host -- CI runners, scheduled tasks, containers, and any session with redirected stdin fall straight through to the previous default full ARM inventory, so an existing bare Invoke-AzureScout in a pipeline cannot block on a prompt; -NoWizard forces that path at a terminal. Start-AZSCWizard is exported for on-demand use. FIXED: the documentation stated a PowerShell floor the module never had -- several pages claimed the inventory cmdlet ran on PowerShell 5.1+ and that only the assessment platform needed 7.0, when the manifest has always declared PowerShellVersion 7.0 with CompatiblePSEditions Core. KNOWN LIMITATION: inventory and assessment still collect their Azure data independently, so running both queries Azure twice. Full suite 1671 passed, 0 failed, 3 skipped. v2.3.0 — Collection hardening and external platform integrations. Run isolation (AB#331): every invocation gets its own run folder, so a rescan — or a scan of a second tenant — can no longer destroy the previous run''s ReportCache, DiagramCache, or report. -RunName names the folder, -Force restores the old overwrite-in-place behaviour, and Clear-AZSCCacheFolder -OlderThan <days> prunes aged runs. Cross-subscription context restore (AB#368): all five Set-AzContext loops now capture the caller''s context up front and restore it in a finally block, on both the normal and the error path. Post-login management group probe (AB#351): the visible count is reported at login, and an authorization failure names the exact role to assign instead of surfacing an hour later as a silently empty worksheet; the probe never aborts the run. Azure DevOps inventory (AB#327): -IncludeDevOps adds projects, pipelines, service connections, repositories, and agent pools across one or more organizations, in five new worksheets. Authentication reuses the current Azure sign-in by requesting an Entra token for the Azure DevOps resource, so no PAT is needed in the common case; -DevOpsPat covers a separate identity. The ADO Service Connections sheet cross-references every Azure Resource Manager connection against the subscriptions in scope, and flags connections still authenticating with a secret rather than workload identity federation. Every call is a GET — Azure Scout stays read-only. GitHub Action (AB#328): a composite action.yml ships at the repository root, so a workflow can generate an inventory with uses: thisismydemo/azure-scout@v2. Azure Automation Account (AB#343): the eight-step unattended setup guide that previously did not exist, plus two runbook fixes — blob uploads now pass -Force, without which the second scheduled run failed with "blob already exists", and the diagnostic log upload now tests $DebugPreference rather than $Debug.IsPresent, which is always null because -Debug is a common parameter. New documentation: Category Reference (every report section heading mapped to its category, aliases, collector folder, and module count), Validation Matrix (per-check automated vs live-tenant coverage for phases 5-21), Automation, GitHub Actions, and Azure DevOps. Full suite 1648 passed, 0 failed, 3 skipped. v2.2.0 — Report tiers, deeper analytics, hardened collectors. New report tiers: Word (.docx, Export-Word), an offline ECharts HTML dashboard (Export-EChartsDashboard), a dependency-free PDF (Export-Pdf), and a resources-only JSON evidence export (Export-JsonEvidence) -- all wired into Export-Report and Invoke-ScoutAssessment -OutputFormat. Excel gains visual dashboard tabs with pivot charts; the React report gains richer interactive visuals (topology, management-group hierarchy, KPI cards, a Governance section, drill-downs, search/filter, badges, tooltips) plus report.pbit generation. New offline analysis functions: Get-ScoutInventoryDrift (cross-run resource drift), Get-ScoutCostAnomaly (cost outlier detection), and Get-ScoutIacGap (Bicep/ARM-JSON coverage gaps) -- none of these call Azure. Collect layer gains IoT deep coverage (Device Provisioning Service + Digital Twins), tag-value aggregation, deeper Database/Analytics/IoT rule automation, and collector/pipeline resilience (per-subscription continue-on-error, management-group hints, an empty-data guard, and a HadErrors summary flag) plus live Write-ScoutProgress output. New Import-ScoutConfig/Export-ScoutConfig let you save and reload an assessment config (benchmark, rule patterns, rule overrides) as JSON, with a safe fallback to the built-in default. Also: a CI pipeline (ci.yml), a real (non-simulated) azure-inventory workflow, five v1 inventory bug fixes, draw.io merge/StrictMode repairs, and documented Entra Graph delegated scopes. v2.1.0 — Platform hardening. Native governance collector (Import-Governance) replaces the Azure Governance Visualizer dependency: management-group, policy-assignment, role-assignment, budget, and resource-lock data now come from Azure Resource Graph + ARM REST directly, so the ALZ benchmark needs only ARM Reader at the management-group root (no Microsoft Graph app permissions by default). New unattended one-command pipeline (Invoke-ScoutPipeline) for CI/cron with a machine-readable run summary and exit codes. New self-contained interactive React HTML report (-OutputFormat React) plus cross-run drift tracking (New/Resolved/Regressed deltas across runs). v2.0.1 — Point the Project Site link at the documentation site (thisismydemo.cloud/azure-scout). v2.0.0 — CAF/WAF Assessment Platform (major). Adds a read-only, three-layer assessment engine (collect.json -> findings.json -> report) on top of the v1 inventory tool: a declarative CAF/WAF rule engine (139 rules across 8 CAF design areas + 5 WAF pillars, dual scoring, prioritized gaps), an Azure Resource Graph collect layer, AzGovViz/Advisor/ARG ingest, an ALZ benchmark diff, and tiered reporting (Power BI, self-contained HTML, executive PowerPoint via the OpenXML SDK, plus Excel + JSON evidence). Per-domain analytics: every discovery category is an independently runnable, tagged assessment via Invoke-ScoutAssessment -Assessment <Category>. Runtime-verified offline (Pester) and against a live tenant. BREAKING: introduces the findings.json output contract and demotes Excel-first output to an evidence tier. Assessment features require PowerShell 7. Full inventory functionality from v1.0.0 is unchanged. See CHANGELOG.md for details.'

        # Prerelease string of this module
        # Prerelease = ''

        # Flag to indicate whether the module requires explicit user acceptance for install/update/save
        # RequireLicenseAcceptance = $false

        # External dependent modules of this module
        # ExternalModuleDependencies = @()

    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}


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
ModuleVersion = '2.5.3'

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
        ReleaseNotes = 'v2.5.3 -- A normal Azure response aborted the entire inventory run (AB#5633). A run against a real tenant died right after the API inventory phase with "The property ''ReservationRecomen'' cannot be found on this object." This was not a null-reference fault. Every src/*.ps1 sets Set-StrictMode -Version Latest at file scope and AzureScout.psm1 dot-sources them, so the whole module including the v1 inventory path runs strict, and under StrictMode member enumeration over a collection reports the property missing when the enumeration yields nothing at all -- which is exactly what an empty collection on every element produces, because the empties flatten away. A null value is safe; an empty one is not. The Consumption reservationRecommendations API returns { "value": [] } for a subscription with no recommendations, so a perfectly healthy tenant crashed the run. All seven reads at that site now go through Get-AZSCCollectedValue, which reads element-wise. The same class was swept: $Resources is a mixed array whose Resource Graph rows carry subscriptionId and Type while the REST rows beside them do not, and two collectors running in module scope filtered it with bare property reads -- Get-AZSCVMQuotas on $_.subscriptionId, which meant no quota was collected for any subscription rather than just the offending one, and Get-AZSCVMSkuDetails on $_.TYPE plus an -ExpandProperty over rows without a location. The ~176 inventory modules use the same filter shape safely because they run in fresh runspaces with StrictMode unset, and are unchanged. Diagram jobs never actually waited: Start-AZSCDiagramJob looped on $Job.Runspace.IsCompleted, but those handles are PowerShellAsyncResult and have no Runspace property, so the expression was empty, -contains $false was always false, and EndInvoke raced the work it was collecting; v2.5.2 fixed this same line in Start-AZSCProcessJob and missed this copy. An unavailable Cost Management API destroyed the whole run (AB#5636): Get-AZSCCostInventory ended its catch with throw and the $Costs = @() fallback on the next line was unreachable dead code, so a machine without Az.CostManagement lost the entire report to -IncludeCosts. Cost data is optional enrichment and now warns, naming the install command, and continues. Az.CostManagement is deliberately not auto-installed -- doing so drags in a newer Az.Accounts, and two side-by-side versions make every Import-Module die with a stack overflow inside Az.Accounts'' own assembly-load-context resolver. NEW: every run now writes a detailed log into its own run folder with no extra parameter (AB#5634, AB#5635). scout-run.log carries a metadata header, every phase boundary with elapsed time and counts, warnings, and on failure the full error record -- message, exception type, failing script, line number, statement and script stack trace; scout-console.log carries the console transcript. A failed run prints the log path before exiting. Logging is best-effort: if the log cannot be written the run still proceeds. It paid for itself immediately -- the Cost Management defect and both mixed-array collector crashes were found by reading the log rather than by re-running with -Debug. v2.5.2 -- A whole report category could silently vanish from a run (AB#5629). Inventory output was non-deterministic: ReportCache/Compute.json came back 5,158 bytes on one run and 470 on the next, same tenant and scope, with every Compute module reporting zero rows while the hashtable keys were still present. The cause was a race, not throttling: Wait-AZSCJob looped only while a job was Running, but Start-Job is asynchronous and a job created moments earlier sits in NotStarted, a state that satisfied neither the wait loop nor the caller job-selection filter, so it was never waited on and Build-AZSCCacheFiles then ran Receive-Job followed by Remove-Job, destroying it before it produced anything. Both now treat every non-terminal state as pending. Build-AZSCCacheFiles now warns when a job is harvested in a non-Completed state or a category returns no data, naming the category, instead of reporting an empty estate in silence. Also, Build-AZSCExcelComObject surfaced a raw 0x80040154 REGDB_E_CLASSNOTREG on every machine without Excel installed; the report is already complete and saved at that point, so the missing ProgID is now detected up front and explained in one line. v2.5.1 -- Seven fixes that let a full inventory run complete against a real tenant. Every one was found by running the product end to end against live Azure; the 1692-test suite passed throughout because nothing drove the extraction, processing and reporting chain against real collector output. Extraction: $MGContainerExtension was consumed unconditionally by the resourcecontainers query but only assigned in the -ManagementGroup branch (AB#5547). Processing: 41 .IsPresent reads on parameters not declared [switch] -- null when the caller omits them (AB#5547). Reporting (AB#5567): ImportExcel throws on a -Style range or -TableName over a worksheet with zero data rows; the cost and update-manager worksheets read VM property names the collector never emitted, so those sheets had never carried VM rows; 29 worksheet dereferences threw whenever the estate produced no such sheet; 10 pivot titles were read before assignment; and the Markdown export died on a trailing italic underscore parsed as part of the identifier. First live-tenant verification of the -IncludeDevOps collectors: 166 resources across 74 projects. Full history for every earlier release is in CHANGELOG.md: https://github.com/thisismydemo/azure-scout/blob/main/CHANGELOG.md'

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


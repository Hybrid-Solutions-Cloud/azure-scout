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
ModuleVersion = '2.9.0'

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
        ReleaseNotes = 'v2.9.0 -- The collectors become data, the module runs strict, and a blind spot in error reporting closes. Second wave of the engine rebuild (Epic AB#5638). DECLARATIVE COLLECTORS (AB#5659): 124 of 176 collectors are now .psd1 definitions rather than PowerShell, up from 13 -- AI 19, Monitor 17, Identity 16, Hybrid 14, Databases 13, Networking 12, Management 10, Compute 8, Analytics 5, Containers 4, and the rest. Every one is pinned by an equivalence test that runs the original imperative collector and the declarative definition over the same input, then compares the processed rows key-by-key in order AND the written .xlsx cell-by-cell, under both -IncludeTags states. Writing those tests found six interpreter defects that would otherwise have shipped: a field whose source is an if/else STATEMENT rather than an expression was silently unreachable, because ( ) takes a pipeline and $( ) unrolls a single-element array to a scalar -- expressions are now emitted unwrapped; per-loop preambles were dropped, so every local a fan-out loop computed came out null and Security/Vault lost all three permission columns while Networking/VirtualNetwork lost its entire subnet calculation; the tag loop was assumed universal and always named Tag, when 25 collectors have none and RouteTables uses a different name; resource-type matching was treated as a grouping where ArcSites needs arrival order; a filter preamble was dropped, so AppliedAIServices matched nothing and produced a silently empty sheet; and tag columns were defaulted on, adding columns to 10 Monitor sheets that no release has ever contained. Four collectors stay imperative for stated reasons and are pinned as test data so shortening that set is a visible edit. STRICTMODE (AB#5671, AB#5672): all 174 collectors now pass under Set-StrictMode -Version Latest, and the recorded baseline is empty because a run says so rather than aspirationally. Each conversion was proved real by running the collector twice with StrictMode off, before and after, and diffing emitted rows -- 20 of 23 are byte-identical, which is only possible by executing the row-emitting path. A CI guard, AST-parsed rather than grepped, now fails the build if Set-StrictMode is weakened anywhere in the module. Management/ManagementGroups was found NOT to be a StrictMode fault at all: it fails parameter binding on Get-AzManagementGroup -Expand -Recurse with no -GroupId, which is the long-standing missing mandatory parameters GroupName failure seen on every live run, finally explained. REPORTING (AB#5666): the ChartP6 pivot defect is root-caused and fixed. ImportExcel builds a pivot source range from the worksheet dimension, and a worksheet that EXISTS but holds no cells has a null dimension, so the range lookup threw, Add-PivotTable downgraded it to a warning, and the chart vanished with it. The existing guard tested existence rather than emptiness. All 30 call sites now check the dimension. FIXED, a real blind spot in shipped code: AB#402 non-terminating-error detection compared $Error.Count before and after a phase, but $Error is a fixed-size ring buffer, so once it saturates the count stops rising, the delta is permanently zero, and non-terminating errors stop being reported entirely -- silently, and precisely in the long runs where degraded datasets matter most. Demonstrated: with the buffer saturated and one new error raised, the old technique reports false. It now remembers the record at the front of $Error and counts by reference identity. Also fixed: a StrictMode conversion had changed an out-of-scope subscription name from null to an empty string, which made a single estate render two different blanks depending on which sheet you looked at -- the declarative equivalence proof caught it on 11 collectors, and it would have been invisible on the rest. DOCUMENTATION: github-actions, troubleshooting and validation-matrix all still told operators that chart customization drives Excel over COM and that lite mode is mandatory on hosted runners. v2.7.0 made that false, so those pages were actively pushing users to disable a working feature. KNOWN LIMITS, stated rather than buried: the equivalence fixtures are GENERATED by walking each definition AST, not recorded from a tenant, so they prove the two implementations agree on the same input -- they do not prove either is right about a real estate. The live pipeline still executes the imperative .ps1 for every collector; converting is not the same as using, and the cutover is staged separately. Of the 174 StrictMode passes, 146 emit zero rows because the recorded capture covers only 32 resource types, so those passes are real but weak; exact row counts are now pinned for the 25 meaningfully exercised collectors. Live-verified: 4:52, 124 resources, 438 Excel rows, 42 worksheets, 464 security advisories, zero leftover background jobs. v2.8.0 -- Collection actually happens once. A default assessment collect now issues 4 Azure Resource Graph queries instead of 35 (AB#5648, Epic AB#5638). v2.7.0 shipped the single-pass collection functions but nothing called them -- outside tests the only reference to any of them was a comment -- so the round-trip count was unchanged. They are now the real path. Both numbers were re-derived by counting invocations against a stub in place of Search-AzGraph, and both are pinned by hard count assertions in tests/Collect.SinglePassInversion.Tests.ps1, because a query count with no test regresses silently within a release. It is 4 rather than 1 for stated reasons: three raw tables (resourcecontainers, resources, networkresources) plus sqlDefenderPricing, which reads SecurityResources and genuinely cannot be served from inventory. The inventory extraction path stays at 8 queries because those are eight DISTINCT ARG tables -- resourcecontainers, resources, networkresources, SupportResources, recoveryservicesresources, desktopvirtualizationresources, advisorresources and retirements -- not filters over one table; merging them would drop datasets. What changed there is ownership rather than count: one paging implementation instead of two. Modules/Private/Extraction/Invoke-AZTIInventoryLoop.ps1 -- the legacy paging, batching and retry engine -- is DELETED, and a test asserts both that the file is absent and that no AST command node anywhere in Modules/ or src/ still calls it. Start-AZTIGraphExtraction is reduced to a shim that builds no query text and issues no ARG call; its resource-group, tag and management-group filter clauses moved into Get-ScoutRawInventory reproducing the legacy if/elseif precedence exactly, each with its own test. FIXED, and it would have shipped as a blank report section invisible to 2144 passing tests: the raw pass omits the tags column unless asked, while the collect contract aggregates its top-level tags key from subscriptions[*].tags, so the inverted path returned an empty tags array for every estate. The internal raw call now requests tags, with a regression test. STATED TRADE-OFFS, not yet measured: the raw pass carries the full properties bag where the typed queries carried narrow projections, so on a large estate the number of 1000-row pages can rise even as the query count falls; and -Categories no longer reduces what is fetched, only what is shaped. Use -Source TypedQueries as the escape hatch for a narrow single-category collect -- that path is unchanged at 35 queries and remains fully supported. STILL NOT DONE, deliberately not claimed: the non-ARG half of AB#5648. Get-ScoutApiResources, Get-ScoutVmQuotas, Get-ScoutVmSkuDetails and Get-ScoutCostInventory remain dead code, and a live run still uses the v1 implementations for ARM REST resources, VM quota and SKU lookups, and Cost Management. The round-trip numbers above say nothing about those. Live-verified against a real tenant: 5:11 runtime, 124 resources, 438 Excel rows, 42 worksheets, 452 security advisories, zero leftover background jobs, and one collector failing (Management/ManagementGroups, an environment and permissions issue rather than a code defect). Full history for every earlier release is in CHANGELOG.md: https://github.com/thisismydemo/azure-scout/blob/main/CHANGELOG.md'

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


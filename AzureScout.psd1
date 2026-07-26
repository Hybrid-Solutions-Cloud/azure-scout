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
ModuleVersion = '2.10.0'

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
        ReleaseNotes = 'v2.10.0 -- The declarative collectors actually run, and the non-ARG collection half is inverted. Epic AB#5638. THE CUTOVER (AB#5656): v2.9.0 shipped 124 of 176 collectors as .psd1 definitions, but nothing called the interpreter -- the live pipeline still executed the imperative .ps1 for every collector, so the conversion delivered nothing to a user. It now routes on the HasDeclarativeDefinition and DefinitionPath that Get-ScoutCollector already reported: definition present goes to the interpreter, absent goes to the .ps1. No second discovery mechanism was added. Verified against a live tenant, the run log now reports 124 declarative and 50 imperative collectors, with 2 skipped. Proving this needed a different technique than the conversion did: a row comparison can never detect a routing regression, because both paths agree by construction. The proof is by impossibility instead -- a fixture collector has a valid definition and a .ps1 whose entire processing branch is a throw, and the run completes with its row present; with the kill switch on, the same fixture fails with that exact message, so the switch cannot pass on a sentinel string alone. Asserted both through the collector entry point and end to end through the ReportCache JSON. A full processing pass over an 845-resource estate produced identical output with the switch on and off: 1654 rows either way, zero collector-level deltas, and byte-identical ReportCache JSON by hash. KILL SWITCH: AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS set to 1, true, yes or on forces every collector down the imperative path. It is an environment variable rather than a parameter so it works on an already-installed build with nothing threaded through Invoke-AzureScout; Invoke-ScoutProcessing -ForceImperativeCollectors is the programmatic form. A definition that fails schema validation falls back to its .ps1 with a warning; an execution failure does not fall back, it stays contained and reported as before. THE NON-ARG HALF (AB#5648, AB#5639): the four collection functions shipped in v2.7.0 and left dead in v2.8.0 -- Get-ScoutApiResources, Get-ScoutVmQuotas, Get-ScoutVmSkuDetails and Get-ScoutCostInventory -- are now the real path. The v1 ARM REST, VM quota and SKU, and Cost Management implementations are retired to shims, proven by AST tests asserting that no file under Modules calls Invoke-RestMethod, Get-AzAccessToken, Get-AzVMUsage, Get-AzComputeResourceSku or Invoke-AzCostManagementQuery outside a two-file allow-list, and that each cmdlet has exactly one call site under src. Equivalence was checked per dataset against the v1 bodies driven over identical stubbed responses, comparing key sets, values and the REST call sequence in order. FIXED, two shape regressions caught by that comparison and both introduced by an @() that looked like hardening: CostData wrapped in an array meant Get-ScoutCostAnomaly, which reads the raw shape through PSObject.Properties, would have produced zero records with no error at all; and returning a collection member unrolled single-element arrays, so every endpoint answering with exactly one row changed shape. FIXED: Management/ManagementGroups no longer fails the run. Its earlier try/catch stopped the crash but left the fallback returning nothing on every run, so that worksheet was empty for any tenant whose root management group id is not the tenant id. It now enumerates without switches, expands each group by id, and keeps only roots so subtrees are not rendered twice; six tests assert on the calls made, because not throwing was already true while it produced no rows. NOTE that a tenant still needs Management Group Reader at the root -- without Microsoft.Management/register/action the collector returns zero rows by design rather than failing. This was the only collector failing on every live run, and this release is the first with zero collector failures. NOT DONE, stated rather than implied: reporting is not cut over. Start-AZSCExcelJob still executes each collector''s .ps1 reporting branch because it walks the module directory with its own duplicate discovery, so every definition''s Export section is still exercised only by tests. Mixing the two is safe because the equivalence suite compares the written workbook cell by cell, not because it is assumed. Live-verified: 6:37, 136 resources, 481 Excel rows, 43 worksheets, 503 security advisories, zero leftover background jobs, zero collector failures. v2.9.0 -- The collectors become data, the module runs strict, and a blind spot in error reporting closes. Second wave of the engine rebuild (Epic AB#5638). DECLARATIVE COLLECTORS (AB#5659): 124 of 176 collectors are now .psd1 definitions rather than PowerShell, up from 13 -- AI 19, Monitor 17, Identity 16, Hybrid 14, Databases 13, Networking 12, Management 10, Compute 8, Analytics 5, Containers 4, and the rest. Every one is pinned by an equivalence test that runs the original imperative collector and the declarative definition over the same input, then compares the processed rows key-by-key in order AND the written .xlsx cell-by-cell, under both -IncludeTags states. Writing those tests found six interpreter defects that would otherwise have shipped: a field whose source is an if/else STATEMENT rather than an expression was silently unreachable, because ( ) takes a pipeline and $( ) unrolls a single-element array to a scalar -- expressions are now emitted unwrapped; per-loop preambles were dropped, so every local a fan-out loop computed came out null and Security/Vault lost all three permission columns while Networking/VirtualNetwork lost its entire subnet calculation; the tag loop was assumed universal and always named Tag, when 25 collectors have none and RouteTables uses a different name; resource-type matching was treated as a grouping where ArcSites needs arrival order; a filter preamble was dropped, so AppliedAIServices matched nothing and produced a silently empty sheet; and tag columns were defaulted on, adding columns to 10 Monitor sheets that no release has ever contained. Four collectors stay imperative for stated reasons and are pinned as test data so shortening that set is a visible edit. STRICTMODE (AB#5671, AB#5672): all 174 collectors now pass under Set-StrictMode -Version Latest, and the recorded baseline is empty because a run says so rather than aspirationally. Each conversion was proved real by running the collector twice with StrictMode off, before and after, and diffing emitted rows -- 20 of 23 are byte-identical, which is only possible by executing the row-emitting path. A CI guard, AST-parsed rather than grepped, now fails the build if Set-StrictMode is weakened anywhere in the module. Management/ManagementGroups was found NOT to be a StrictMode fault at all: it fails parameter binding on Get-AzManagementGroup -Expand -Recurse with no -GroupId, which is the long-standing missing mandatory parameters GroupName failure seen on every live run, finally explained. REPORTING (AB#5666): the ChartP6 pivot defect is root-caused and fixed. ImportExcel builds a pivot source range from the worksheet dimension, and a worksheet that EXISTS but holds no cells has a null dimension, so the range lookup threw, Add-PivotTable downgraded it to a warning, and the chart vanished with it. The existing guard tested existence rather than emptiness. All 30 call sites now check the dimension. FIXED, a real blind spot in shipped code: AB#402 non-terminating-error detection compared $Error.Count before and after a phase, but $Error is a fixed-size ring buffer, so once it saturates the count stops rising, the delta is permanently zero, and non-terminating errors stop being reported entirely -- silently, and precisely in the long runs where degraded datasets matter most. Demonstrated: with the buffer saturated and one new error raised, the old technique reports false. It now remembers the record at the front of $Error and counts by reference identity. Also fixed: a StrictMode conversion had changed an out-of-scope subscription name from null to an empty string, which made a single estate render two different blanks depending on which sheet you looked at -- the declarative equivalence proof caught it on 11 collectors, and it would have been invisible on the rest. DOCUMENTATION: github-actions, troubleshooting and validation-matrix all still told operators that chart customization drives Excel over COM and that lite mode is mandatory on hosted runners. v2.7.0 made that false, so those pages were actively pushing users to disable a working feature. KNOWN LIMITS, stated rather than buried: the equivalence fixtures are GENERATED by walking each definition AST, not recorded from a tenant, so they prove the two implementations agree on the same input -- they do not prove either is right about a real estate. The live pipeline still executes the imperative .ps1 for every collector; converting is not the same as using, and the cutover is staged separately. Of the 174 StrictMode passes, 146 emit zero rows because the recorded capture covers only 32 resource types, so those passes are real but weak; exact row counts are now pinned for the 25 meaningfully exercised collectors. Live-verified: 4:52, 124 resources, 438 Excel rows, 42 worksheets, 464 security advisories, zero leftover background jobs. Full history for every earlier release is in CHANGELOG.md: https://github.com/thisismydemo/azure-scout/blob/main/CHANGELOG.md'

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


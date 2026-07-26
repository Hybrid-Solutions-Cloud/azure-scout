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
ModuleVersion = '2.11.0'

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
        ReleaseNotes = 'v2.11.0 -- 138 of 176 collectors are declarative, and the definitions are gated in CI. CORRECTION: this previously read "Epic AB#5638 completes". It does not -- the epic was closed without meeting its acceptance criteria and has been reopened. Everything below shipped, but Modules/ still holds 221 .ps1 files (its stated end state is deletion), 176 collector .ps1 remain, 138 of 176 are declarative, 20 Set-StrictMode weakening sites remain (4 live), and reporting is not cut over. THE JOIN COLLECTORS (AB#5659): the audit had classified 20 cross-resource-join collectors as escape-hatch, alongside the ones making live cmdlet calls. Re-examining all 48 escape-hatch collectors showed the audit reasons were accurate but the inference was not: a cross-resource join is not the same thing as a live cmdlet call. Every one of those 20 filters the already-collected resource set a second time for another type and correlates against the result -- data shaping over data the pipeline already holds. The only missing capability was somewhere to put statements that run once, before the row loop. Two schema keys were added: SetupPreamble, the contiguous verbatim source above the row loop, and SetupVariables, the names it exports. Names are DECLARED rather than harvested, because harvesting sweeps up automatic variables, and because a preamble that stopped assigning a variable would otherwise silently stop binding it. The interpreter throws on any declared name it cannot resolve, and the loader rejects either key without the other. Fourteen collectors converted on that basis, taking the total from 124 to 138, each proven by the existing equivalence gate -- rows key by key in order, and the written workbook cell by cell, under both tag modes. HONEST LIMIT, stated because it is the weakest part of this release: all 14 agree with the imperative collector row for row, but the generated estate only makes the join itself change the output for 5 of them. For the other 9 the join partners are present and both paths agree while both take the not-found branch. That is a fixture limitation rather than a conversion defect, and each of the 9 is pinned by name with the specific predicate that defeats the fixture generator -- a reverse-direction identity comparison, an accessor-call predicate, a containment test against a member-enumerated array, a secondary set whose own filter drops the partner. A test removes the partners from the estate and asserts the output changes, and it fails both on an unlisted collector and on a stale entry, so that list can only shorten. DEFINITIONS GATED IN CI (AB#5661): a validator runs as its own step before the test suite, so a violation annotates the offending definition in the pull-request diff rather than surfacing as an empty worksheet at runtime. Seven checks: the definition parses and satisfies the schema; the generated row script parses, which is the if-else-statement-as-field class that was silently unreachable before; every preamble parses on its own; every exported column resolves to a declared field, with the five known blank columns allow-listed by name and reason so that a sixth fails the build AND a fixed one also fails, meaning the list can only shorten; every declared setup variable is statically assigned by its preamble; the source collector exists; and drift -- regenerating the definition from its source collector must reproduce the file byte for byte. That last check exists because a definition had already drifted from its collector for a release while its equivalence test stayed green, since with StrictMode off the stale and current property accessors agreed on the fixture. Nothing in the repository could have caught it. The gate is proven to fail rather than assumed to: thirteen tests each write one deliberately broken definition and assert both a non-zero exit and that the message names the fault, after first asserting that a correct definition passes so the failure assertions are not vacuous. FIXED, pre-existing: the conversion tool could never have converted the App Service Plan collector correctly, because it treated every filtered assignment as a row source -- that collector''s secondary filter would have been lifted onto the row set itself, silently dropping every app service plan; a definition that had drifted since the StrictMode hardening was regenerated; the fixture generator was not reproducible between processes, because unordered hashtable enumeration made every regeneration produce a spurious difference; the fixture writer emitted case-variant duplicate JSON keys; and shape resolution had no pipeline pass-through, so a join partner was synthesised carrying only the properties its own predicate mentioned, leaving every joined column null on BOTH paths and therefore passing equivalence. Live-verified: 5:37, 136 resources, 481 Excel rows, 514 security advisories, zero leftover background jobs, zero collector failures, and the run log reporting 138 declarative and 36 imperative collectors. STILL IMPERATIVE, 38 with specific reasons: those calling Invoke-AzRestMethod inside the row loop, those making live Get-Az calls with no resource-type filter to drive the interpreter, three whose row shape or loop depth is conditional, one whose row loop iterates a synthesised set with no type to declare, and two written against a registration contract that only ever existed as a test mock. No second escape hatch was invented -- not having a definition remains it. NOT DONE: reporting is still not cut over. The Excel job executes each collector''s own reporting branch through its own duplicate discovery, so every definition''s export section is exercised only by tests. v2.10.0 -- The declarative collectors actually run, and the non-ARG collection half is inverted. Epic AB#5638. THE CUTOVER (AB#5656): v2.9.0 shipped 124 of 176 collectors as .psd1 definitions, but nothing called the interpreter -- the live pipeline still executed the imperative .ps1 for every collector, so the conversion delivered nothing to a user. It now routes on the HasDeclarativeDefinition and DefinitionPath that Get-ScoutCollector already reported: definition present goes to the interpreter, absent goes to the .ps1. No second discovery mechanism was added. Verified against a live tenant, the run log now reports 124 declarative and 50 imperative collectors, with 2 skipped. Proving this needed a different technique than the conversion did: a row comparison can never detect a routing regression, because both paths agree by construction. The proof is by impossibility instead -- a fixture collector has a valid definition and a .ps1 whose entire processing branch is a throw, and the run completes with its row present; with the kill switch on, the same fixture fails with that exact message, so the switch cannot pass on a sentinel string alone. Asserted both through the collector entry point and end to end through the ReportCache JSON. A full processing pass over an 845-resource estate produced identical output with the switch on and off: 1654 rows either way, zero collector-level deltas, and byte-identical ReportCache JSON by hash. KILL SWITCH: AZURESCOUT_FORCE_IMPERATIVE_COLLECTORS set to 1, true, yes or on forces every collector down the imperative path. It is an environment variable rather than a parameter so it works on an already-installed build with nothing threaded through Invoke-AzureScout; Invoke-ScoutProcessing -ForceImperativeCollectors is the programmatic form. A definition that fails schema validation falls back to its .ps1 with a warning; an execution failure does not fall back, it stays contained and reported as before. THE NON-ARG HALF (AB#5648, AB#5639): the four collection functions shipped in v2.7.0 and left dead in v2.8.0 -- Get-ScoutApiResources, Get-ScoutVmQuotas, Get-ScoutVmSkuDetails and Get-ScoutCostInventory -- are now the real path. The v1 ARM REST, VM quota and SKU, and Cost Management implementations are retired to shims, proven by AST tests asserting that no file under Modules calls Invoke-RestMethod, Get-AzAccessToken, Get-AzVMUsage, Get-AzComputeResourceSku or Invoke-AzCostManagementQuery outside a two-file allow-list, and that each cmdlet has exactly one call site under src. Equivalence was checked per dataset against the v1 bodies driven over identical stubbed responses, comparing key sets, values and the REST call sequence in order. FIXED, two shape regressions caught by that comparison and both introduced by an @() that looked like hardening: CostData wrapped in an array meant Get-ScoutCostAnomaly, which reads the raw shape through PSObject.Properties, would have produced zero records with no error at all; and returning a collection member unrolled single-element arrays, so every endpoint answering with exactly one row changed shape. FIXED: Management/ManagementGroups no longer fails the run. Its earlier try/catch stopped the crash but left the fallback returning nothing on every run, so that worksheet was empty for any tenant whose root management group id is not the tenant id. It now enumerates without switches, expands each group by id, and keeps only roots so subtrees are not rendered twice; six tests assert on the calls made, because not throwing was already true while it produced no rows. NOTE that a tenant still needs Management Group Reader at the root -- without Microsoft.Management/register/action the collector returns zero rows by design rather than failing. This was the only collector failing on every live run, and this release is the first with zero collector failures. NOT DONE, stated rather than implied: reporting is not cut over. Start-AZSCExcelJob still executes each collector''s .ps1 reporting branch because it walks the module directory with its own duplicate discovery, so every definition''s Export section is still exercised only by tests. Mixing the two is safe because the equivalence suite compares the written workbook cell by cell, not because it is assumed. Live-verified: 6:37, 136 resources, 481 Excel rows, 43 worksheets, 503 security advisories, zero leftover background jobs, zero collector failures. Full history for every earlier release is in CHANGELOG.md: https://github.com/thisismydemo/azure-scout/blob/main/CHANGELOG.md'

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


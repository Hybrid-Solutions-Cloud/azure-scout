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
ModuleVersion = '2.7.0'

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
        ReleaseNotes = 'v2.7.0 -- Second phase of the engine rebuild (Epic AB#5638): the reporting layer moves out of Modules/, Excel COM is gone entirely, the first collector category becomes declarative data, and a single-pass collection layer lands. REPORTING (AB#5662): all 26 inventory report renderers moved from Modules/Private/Reporting/ to src/report/renderers/inventory/ and src/report/renderers/inventory/style/, renamed so the file name matches the function it defines -- the legacy AZTI-file / AZSC-function mismatch is gone. Function names are unchanged, so no call site changed behaviour. Build-AZTIExcelComObject.ps1 is DELETED: chart styling now runs on EPPlus/ImportExcel only, through the new Build-AZSCExcelChartStyle. Excel COM was why -Lite defaulted to true and why the module surfaced a raw 0x80040154 REGDB_E_CLASSNOTREG on every machine and CI runner without Excel installed; no live COM call remains anywhere in src/, Modules/ or tests/. Verified against a live tenant: a 42-worksheet workbook built with no Excel present, SecurityCenter carrying 489 rows. NOTE: the EPPlus chart styling is an approximation of the former COM styling, documented in the function .NOTES. DECLARATIVE COLLECTORS (AB#5656): the 13 Databases collectors are now data -- manifests/collectors/Databases/*.psd1 -- interpreted at runtime by Invoke-ScoutDeclarativeCollector, with Get-ScoutCollector extended to report HasDeclarativeDefinition and DefinitionPath rather than adding a second discovery mechanism. Each definition is pinned by an equivalence test that runs the original imperative collector and the declarative definition over the same input and compares the processed rows key-by-key and the written .xlsx cell-by-cell, under both -IncludeTags states. Writing that test found two defects in the interpreter that would have silently changed shipped reports: tag columns were appended rather than inserted, so every tagged worksheet came out with its last three columns reordered (all 13 collectors add their trailing column after the tag block); and ResourceTypes was applied as a membership test rather than a grouping, so RedisCache lost the ordering its original produced by concatenating redis then redisenterprise. Both are fixed, and a definition naming a column that does not exist is now a load-time error rather than a silent fallback. An AST audit of all 176 collectors ships as docs/design/collector-audit.md: 115 of the remaining 163 are mechanically convertible, 48 stay hand-written (29 make live cmdlet calls, 20 do cross-resource joins, 10 never filter $Resources, 2 are unimplemented). COLLECTION (AB#5639): src/collect/ gains Get-ScoutRawInventory, Get-ScoutApiResources, Get-ScoutCostInventory, Get-ScoutVmQuotas and Get-ScoutVmSkuDetails, plus an AST-derived resource-type map covering 128 ARM types, 17 cognitive-services kinds and the VM quota/SKU pseudo-types. One raw pass satisfies 34 of the 35 collect queries; sqlDefenderPricing reads SecurityResources and genuinely cannot be served from inventory. THIS IS CAPABILITY ONLY -- nothing in the product calls these functions yet, so the run still reaches Resource Graph as many times as it did in v2.6.0. Inverting the pipeline onto this layer is AB#5648 and is not in this release. Do not read this entry as "collection is now single-pass"; it is not. FIXED: an unbound [string[]] parameter is $null and @($null).Count is 1, not 0, so the subscription-resolution branch in Invoke-Collect gated on .Count -eq 0 never fired on the default path -- the subscription list was never derived from resourcecontainers and every later table degraded to one un-batched tenant-wide call with none of the documented per-batch isolation. The existing test passed either way because it asserted only the container count; the regression test now asserts the actual -Subscription argument. This is the same @($null).Count class that emptied the Excel loop in v2.6.0. KNOWN, UNCHANGED: Management/ManagementGroups fails on every live run with "missing mandatory parameters: GroupName" -- environment and permissions, not a code defect. RedisCache exports a blank Resource Group column and SQLMI a blank ActiveDirectoryOnlyAuthentication column, both blank in every shipped release; the declarative definitions reproduce them faithfully rather than diverge from the imperative path. Identity/IdentityProviders and Identity/SecurityDefaults are still written against a registration API that exists only as a test mock and have never produced a row. v2.6.0 -- The inventory engine no longer uses background jobs. First phase of the engine rebuild. Processing used to create one Start-Job per category, each of which created one [PowerShell]::Create() runspace per collector, then Wait-AZSCJob waited and Build-AZSCCacheFiles harvested and destroyed them. Every defect of the v2.5.x wave lived in that coordination rather than in the collectors: Start-Job is asynchronous so a NotStarted job was excluded from the wait, harvested empty and deleted, taking its whole category out of the report with no trace; the inner wait read $Job.Runspace.IsCompleted, but PowerShellAsyncResult has no Runspace property so the loop never waited and EndInvoke raced its own work; each job re-imported the module, re-applying module-scope StrictMode inside the job and forcing the v2.5.3 opt-out to 17 entry points; category ordering came from Get-Job, so the same tenant produced different reports on consecutive runs; and the whole estate was serialised through ConvertTo-Json -Depth 40 once per category. Collectors are pure functions of the resource set, so none of that concurrency was ever required. All 176 now run in-process in a fixed order through Invoke-ScoutProcessing, writing the same ReportCache layout. Identical input produces an identical report cache, and each collector failure is contained individually so one bad collector no longer empties its category or aborts the batch. Verified against a live tenant: two consecutive full runs compared collector-section by collector-section produced 32 sections with 31 byte-identical; the single difference was checked against Resource Graph and was the estate genuinely changing between runs. The -Automation processing branch is gone -- it only substituted Start-ThreadJob where Start-Job was unavailable, so both modes now execute identical code. The draw.io lookup collapsed too: Start-AZSCDiagramJob was 290 lines that filtered resources by 27 types using 27 separate runspaces, and is now one bucket-sorting pass. Wait-AZSCJob has been deleted; the run orchestration starts no background jobs at all. FIXED, all pre-existing and all invisible until collectors ran in-process: the Security Center worksheet has been EMPTY in every release that had one, because Invoke-AZSCSecurityCenterJob was called with -SecurityCenter against a parameter block that declared no such parameter -- PowerShell does not reject an unknown named argument to a simple function, it collects it into $args and carries on, so $null crossed the job boundary as the -Security argument and the loop iterated nothing; it now carries real data (484 rows on the verification tenant). Five collectors -- Monitor/SubscriptionDiagnosticSettings and the four Security/Defender ones -- called Write-AZSCLog with -Color and -Level Verbose, neither of which the function accepted, so each threw on its first log line and produced nothing. Per-file .CATEGORY filtering had never matched a single file, because the expression required a line break between the keyword and its value while all 176 collectors write it on one line. The Excel report loop invoked every collector whether or not it had data, because it counted rows with @($SmaResources).count and @($null).Count is 1, not 0. All four report exporters read $CacheData.$ModName unguarded, which throws under StrictMode when the cache has no entry for that collector. KNOWN LIMITATION: Identity/IdentityProviders and Identity/SecurityDefaults are written against a registration API that exists only as a mock inside the test suite and was never implemented, so they have never produced a row; they are now reported as skipped rather than executed. v2.5.3 -- A normal Azure response aborted the entire inventory run (AB#5633). A run against a real tenant died right after the API inventory phase with "The property ''ReservationRecomen'' cannot be found on this object." This was not a null-reference fault. Every src/*.ps1 sets Set-StrictMode -Version Latest at file scope and AzureScout.psm1 dot-sources them, so the whole module including the v1 inventory path runs strict, and under StrictMode member enumeration over a collection reports the property missing when the enumeration yields nothing at all -- which is exactly what an empty collection on every element produces, because the empties flatten away. A null value is safe; an empty one is not. All seven reads at that site now go through Get-AZSCCollectedValue, which reads element-wise. The same class was swept: $Resources is a mixed array whose Resource Graph rows carry subscriptionId and Type while the REST rows beside them do not, and two collectors filtered it with bare property reads -- Get-AZSCVMQuotas on $_.subscriptionId, which meant no quota was collected for any subscription rather than just the offending one, and Get-AZSCVMSkuDetails on $_.TYPE. An unavailable Cost Management API destroyed the whole run (AB#5636): Get-AZSCCostInventory ended its catch with throw and the $Costs = @() fallback on the next line was unreachable, so a machine without Az.CostManagement lost the entire report to -IncludeCosts. Cost data is optional enrichment and now warns and continues. Az.CostManagement is deliberately not auto-installed -- doing so drags in a newer Az.Accounts, and two side-by-side versions make every Import-Module die with a stack overflow inside Az.Accounts'' own assembly-load-context resolver. NEW: every run writes a detailed log into its own run folder with no extra parameter (AB#5634, AB#5635). scout-run.log carries a metadata header, every phase boundary with elapsed time and counts, warnings, and on failure the full error record with failing script, line, statement and script stack trace. Full history for every earlier release is in CHANGELOG.md: https://github.com/thisismydemo/azure-scout/blob/main/CHANGELOG.md'

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


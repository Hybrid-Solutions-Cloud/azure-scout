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
ModuleVersion = '3.6.0'

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
            # Invoke-AzureScout is the supported assessment entry point.
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
        ReleaseNotes = 'v3.6.0 - The collector-payload wiring audit, closed out. Nearly 100 collector manifests existed, were fully tested, and produced Excel-only rows - but never reached the assessment collect (collect.json) the React report actually renders from. This release closes that gap: 95 collectors wired across Networking, Hybrid, Monitor, Defender, Databases, DevOps, Management, Security, Storage, and Update Manager categories (coverage moves from 77 to 172 of 245 tracked manifests), plus 3 genuinely new collectors authored from scratch for services that had none - Microsoft Entra Verified ID and Microsoft Entra External ID (the governance/landing-zone-relevant one), both Graph-backed rather than ARM/ARG. Along the way, a real defect in the test suite''s own infrastructure was found and fixed: a shared mock-cleanup idiom silently no-opped, letting mock state leak across test files - corrected everywhere it appeared, restoring a genuinely clean full test run. v3.5.1 - Three things v3.5.0 said were fine. Every one was found by USING the product rather than reading the test results. (1) The wizard offered every report format except the one it renders: choosing both inventory and assessment - the commonest path there is - fell through to the inventory-only format list, which contains no React at all. An assessment run now offers React (the deliverable, and the default) plus Json/JsonEvidence; a menu-honesty test fails if the product is ever again asked to promise what it will decline to produce. (2) One tenant in eight could not render at all: dotted member enumeration over an EMPTY collection resolves against the array object rather than its zero elements, so a tenant with management groups but no policy assignments threw and produced no report; rewritten with ForEach-Object, and all eight banked corpus tenants now render. (3) The diagram-overlap gate was green because it inspected nothing: the fixture builder wrote flat keys while the real payload uses dotted paths, so every diagram hit its empty-data guard; the fixture now emits the payload''s own key shape and the gate was proved to fail on a manufactured overlap. v3.5.0 - The report is a product, not a page: the React report became a multi-page application - Overview, Inventory & audit (18-category blade view with every collector listed including zeros, filter/sort item tables, tenant structure, audit callouts and a full cost-optimization blade), Assessments (a complete conformance register per assessment), Diagrams (management-group hierarchy, VNet and subnet IP utilization, full-screen zoom), Data & drift, and Remediation plan - with Executive/Consultant/Data as a depth toggle, Markdown and JSON exports, and conformance clause R-04 enforced so the renderer no longer re-invokes the scoring engine. All other assessment report formats remain on hold. See CHANGELOG.md for the full history.'

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


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
ModuleVersion = '3.8.0'

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
        ReleaseNotes = 'v3.8.0 - One taxonomy, no broken scripts. The 12 legacy assessment registry keys join the source-anchored naming: LandingZone becomes ''CAF: Azure Landing Zone''; CASA, DevOps Capability Assessment, SMART and FinOps Review become ''Microsoft: *''; Cost, CrossResource, Monitoring, UpdateManager and Governance become ''Scout: *''; the AVS pair becomes ''Workload: *''. Every old name keeps working through an alias map with a one-time deprecation warning - ''-Assessment LandingZone'' still runs the same assessment - pinned by a dedicated backward-compatibility test suite. Wizard defaults, internal defaults and the documentation move to the new names. v3.7.0 - The network picture, completed. The assessment collect gains the networking relationship data the diagrams were starving for: vnetPeerings (remote VNet named, peering state, gateway-transit flags), vpnConnections (sharedKeyPresent as a bool only - the pre-shared key value is never collected), localNetworkGateways, virtualHubs, and richer expressRouteCircuits, routeTables (a forced-tunnel 0.0.0.0/0 route is detectable from a scalar), loadBalancers, applicationGateways (wafEnabled), frontDoors, trafficManagerProfiles, natGateways and bastionHosts - both collect paths produce identical shapes, gated by two new plumbing test suites. The VNet connectivity diagram draws real peering-pair edges; the hybrid diagram gains per-connection detail, an ExpressRoute lane and Virtual WAN hubs; two new diagrams land: Edge & delivery and Routing & forced tunnelling. The wizard''s 46-entry assessment menu is grouped under CAF / WAF / Specialized reviews / Service category deep-dives without renaming a single registry key. v3.6.1 - Four field defects from one live session, every one reported by the owner running the shipped module. (1) The Graph token now targets the tenant being audited instead of az CLI''s ambient default: on a multi-tenant identity the Entra ID P2 licence check read a different tenant''s subscribedSkus and reported a licensed tenant as NOT LICENSED; -TenantID is threaded through the token helper (per-tenant token cache), the Graph request wrapper, and every Graph call in the permission audit. (2) A combined Inventory+Assessment run writes ONE output folder: the deferred assessment''s OutputPath was captured before the timestamped run folder existed, so the React report - the only renderer that path produces - landed in a sibling folder the operator was never told about. (3) The permission audit now decodes its own token''s scp claim: scopes Azure CLI can never acquire (Policy.Read.AuthenticationMethod, VerifiedId-Profile.Read.All) are reported as UNAVAILABLE WITH CLI SIGN-IN with service-principal remediation instead of DENIED advice that fails a Global Administrator identically - proven live by decoding a real az token and reproducing the 403. (4) The four approved network diagrams - VNet hub-and-spoke with no-peering warnings, hybrid site-to-site with a single-instance gateway warning, private link and DNS, internet exposure - are ported from the approved mockup into the shipping React report''s diagram kernel with sidebar, tiles, panes and overlap-gate coverage; the port caught a wrong node CSS class that hid the diagrams from the collision gate and a gate shape mismatch that made it inspect nothing. See CHANGELOG.md for the full history.'

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


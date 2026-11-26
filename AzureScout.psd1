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
ModuleVersion = '3.18.19'

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
Description = 'AzureScout — discover, inventory, and assess everything in your Azure environment from one command. Run Invoke-AzureScout with no parameters for a guided wizard, or drive it with switches: by default it inventories tenant-wide Azure ARM resources and produces the live React, Json, and JsonEvidence outputs; opt into Entra ID collection with -Scope All; add -Assessment to run a read-only CAF/WAF assessment. Detailed run logs capture debug and verbose diagnostics without adding console noise. See everything. Own your cloud. (Requires PowerShell 7 on PowerShell Core.)'

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

# Modules that must be imported into the global environment prior to importing this module.
# Keep optional feature dependencies (for example Az.CostManagement) out of this list.
# Declaring the core dependencies here lets Install-Module resolve them and makes a
# source-tree Import-Module fail cleanly instead of installing software as a side effect.
# The live progress renderer is built into AzureScout and has no external module dependency.
RequiredModules = @(
    'ImportExcel'
    'Az.Accounts'
    'Az.ResourceGraph'
    'Az.Storage'
    'Az.Compute'
    'Az.Resources'
    'Az.Advisor'
    'Microsoft.Graph.Authentication'
    'powershell-yaml'
)

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

            #Public output maintenance
            'Clear-AZSCCacheFolder',

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
            'Export-ScoutConfig',

            #Assessment questionnaire: write the manual questions to a CSV to answer
            'Export-ScoutAssessmentQuestion'
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
        Tags = @('Azure','AzureScout','Discovery','Inventory','Assessment','CAF','WAF','WellArchitected','CloudAdoptionFramework','LandingZone','Governance','AZSC','EntraID','Resources','ARM','Graph','Reporting','React','Json','JsonEvidence')

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/Hybrid-Solutions-Cloud/azure-scout/blob/main/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://labs.hybridsolutions.cloud/azure-scout/'

        # A URL to an icon representing this module.
        IconUri = 'https://raw.githubusercontent.com/Hybrid-Solutions-Cloud/azure-scout/main/docs/public/images/azurescout-icon.svg'

        # ReleaseNotes of this module
        ReleaseNotes = 'v3.18.19 - Deeper collection: Azure VMware Solution sub-resources, and more checks scored from data already collected. Azure VMware Solution private clouds are now read below the top level: 13 sub-resource datasets (clusters and host counts, datastores, placement policies, maintenances, add-ons such as SRM/HCX/Arc, Global Reach, ExpressRoute authorizations, cloud links, NSX segments/DNS/DHCP/gateways, iSCSI paths) under domains.avs, read in parallel only when a private cloud exists, listed in discovery under their real resource types, with no passwords, keys, IP ranges or host names kept. Five AVS checks are scored from them (minimum hosts on every cluster, encryption state, VMware syslog forwarding, SRM add-on, connectivity that accepts Gen 2 clouds). Seventeen more checks move from manual to scored using data Scout already had or one extra storage read (management-group depth, Defender for Containers on registries, storage lifecycle policies, PostgreSQL, Log Analytics replication, Service Health alerts, Container Apps, AKS, API Management, Azure Firewall, Application Insights, Traffic Manager, Virtual WAN). A handled 403 on the optional Security Defaults read is logged as INFO, not ERROR. 66 assessments, 1733 rules, 693 automated. Not live-tested against AVS (none deployed in the test tenants); shapes verified against the Microsoft.AVS 2025-09-01 REST reference. v3.18.18 - Azure only, with Conditional Access and PIM scored from data. Scout assesses Azure: the seven assessments for products outside Azure added in 3.18.17 (Power Platform x3, Microsoft 365 Copilot data security, Dynamics 365 Sustainability, Microsoft for Financial Services, Windows 11) are removed, and the coverage page lists them as out of scope. Azure PIM eligibility, which Scout already read for every subscription and then discarded, now reaches the assessment data together with active role-assignment schedules (eligible, standing or activated; permanent or time-bound; privileged roles flagged) -- an ARM read covered by Reader. Entra Conditional Access policies, named locations and Security Defaults are read into domains.identity.conditionalAccess with computed flags (requires MFA, all users, Azure management, legacy-auth block, risk, device). Five identity checks move from manual to scored (CAF-IDN-04, CAF-BIL-02, WAF-AVD-SE-01, WAF-AVDAZ-SE-06, APPMOD-SEC-02), three PIM checks that were wired but always NotAssessed now score (CAF-IDN-02, CAF-IDN-05, CGOV-SC-05), and seven attach the policies or standing privileged assignments as evidence. Each reads NotAssessed, never Fail, when the data could not be read. 66 assessments, 1,732 rules, 674 automated. v3.18.17 - Every assessment in Microsoft''s catalog now has a Scout equivalent. Seven assessments for Microsoft products other than Azure, run as questionnaires because Scout does not read their data yet (answered with -AssessmentAnswers; each framework page names the Microsoft APIs an automated version would need): Power Platform Well-Architected (Microsoft''s checklist codes), Power Platform Solution and Power Platform Adoption; Microsoft 365 Copilot data security; Dynamics 365 Sustainability (formerly Sustainability Manager) and Microsoft for Financial Services (formerly Cloud for Financial Services) Well-Architected for Industry; and Windows 11 migration readiness. 73 assessments, 2,020 rules. The Microsoft Assessment Coverage page now maps every catalog assessment. v3.18.16 - Settings only a per-resource read returns, read eight at a time. Eight datasets Resource Graph does not hold are now read from each resource (storage blob and file soft delete, versioning and SMB settings; SQL auditing and failover groups; App Service FTP, basic auth, Always On, health check and remote debugging; Event Hubs geo-DR; Redis Enterprise access keys), with secret-bearing fields filtered before any row exists, and diagnostic-settings coverage extends to 14 more resource types. These reads and the diagnostic sweep now run eight at a time (live: 33 s to 3.7 s for 110 reads, identical results), and throttling or server errors back off 1-8 s honouring Retry-After over five attempts. 19 more checks are scored from data (669 of 1,732). A classic Redis cache with no access-key flag now reads as keys allowed, Azure''s default. v3.18.15 - More of each assessment answered from Azure data, and a WAF service-guides review. About 150 Azure settings added to the assessment collection (zones and high availability for databases, Redis, AKS, App Service, gateways, Service Bus and Event Hubs; TLS, local-auth and encryption settings; ids and locations) plus public IP, scale set, flow log and Event Grid datasets, so 179 more checks are scored from data (650 of 1,732). New WAF: Service Guides assessment: 214 checks from 20 Microsoft service guides. Fixed: classic Redis SKU always empty; Azure Firewall tier never collected; five typed Resource Graph queries Azure rejected (mv-apply and a reserved word), now live-verified and guarded by a test; diagnostic coverage not reaching the assessment in combined runs; Defender reads giving up after 0.6 seconds on a server error (now 2-16 s back-off, 5 attempts); duplicate compliance finding ids that made drift tracking skip a run. v3.18.14 - Microsoft''s workload, technology and questionnaire assessments. Eighteen Microsoft assessments Scout did not have (65 assessments, 1,507 rules, 471 automated): SAP on Azure, Oracle on Azure IaaS, SaaS, Mission Critical, Sustainability, Go-Live, Azure Machine Learning, Azure AI Search, Analytics and Data Services Well-Architected reviews; the Well-Architected Reliability Assessment (from the Azure Proactive Resiliency Library) and Azure Advisor recommendations; and the questionnaire-led AI Readiness, Generative AI Technical, GenAIOps Maturity, Platform Engineering, Analytics Journey Tracker and App and Data Modernization assessments. Microsoft publishes none of their question text, so each is Scout''s reading of the published guidance, documented per framework; questionnaire items are answered with -AssessmentAnswers. A Microsoft Assessment Coverage page maps every catalog assessment to Scout''s. Fixed: infrastructure-as-code rules (WAF-OE-02/08, CAF platform automation, DevOps) could never pass because no deployment history was collected; assessment runs now read Resource Graph''s deploymentresources table. v3.18.13 - Questionnaire answers, and assessments brought up to Microsoft''s current set. Manual assessment questions can now be answered and scored: every run writes assessment-questions.csv, -AssessmentAnswers (CSV or JSON) feeds answers back, the React report lets you answer and download them, the wizard asks for the file, and Export-ScoutAssessmentQuestion writes the questionnaire without a scan; answered items are marked Answered and data-evaluated rules are never overridden. SMART and Cloud Governance, which Microsoft deletes in January 2027, are re-based on CAF Plan + Migrate (CAF: Migrate readiness, 49 rules) and CAF Govern (CAF: Govern, 54 rules, with a governance-process domain); old names still resolve. FinOps Review follows the FinOps Framework 2026 (23 rules). The AI workload review covers all ten design areas (63 rules). New Workload: AVD reviews AVD in Azure (30 rules). Diagnostic-settings coverage was read from a property no resource has, so it reported 0% everywhere and failed CAF-MGT-01/05 and WAF-OE-01 in every tenant; it is now measured from the diagnostic-settings ARM sweep, and reported Not assessed when the sweep did not run. 47 assessments, 527 rules (222 automated). v3.18.12 - The remaining discovered types get collectors, and a faster completeness pass. Thirty-nine more collectors (381, up from 342) read resources that were discovered and categorized but not read: AKS Fleet and fleet members, Application Gateway for Containers, Container Apps session pools and Arc environments, Prometheus rule groups, Log Analytics dedicated clusters and query packs, Virtual WAN site-to-site, point-to-site and ExpressRoute gateways, VPN server configurations, ExpressRoute Direct ports, route filters, network virtual appliances, IP groups, public and custom IP prefixes, Private Link services, service endpoint policies, virtual network TAPs, NGINXaaS, Operator Nexus, API Center, Durable Task Schedulers, deployment stacks, template specs and deployment scripts, SAP virtual instances and monitors, capacity reservation and proximity placement groups, SSH public keys (presence only), Arc ESU licenses, private link scopes and multicloud connectors, AKS on Azure Local clusters, Azure Device Registry, Oracle Database@Azure, MongoDB Atlas, Confluent Cloud and Palo Alto Cloud NGFW. Secrets and personal data are never projected. Discovery''s per-resource completeness pass matched every resource against every collection-health entry; it now indexes them (live: 51 s to 9 s per pass on a 42-subscription tenant, three passes per run, identical output). Credential redaction during discovery now runs compiled with identical output (live: 28,930 of 28,930 values identical, 675 s to 16 s; discovery build 164 s to 63 s). The collector counts on the docs site and in the README were stale (245 and 240); they are corrected and a test keeps them in step with the catalogue. v3.18.11 - Every discovered resource has a category. Discovery found everything deployed, but only resources a collector reads were filed under one of the 18 categories (live: 47 of 129 discovered types, 13,268 resources, had none). Every Azure resource provider namespace (419: Azure''s provider catalogue plus Resource Graph''s reference) now maps to a category in manifests/resource-categories.psd1, with type-level entries where one namespace spans categories (role assignments are Identity, managed disks Storage, Update Manager patch results Management, firewall and WAF policies Security). A collector''s category still wins. Each Discovery.json record carries Category and CategorySource, its summary counts resources per category, the React report shows resources by category and lists each category''s resources without a collector on that category''s page, and docs/reference/resource-categories.md is generated from the map (live: 4,183 of 4,183 resources categorized). Earlier releases: see CHANGELOG.md.'

        # Prerelease string of this module
        # Prerelease = ''

        # Flag to indicate whether the module requires explicit user acceptance for install/update/save
        # RequireLicenseAcceptance = $false

    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}


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
ModuleVersion = '3.18.15'

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
        ReleaseNotes = 'v3.18.15 - More of each assessment answered from Azure data, and a WAF service-guides review. About 150 Azure settings added to the assessment collection (zones and high availability for databases, Redis, AKS, App Service, gateways, Service Bus and Event Hubs; TLS, local-auth and encryption settings; ids and locations) plus public IP, scale set, flow log and Event Grid datasets, so 179 more checks are scored from data (650 of 1,732). New WAF: Service Guides assessment: 214 checks from 20 Microsoft service guides. Fixed: classic Redis SKU always empty; Azure Firewall tier never collected; five typed Resource Graph queries Azure rejected (mv-apply and a reserved word), now live-verified and guarded by a test; diagnostic coverage not reaching the assessment in combined runs; Defender reads giving up after 0.6 seconds on a server error (now 2-16 s back-off, 5 attempts); duplicate compliance finding ids that made drift tracking skip a run. v3.18.14 - Microsoft''s workload, technology and questionnaire assessments. Eighteen Microsoft assessments Scout did not have (65 assessments, 1,507 rules, 471 automated): SAP on Azure, Oracle on Azure IaaS, SaaS, Mission Critical, Sustainability, Go-Live, Azure Machine Learning, Azure AI Search, Analytics and Data Services Well-Architected reviews; the Well-Architected Reliability Assessment (from the Azure Proactive Resiliency Library) and Azure Advisor recommendations; and the questionnaire-led AI Readiness, Generative AI Technical, GenAIOps Maturity, Platform Engineering, Analytics Journey Tracker and App and Data Modernization assessments. Microsoft publishes none of their question text, so each is Scout''s reading of the published guidance, documented per framework; questionnaire items are answered with -AssessmentAnswers. A Microsoft Assessment Coverage page maps every catalog assessment to Scout''s. Fixed: infrastructure-as-code rules (WAF-OE-02/08, CAF platform automation, DevOps) could never pass because no deployment history was collected; assessment runs now read Resource Graph''s deploymentresources table. v3.18.13 - Questionnaire answers, and assessments brought up to Microsoft''s current set. Manual assessment questions can now be answered and scored: every run writes assessment-questions.csv, -AssessmentAnswers (CSV or JSON) feeds answers back, the React report lets you answer and download them, the wizard asks for the file, and Export-ScoutAssessmentQuestion writes the questionnaire without a scan; answered items are marked Answered and data-evaluated rules are never overridden. SMART and Cloud Governance, which Microsoft deletes in January 2027, are re-based on CAF Plan + Migrate (CAF: Migrate readiness, 49 rules) and CAF Govern (CAF: Govern, 54 rules, with a governance-process domain); old names still resolve. FinOps Review follows the FinOps Framework 2026 (23 rules). The AI workload review covers all ten design areas (63 rules). New Workload: AVD reviews AVD in Azure (30 rules). Diagnostic-settings coverage was read from a property no resource has, so it reported 0% everywhere and failed CAF-MGT-01/05 and WAF-OE-01 in every tenant; it is now measured from the diagnostic-settings ARM sweep, and reported Not assessed when the sweep did not run. 47 assessments, 527 rules (222 automated). v3.18.12 - The remaining discovered types get collectors, and a faster completeness pass. Thirty-nine more collectors (381, up from 342) read resources that were discovered and categorized but not read: AKS Fleet and fleet members, Application Gateway for Containers, Container Apps session pools and Arc environments, Prometheus rule groups, Log Analytics dedicated clusters and query packs, Virtual WAN site-to-site, point-to-site and ExpressRoute gateways, VPN server configurations, ExpressRoute Direct ports, route filters, network virtual appliances, IP groups, public and custom IP prefixes, Private Link services, service endpoint policies, virtual network TAPs, NGINXaaS, Operator Nexus, API Center, Durable Task Schedulers, deployment stacks, template specs and deployment scripts, SAP virtual instances and monitors, capacity reservation and proximity placement groups, SSH public keys (presence only), Arc ESU licenses, private link scopes and multicloud connectors, AKS on Azure Local clusters, Azure Device Registry, Oracle Database@Azure, MongoDB Atlas, Confluent Cloud and Palo Alto Cloud NGFW. Secrets and personal data are never projected. Discovery''s per-resource completeness pass matched every resource against every collection-health entry; it now indexes them (live: 51 s to 9 s per pass on a 42-subscription tenant, three passes per run, identical output). Credential redaction during discovery now runs compiled with identical output (live: 28,930 of 28,930 values identical, 675 s to 16 s; discovery build 164 s to 63 s). The collector counts on the docs site and in the README were stale (245 and 240); they are corrected and a test keeps them in step with the catalogue. v3.18.11 - Every discovered resource has a category. Discovery found everything deployed, but only resources a collector reads were filed under one of the 18 categories (live: 47 of 129 discovered types, 13,268 resources, had none). Every Azure resource provider namespace (419: Azure''s provider catalogue plus Resource Graph''s reference) now maps to a category in manifests/resource-categories.psd1, with type-level entries where one namespace spans categories (role assignments are Identity, managed disks Storage, Update Manager patch results Management, firewall and WAF policies Security). A collector''s category still wins. Each Discovery.json record carries Category and CategorySource, its summary counts resources per category, the React report shows resources by category and lists each category''s resources without a collector on that category''s page, and docs/reference/resource-categories.md is generated from the map (live: 4,183 of 4,183 resources categorized). v3.18.10 - Collectors for what discovery found. Thirty new collectors read the settings of resources that discovery found but nothing read: Azure Local machines and Arc VM network interfaces, disks and security groups, custom locations, Arc VMware vCenters and inventory, Arc SCVMM servers and inventory, Arc SQL databases and availability groups, Kubernetes extensions, Arc run commands (never the script or its output), machine configuration compliance, Update Manager assignments, backup vaults and resource guards, Defender automations, standard assignments and multicloud connectors, network security perimeters, DNS private resolvers, forwarding rulesets and security policies, alert processing rules, partner monitors, managed images, compute galleries, restore point collections and Playwright Workspaces (342 collectors, up from 312). Live, they read 156 machine configuration assignments, 57 Defender standard assignments, 28 Arc SQL databases, 28 Update Manager assignments and 6 Azure Local machines from the test tenants. Seven retired services (MariaDB, MySQL single server, Integration Service Environment, Maps Creator, Azure API for FHIR, AI Health Insights, Playwright Testing) are now flagged as retired with their successor. v3.18.9 - Assessment-only counts what it assessed. A multi-tenant assessment-only run reported "resources 0" for every tenant because the count was hard-coded. It is now the number of distinct resources the assessment collected (live: 879 in a 42-subscription tenant). The output guide now says what each format writes in each run mode: in an assessment-only run, Json is findings.json, because there is no inventory to write. v3.18.8 - A throttle that outlasts Azure''s own wait. Cost Management can keep answering HTTP 429 while asking for only a few seconds'' wait each time (live: 7, 9, 6 and 10 s, all honoured, and an Arc server cost was still lost after 2.4 minutes, the only gap in a five-tenant run). Azure''s wait is now honoured on the first retry; after that a throttled request waits the longer of Azure''s wait and a doubling back-off of 10, 20, 40 and 60 s, and a cost query gets six attempts. v3.18.7 - Discovery without false failures. The resources 3.18.6 discovers from the other Resource Graph tables (role assignments, Lighthouse delegations, maintenance assignments, connector resources and others) were also sent to the per-resource provider-detail read. Their Resource Graph row is already complete, and many have no per-resource read at the subscription scope. Live, 111 of these reads failed in a 42-subscription tenant and marked it Partial. Those rows now skip that read and are tagged with the table they came from. A provider that lists an API version before it is live in every region no longer loses the resource''s detail: when Azure refuses the version and names the versions it supports there (live: storage accounts in East US), the read retries with the newest supported stable version. v3.18.6 - Everything deployed is discovered. Discovery read 3 of the 63 Azure Resource Graph tables, so resources that live only in another table were never found. A full inventory now also reads every other table that holds deployed resources. That brings in role assignments and custom roles, policy assignments, exemptions and custom definitions, Lighthouse delegations, machine-configuration and maintenance assignments, Kubernetes extensions, DNS record sets, Defender plans and connectors, backup and replication policies, VM scale set instances and more (live: 12 resources to 488 in an eight-subscription tenant). Tables of events, state and telemetry are excluded, each with its reason. A test fails if a Resource Graph table is neither read nor excluded. A cross-check against each subscription''s Azure Resource Manager resource list adds any resource Resource Graph did not return. Five assessment queries that read the wrong Resource Graph table and always came back empty (Lighthouse delegations, Advisor scores, backup policies, AVD session hosts, Edge orders) now read the right one (live: 38 delegations, 143 scores, 17 policies, 2 session hosts that had been missed). Earlier releases: see CHANGELOG.md.'

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


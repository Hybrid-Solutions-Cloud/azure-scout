#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    The Azure Resource Graph tables that hold deployed resources, beyond `resources`,
    `networkresources` and `resourcecontainers`, with the filter that keeps each to deployed
    resources.

.DESCRIPTION
    Resource Graph splits Azure across about sixty tables
    (https://learn.microsoft.com/azure/governance/resource-graph/reference/supported-tables-resources).
    `resources` holds every top-level tracked resource, but many deployed resources live only in
    another table: role assignments and custom roles, policy assignments, exemptions and custom
    definitions, Lighthouse delegations, guest-configuration and maintenance assignments,
    Kubernetes extensions and Flux configurations, DNS record sets, Elastic SAN volume groups,
    Kusto databases, Service Fabric managed clusters, Fleet members, API Center APIs,
    data-collection-rule associations, backup and replication policies, and more. Discovery
    reads every one of these so anything deployed in Azure has a way to be found.

    Tables, or types within a table, that hold events, state or telemetry rather than deployed
    resources are excluded, each with its reason (`-Excluded`). Every included table was queried
    live with its filter before release (2026-11-24, 42 subscriptions, every query succeeded).

    `Filter` is a KQL fragment placed after the scope clauses and before `| project`.

.PARAMETER Excluded
    Return the excluded tables and the reason for each instead of the included ones.
#>
function Get-ScoutResourceGraphDiscoveryTable {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([switch] $Excluded)

    if ($Excluded) {
        $excludedTables = [ordered]@{
            'resources'                          = 'Read by the main resources sweep.'
            'networkresources'                   = 'Read by the main network sweep.'
            'resourcecontainers'                 = 'Read first, for subscriptions and resource groups.'
            'advisorresources'                   = 'Recommendations are findings, not deployed resources; read separately with -IncludeAdvisories.'
            'patchassessmentresources'           = 'Update results, not deployed resources; read separately for Update Manager.'
            'patchinstallationresources'         = 'Update results, not deployed resources; read separately for Update Manager.'
            'alertsmanagementresources'          = 'Fired alerts are events.'
            'healthresources'                    = 'Availability status is state, one row per resource.'
            'servicehealthresources'             = 'Service health events; read through the ARM REST sweep.'
            'resourcechanges'                    = 'Change history.'
            'resourcecontainerchanges'           = 'Change history.'
            'networkresourcechanges'             = 'Change history.'
            'healthresourcechanges'              = 'Change history.'
            'maintenanceresourcechanges'         = 'Change history.'
            'extensibilityresourcechanges'       = 'Change history.'
            'deploymentresourcechanges'          = 'Change history.'
            'quotaresourcechanges'               = 'Change history.'
            'changesafetyresources'              = 'Change-safety records and rollout events.'
            'containerserviceeventresources'     = 'AKS scheduled events.'
            'metricresources'                    = 'Metric samples and statuses.'
            'machinesinventoryinsightsresources' = 'Software and update inventory reported by machines, not deployed resources.'
            'migrateresources'                   = 'Azure Migrate discovery of on-premises machines, databases and applications, not Azure deployments. The Migrate projects themselves are in resources.'
            'communitygalleryresources'          = 'Public community galleries published by others.'
            'sharedgalleryresources'             = 'Galleries other tenants share with this one; the owner deploys them.'
            'spotresources'                      = 'Spot price and eviction-rate data.'
            'capabilityresources'                = 'Platform capability metadata.'
            'tagsresources'                      = 'Tag names and values, not resources; tags are read on every resource.'
            'orbitalresources'                   = 'Spacecraft contacts are scheduled events.'
        }
        foreach ($name in $excludedTables.Keys) {
            [pscustomobject]@{ Table = $name; Reason = $excludedTables[$name] }
        }
        return
    }

    $tables = @(
        @{ Table = 'authorizationresources'; Filter = "| where type !~ 'microsoft.authorization/roledefinitions' or tostring(properties.type) =~ 'CustomRole'"; Note = 'Role assignments, classic administrators and custom roles. Built-in role definitions are Microsoft''s, not deployed.' }
        @{ Table = 'policyresources'; Filter = "| where type in~ ('microsoft.authorization/policyassignments','microsoft.authorization/policyexemptions','microsoft.authorization/policyenrollments') or (type in~ ('microsoft.authorization/policydefinitions','microsoft.authorization/policysetdefinitions','microsoft.authorization/policydefinitions/versions','microsoft.authorization/policysetdefinitions/versions') and tostring(properties.policyType) !in~ ('BuiltIn','Static'))"; Note = 'Assignments, exemptions, enrollments and custom definitions. Compliance states and built-in definitions are excluded.' }
        @{ Table = 'managedservicesresources'; Filter = ''; Note = 'Azure Lighthouse registration definitions and assignments.' }
        @{ Table = 'guestconfigurationresources'; Filter = "| where type =~ 'microsoft.guestconfiguration/guestconfigurationassignments'"; Note = 'Machine configuration assignments. Reports and machine software inventory are excluded.' }
        @{ Table = 'maintenanceresources'; Filter = "| where type =~ 'microsoft.maintenance/configurationassignments'"; Note = 'Maintenance configuration assignments (Update Manager schedules). Update runs are excluded.' }
        @{ Table = 'kubernetesconfigurationresources'; Filter = "| where type !in~ ('microsoft.kubernetesconfiguration/kubernetesresources','microsoft.kubernetesconfiguration/upgradeassessments')"; Note = 'Cluster extensions, Flux and source-control configurations, namespaces. In-cluster objects and upgrade assessments are excluded.' }
        @{ Table = 'extendedlocationresources'; Filter = ''; Note = 'Custom location enabled resource types.' }
        @{ Table = 'insightsresources'; Filter = ''; Note = 'Data collection rule associations, platform log configurations, tenant action groups.' }
        @{ Table = 'securityresources'; Filter = "| where type in~ ('microsoft.security/pricings','microsoft.security/governancerules','microsoft.security/integrations','microsoft.security/standardassignments','microsoft.security/advancedthreatprotectionsettings','microsoft.security/defenderforstoragesettings','microsoft.security/apicollections','microsoft.security/assessments/governanceassignments') or type startswith 'microsoft.security/securityconnectors'"; Note = 'Defender plans, settings, governance rules, standard assignments and connectors. Assessments, alerts, scores and inventories are findings, read separately.' }
        @{ Table = 'recoveryservicesresources'; Filter = "| where type !contains 'jobs' and type !endswith '/alerts' and type !endswith '/protectableitems'"; Note = 'Vaults, policies, protected and replicated items, recovery plans, deleted vaults. Jobs, alerts and protectable candidates are excluded.' }
        @{ Table = 'azurebusinesscontinuityresources'; Filter = ''; Note = 'Unified protected items.' }
        @{ Table = 'desktopvirtualizationresources'; Filter = ''; Note = 'AVD session hosts.' }
        @{ Table = 'computeresources'; Filter = ''; Note = 'VM scale set instances and their network interfaces.' }
        @{ Table = 'computeartifactresources'; Filter = ''; Note = 'Soft-deleted gallery artifacts.' }
        @{ Table = 'deploymentresources'; Filter = "| where type !~ 'microsoft.resources/deployments/operations'"; Note = 'Deployments and deployment stacks. Deployment operations are run history.' }
        @{ Table = 'dnsresources'; Filter = ''; Note = 'DNS and private DNS record sets, DNS forwarding rules and links.' }
        @{ Table = 'elasticsanresources'; Filter = ''; Note = 'Elastic SAN, volume groups and volumes.' }
        @{ Table = 'kustoresources'; Filter = ''; Note = 'Data Explorer databases, connections, principal assignments and scripts.' }
        @{ Table = 'servicefabricresources'; Filter = ''; Note = 'Service Fabric managed clusters, node types, applications and services.' }
        @{ Table = 'aksresources'; Filter = ''; Note = 'AKS Fleet members, update strategies and profiles.' }
        @{ Table = 'apicenterresources'; Filter = ''; Note = 'API Center APIs, versions and definitions.' }
        @{ Table = 'appserviceresources'; Filter = ''; Note = 'App Service site and slot configuration, Logic Apps Standard workflows.' }
        @{ Table = 'cognitiveservicesresources'; Filter = ''; Note = 'AI Foundry and Cognitive Services connections.' }
        @{ Table = 'batchresources'; Filter = ''; Note = 'Batch pools.' }
        @{ Table = 'chaosresources'; Filter = "| where type !in~ ('microsoft.chaos/experiments/executions','microsoft.chaos/experiments/statuses')"; Note = 'Chaos targets and capabilities. Experiment runs are excluded.' }
        @{ Table = 'edgeorderresources'; Filter = ''; Note = 'Azure Edge hardware orders.' }
        @{ Table = 'iotsecurityresources'; Filter = "| where type !contains 'alerts' and type !contains 'recommendations' and type !contains 'vulnerabilities' and type !~ 'microsoft.iotsecurity/locations/devicegroups/devices'"; Note = 'Defender for IoT sites, sensors and firmware workspaces. Alerts, findings and discovered devices are excluded.' }
        @{ Table = 'impactreportresources'; Filter = "| where type =~ 'microsoft.impact/connectors'"; Note = 'Impact reporting connectors. Workload impact reports are events.' }
        @{ Table = 'monitorresources'; Filter = "| where type =~ 'microsoft.monitor/slis'"; Note = 'Azure Monitor service level indicators. Issues are events.' }
        @{ Table = 'featureresources'; Filter = "| where type =~ 'microsoft.features/featureproviders/subscriptionfeatureregistrations'"; Note = 'Preview features registered on each subscription.' }
        @{ Table = 'azuredevopsplatformresources'; Filter = ''; Note = 'Azure DevOps organizations linked to Azure.' }
        @{ Table = 'saashubresources'; Filter = ''; Note = 'SaaS resources bought through Azure.' }
        @{ Table = 'supercomputerinfraresources'; Filter = ''; Note = 'Supercomputer infrastructure.' }
        @{ Table = 'awsresources'; Filter = ''; Note = 'AWS resources projected into Azure by a multicloud connector.' }
        @{ Table = 'gcpresources'; Filter = ''; Note = 'GCP resources projected into Azure by a multicloud connector.' }
    )
    foreach ($table in $tables) { [pscustomobject]$table }
}

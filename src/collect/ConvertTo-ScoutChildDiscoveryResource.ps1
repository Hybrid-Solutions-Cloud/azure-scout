#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Mirror the swept ARM sub-resource rows under their real ARM resource types, so the discovery
    index lists them.

.DESCRIPTION
    Resource Graph indexes the top-level resource (a private cloud, a SQL server, a Front Door
    profile, a namespace) but not its sub-resources, so Get-ScoutArmChildResource reads them with
    ARM GETs and returns synthetic `AZSC/ARMChild/*` rows. The discovery index
    (New-ScoutResourceDiscovery) treats every `AZSC/*` row as ENRICHMENT of the base resource with
    the same id and never lists it on its own -- which is right for a diagnostic setting or a blob
    container, and wrong for a cluster, an origin group or a firewall rule, which are deployable ARM
    resources with no Resource Graph row to enrich. Without a base row they were never discovered
    at all. "Everything deployable must be discoverable" (AB#9300).

    This pure transform gives each such child row a base-resource twin: same id and name, the real
    ARM type (`microsoft.avs/privateclouds/clusters`, `microsoft.cdn/profiles/origingroups`,
    `microsoft.sql/servers/firewallrules` ...), the parent's location, resource group and
    subscription, and the SAME allow-listed `properties` the AZSC row carries. The discovery index
    then lists it (category by its namespace), the AZSC row attaches to it as enrichment, and the
    React report shows it. It makes no Azure call, never mutates an input row and reads no property
    the sweep did not already allow-list.

    WHICH DATASETS ARE MIRRORED, and the rule used. A dataset is mirrored when
      1. its rows are built from an allow-list (`$SafeChildPropertyPaths` in Get-ScoutArmChildResource),
         so the twin can carry exactly what the AZSC row carries and nothing secret, and
      2. each row is a deployable ARM sub-resource with its own id, and the row count is bounded by
         the number of parents and the configuration they hold (a cluster, an origin, a policy, a
         rule, a queue) rather than by data volume.
    That covers the Azure VMware Solution children, the Front Door, SQL, Azure Local, Event Hubs and
    Service Bus, App Service authentication and API Management datasets, and the batch-2 settings
    (storage blob and file services, SQL auditing and failover groups, web app configuration and
    basic-auth policies, Event Hubs geo-DR, Redis Enterprise databases).

    NOT mirrored, by design: the datasets that keep the WHOLE response rather than an allow-list, or
    whose rows are records and user data that grow with use -- ResourceDiagnosticSettings,
    StorageLifecyclePolicies (rule names and prefixes), LAWorkspaceTables and LAWorkspaceSavedSearches
    (9,891 and 730 rows in a five-tenant run), SentinelDataConnectors and SentinelIngestion,
    StorageBlobContainers, StorageFileShares, StorageQueues, StorageTables, the ML datasets,
    ReservationUtilization (a report, not a resource), OpenAI deployments, Search, AVD applications,
    backup instances and Azure Local virtual machine instances. They stay enrichment of their parent.

    The twin shares its id with the AZSC row it mirrors, which ConvertFrom-ScoutInventory would
    de-duplicate; `AZSCDiscoveryTwin = $true` tells that shaper to skip it, so the AZSC row is what is
    shaped whatever order the two arrive in. Where Resource Graph already holds a row with the same
    id (App Service's `appserviceresources` table indexes some `sites/config` rows) that row arrives
    first and the discovery index keeps it, so the twin never duplicates it. No collector declares
    these types, so a twin feeds no worksheet.

.PARAMETER Resources
    The raw inventory's rows, including the AZSC/ARMChild rows the ARM-child sweep produced.

.OUTPUTS
    PSCustomObject rows, one per mirrored `AZSC/ARMChild/*` row that has an id.
#>
function ConvertTo-ScoutChildDiscoveryResource {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Resources
    )

    # Dataset -> the real ARM resource type. Every value is listed in manifests/azure-provider-types.json
    # except the ones Azure's provider catalogue leaves out (SQL firewall rules, API Management children,
    # Front Door security policies); tests/Collect.DepthDiscovery.Tests.ps1 holds that list.
    $RealType = @{
        # ---- Azure VMware Solution private-cloud children (3.18.19) ----
        'azsc/armchild/avsclusters'                  = 'microsoft.avs/privateclouds/clusters'
        'azsc/armchild/avsdatastores'                = 'microsoft.avs/privateclouds/clusters/datastores'
        'azsc/armchild/avsplacementpolicies'         = 'microsoft.avs/privateclouds/clusters/placementpolicies'
        'azsc/armchild/avsaddons'                    = 'microsoft.avs/privateclouds/addons'
        'azsc/armchild/avsglobalreachconnections'    = 'microsoft.avs/privateclouds/globalreachconnections'
        'azsc/armchild/avsauthorizations'            = 'microsoft.avs/privateclouds/authorizations'
        'azsc/armchild/avscloudlinks'                = 'microsoft.avs/privateclouds/cloudlinks'
        'azsc/armchild/avssegments'                  = 'microsoft.avs/privateclouds/workloadnetworks/segments'
        'azsc/armchild/avsdhcpconfigurations'        = 'microsoft.avs/privateclouds/workloadnetworks/dhcpconfigurations'
        'azsc/armchild/avsdnsservices'               = 'microsoft.avs/privateclouds/workloadnetworks/dnsservices'
        'azsc/armchild/avsgateways'                  = 'microsoft.avs/privateclouds/workloadnetworks/gateways'
        'azsc/armchild/avsiscsipaths'                = 'microsoft.avs/privateclouds/iscsipaths'
        'azsc/armchild/avsmaintenances'              = 'microsoft.avs/privateclouds/maintenances'

        # ---- Azure Front Door Standard / Premium (3.18.20) ----
        'azsc/armchild/afdorigingroups'              = 'microsoft.cdn/profiles/origingroups'
        'azsc/armchild/afdorigins'                   = 'microsoft.cdn/profiles/origingroups/origins'
        'azsc/armchild/afdendpoints'                 = 'microsoft.cdn/profiles/afdendpoints'
        'azsc/armchild/afdroutes'                    = 'microsoft.cdn/profiles/afdendpoints/routes'
        'azsc/armchild/afdcustomdomains'             = 'microsoft.cdn/profiles/customdomains'
        'azsc/armchild/afdsecuritypolicies'          = 'microsoft.cdn/profiles/securitypolicies'

        # ---- Azure SQL (3.18.20, and the batch-2 auditing and failover-group datasets) ----
        'azsc/armchild/sqldatabasebackupshortterm'   = 'microsoft.sql/servers/databases/backupshorttermretentionpolicies'
        'azsc/armchild/sqldatabasebackuplongterm'    = 'microsoft.sql/servers/databases/backuplongtermretentionpolicies'
        'azsc/armchild/sqldatabasetde'               = 'microsoft.sql/servers/databases/transparentdataencryption'
        'azsc/armchild/sqlserverfirewallrules'       = 'microsoft.sql/servers/firewallrules'
        'azsc/armchild/sqlserverencryptionprotector' = 'microsoft.sql/servers/encryptionprotector'
        'azsc/armchild/sqlserversecurityalertpolicies' = 'microsoft.sql/servers/securityalertpolicies'
        'azsc/armchild/sqlserverauditing'            = 'microsoft.sql/servers/auditingsettings'
        'azsc/armchild/sqlfailovergroups'            = 'microsoft.sql/servers/failovergroups'

        # ---- Azure Local clusters (3.18.20) ----
        'azsc/armchild/azurelocalupdatesummaries'    = 'microsoft.azurestackhci/clusters/updatesummaries'
        'azsc/armchild/azurelocalsecuritysettings'   = 'microsoft.azurestackhci/clusters/securitysettings'
        'azsc/armchild/azurelocalarcsettings'        = 'microsoft.azurestackhci/clusters/arcsettings'

        # ---- Event Hubs and Service Bus (3.18.20, and the batch-2 geo-DR dataset) ----
        'azsc/armchild/eventhubnetworkrulesets'      = 'microsoft.eventhub/namespaces/networkrulesets'
        'azsc/armchild/eventhubauthorizationrules'   = 'microsoft.eventhub/namespaces/authorizationrules'
        'azsc/armchild/eventhubentities'             = 'microsoft.eventhub/namespaces/eventhubs'
        'azsc/armchild/eventhubgeodr'                = 'microsoft.eventhub/namespaces/disasterrecoveryconfigs'
        'azsc/armchild/servicebusnetworkrulesets'    = 'microsoft.servicebus/namespaces/networkrulesets'
        'azsc/armchild/servicebusauthorizationrules' = 'microsoft.servicebus/namespaces/authorizationrules'
        'azsc/armchild/servicebusqueues'             = 'microsoft.servicebus/namespaces/queues'
        'azsc/armchild/servicebustopics'             = 'microsoft.servicebus/namespaces/topics'

        # ---- App Service (3.18.20, and the batch-2 configuration and basic-auth datasets) ----
        'azsc/armchild/webappauth'                   = 'microsoft.web/sites/config'
        'azsc/armchild/webappconfig'                 = 'microsoft.web/sites/config'
        'azsc/armchild/webappbasicauth'              = 'microsoft.web/sites/basicpublishingcredentialspolicies'

        # ---- API Management (3.18.20) ----
        'azsc/armchild/apimglobalpolicy'             = 'microsoft.apimanagement/service/policies'
        'azsc/armchild/apimapis'                     = 'microsoft.apimanagement/service/apis'
        'azsc/armchild/apimnamedvalues'              = 'microsoft.apimanagement/service/namedvalues'

        # ---- Storage service settings and Redis Enterprise databases (batch 2) ----
        'azsc/armchild/storageblobserviceproperties' = 'microsoft.storage/storageaccounts/blobservices'
        'azsc/armchild/storagefileserviceproperties' = 'microsoft.storage/storageaccounts/fileservices'
        'azsc/armchild/redisenterprisedatabases'     = 'microsoft.cache/redisenterprise/databases'
    }

    function Get-ChildRowValue {
        param([Parameter(Mandatory)]$InputObject, [Parameter(Mandatory)][string[]]$Name)
        foreach ($Candidate in $Name) {
            $Property = $InputObject.PSObject.Properties[$Candidate]
            if ($null -ne $Property) { return $Property.Value }
        }
        return $null
    }

    foreach ($Row in $Resources) {
        if ($null -eq $Row) { continue }
        $Type = ([string](Get-ChildRowValue -InputObject $Row -Name @('TYPE', 'type'))).ToLowerInvariant()
        if (-not $RealType.ContainsKey($Type)) { continue }
        $Id = [string](Get-ChildRowValue -InputObject $Row -Name @('id', 'ID'))
        if ([string]::IsNullOrWhiteSpace($Id)) { continue }

        [pscustomobject][ordered]@{
            id                = $Id
            name              = [string](Get-ChildRowValue -InputObject $Row -Name @('name', 'NAME'))
            type              = $RealType[$Type]
            location          = [string](Get-ChildRowValue -InputObject $Row -Name @('PARENTLOCATION', 'location'))
            resourceGroup     = [string](Get-ChildRowValue -InputObject $Row -Name @('RESOURCEGROUP', 'resourceGroup'))
            subscriptionId    = [string](Get-ChildRowValue -InputObject $Row -Name @('subscriptionId', 'SubscriptionId'))
            properties        = Get-ChildRowValue -InputObject $Row -Name @('properties', 'PROPERTIES')
            AZSCDiscoveryTwin = $true
        }
    }
}

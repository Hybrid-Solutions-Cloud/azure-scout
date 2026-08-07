#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Produce the normalized collect.json the assessment rules evaluate against.

.DESCRIPTION
    Resolves the discovery -> assessment data-shape gap (AB#5081, AB#5082). The
    existing inventory modules emit flat, Excel-oriented rows; the rule engine
    needs a nested object with SCALAR fields (so rule JSONPath never has to use
    `.length` inside a filter, which Newtonsoft does not support — AB#5083).

    This adapter runs read-only Azure Resource Graph queries and shapes the
    result into the canonical contract below. Ingestors (AzGovViz, Advisor)
    enrich `governance` / `advisor` afterward.

    Canonical shape (top-level keys the rules query):
        subscriptions[], tags[]
        networking { virtualNetworks[{name,peeringCount,ddosEnabled}], subnets[{ipUtilizationPct}],
                     azureFirewalls[], firewallPolicyRuleGroups[{policyName,priority,ruleCollectionCount,ruleCount,parseError}],
                     nsgPublicInbound[], privateDnsZones[], vpnGateways[],
                     privateEndpoints[{targetResourceId,targetProvider,targetType}],
                     applicationGateways[{sku,tier,provisioningState}], bastionHosts[{sku,provisioningState}],
                     networkConnections[{connectionType,connectionStatus}],
                     expressRouteCircuits[{sku,circuitProvisioningState,serviceProviderProvisioningState}],
                     frontDoors[{provisioningState,enabledState}],
                     loadBalancers[{sku,frontendIpCount}], natGateways[{sku,idleTimeoutInMinutes}],
                     networkInterfaces[{nsgAttached,privateIpCount}], networkWatchers[{provisioningState}],
                     publicDnsZones[{zoneType,recordSetCount}],
                     routeTables[{routeCount,disableBgpRoutePropagation}],
                     trafficManagerProfiles[{profileStatus,trafficRoutingMethod}],
                     virtualWans[{wanType,allowBranchToBranchTraffic}] }   (AB#7110, Story AB#7059,
                     Feature AB#7069, Epic AB#7099 -- 13 ordinary ARG-indexed Networking types)
        compute    { virtualMachines[{name,zoneRedundant,zoneEligible,licenseType,osType,
                                       patchMode,assessmentMode}],                       (AB#7109)
                     avdHostPools[{hostPoolType,loadBalancerType,maxSessionLimit}],
                     avdSessionHosts[{hostPoolName,status,agentVersion}],
                     avdScalingPlans[{hostPoolRefCount}] }                              (AB#6819)
                     privateClouds[{availabilityStrategy,availabilityZone,clusterSize,
                                     expressRouteCircuitId,encryptionStatus}] }   (AB#6820)
        management { recoveryVaults[{backupItems[]}], deployments[],
                     logAnalyticsWorkspaces[{retentionInDays}],
                     maintenanceConfigurations[{scope,recurEvery,startDateTime,duration,
                                                 timeZone,rebootSetting}],                (AB#7065)
                     advisorScores[{lastRefreshedScore}], automationAccounts[{sku}],
                     recoveryVaultBackupPolicies[{backupManagementType,scheduleFrequency}],
                     lighthouseDelegations[{provisioningState,authorizationCount}] }   (AB#7110,
                     Story AB#7059, Feature AB#7069, Epic AB#7099)
        updateManager { patchAssessments[{machineId,platform,osType,rebootPending,
                                           patchServiceUsed,startDateTime,lastModifiedDateTime,
                                           availablePatchCountByClassification}],
                         patchInstallations[{machineId,platform,osType,status,
                                              installationActivityId,installedPatchCount,
                                              failedPatchCount,pendingPatchCount,
                                              notSelectedPatchCount,excludedPatchCount,
                                              rebootStatus,maintenanceWindowExceeded,
                                              startDateTime,lastModifiedDateTime}] }
                       (AB#7107/AB#7108 -- Azure Update Manager's own `patchassessmentresources`/
                       `patchinstallationresources` Resource Graph tables, read-only, 7/30-day
                       retention respectively. A new top-level section rather than folding into
                       `management`/`compute`/`hybrid`, same reasoning as `monitor` -- the data
                       spans both Azure VMs and Arc-enabled servers, not one category's resource
                       type. `compute.virtualMachines`/`domains.hybrid.arcServers` above carry the
                       machine's own patch ORCHESTRATION config (patchMode/assessmentMode);
                       `updateManager` carries what Update Manager actually found/did.)
        security   { defenderPlans[], wafPolicies[{type,sku,provisioningState,enabledState,mode,
                     managedRuleSetCount,customRuleCount}],
                     ddosProtectionPlans[{provisioningState,protectedVNetCount,resourceGuid}],
                     applicationSecurityGroups[{provisioningState,resourceGuid}] }   (AB#7063,
                     Story AB#7059, Feature AB#7069, Epic AB#7099 -- ordinary ARG-indexed
                     Networking/Security types; DefenderAlerts/DefenderAssessments/
                     DefenderSecureScore/DefenderPricing were deliberately left out of this pass,
                     see the AB#7063 note above the query pack for why)
        governance { managementGroups[], policyAssignments[], policyDefinitions[],
                     policySetDefinitions[], roleAssignments[], budgets[],
                     resourceLocks[], pimEligibility[], classicAdministrators[] }  (filled by the
                     native Governance ingestor, Import-Governance; policyDefinitions/
                     policySetDefinitions are the raw ARM REST list rows behind the
                     AZSC/Management/PolicyDefinition|PolicySetDefinition envelopes the
                     TenantWideDefinitionsOnly sweep already collects -- AB#7066)
        costCleanup { orphanedDisks[], orphanedPips[] }
        opsPosture  { diagnosticCoverage[{type,coveragePct}] }
        monitor     { dataCollectionRules[{dataCollectionEndpointId,hasLogAnalyticsDestination,dataFlowCount,immutableId}],
                      dataCollectionEndpoints[{publicNetworkAccess,configurationAccessEndpoint,immutableId}],
                      actionGroups[{enabled,groupShortName,emailReceiverCount,smsReceiverCount,webhookReceiverCount}],
                      autoscaleSettings[{enabled,targetResourceUri,profileCount}],
                      metricAlertRules[{enabled,severity,autoMitigate,scopeCount,actionGroupCount}],
                      scheduledQueryRules[{enabled,severity,autoMitigate,kind,scopeCount}],
                      activityLogAlertRules[{enabled,scopeCount,actionGroupCount}],
                      smartDetectorAlertRules[{state,severity,frequency,actionGroupCount}],
                      appInsights[{applicationType,flowType,retentionInDays,samplingPercentage,
                                    ingestionMode,publicNetworkAccessForIngestion,publicNetworkAccessForQuery}],
                      workbooks[{kind,category,sourceId,version}],
                      privateLinkScopes[{accessMode,ingestionAccessMode,privateEndpointConnectionCount,
                                          scopedResourceCount}],
                      workspaceSolutions[{workspaceResourceId,planName,planPublisher,planProduct}],
                      appInsightsAvailabilityTests[{kind,enabled,frequency,timeoutSeconds,
                                                     syntheticMonitorId,testLocationCount}] }   (AB#7064,
                      Story AB#7059, Feature AB#7069 -- ordinary ARG-indexed Monitor types the
                      Monitor(20) coverage table listed as "not wired"; sits alongside
                      `opsPosture`/`management`, not folded into either. The
                      AppInsightsAvailabilityTests/AppInsightsWebTests pair share one ARM type,
                      `microsoft.insights/webtests`, distinguished only by `AdditionalFilter` in
                      their manifests (AvailabilityTests has none, i.e. every Kind; WebTests
                      filters `KIND -eq 'standard'`), so they combine into one
                      `appInsightsAvailabilityTests` query carrying `kind` per row rather than two
                      separate ARG round-trips over the same rows)
        domains     { storage{storageAccounts[{networkDefaultDeny}]},
                      databases{sqlServers[],sqlDatabases[],sqlDefenderPricing[{pricingTier}]},
                      web{webApps[{vnetIntegrated,customDomainBound}]},
                      containers{aksClusters[{networkPolicyEnabled,aadIntegrated,allPoolsZoned}],
                                 containerRegistries[],
                                 openShiftClusters[{provisioningState}], containerApps[{provisioningState,environmentId}],
                                 containerAppEnvironments[{provisioningState}],
                                 containerGroups[{osType,restartPolicy}]},   (AB#7110 -- 4 ordinary
                                 ARG-indexed Containers types)
                      security{keyVaults[]},
                      ai{cognitiveAccounts[{identityType,cmkEnabled}],
                         mlWorkspaces[{workspaceKind,publicAccess,identityType}],          (AB#6818)
                         searchServices[{sku}]},                                           (AB#6818)
                      security{keyVaults[], keyVaultSecrets[{contentType,enabled,expires}],
                               keyVaultKeys[{enabled,expires}],
                               appComplianceReports[{triggerType}],                        (AB#7110)
                               applicationSecurityGroups[],                                (AB#7110)
                               artifactSigningAccounts[{sku}],                             (AB#7110)
                               cloudHsmClusters[{provisioningState}],                       (AB#7110)
                               confidentialLedgers[{provisioningState,ledgerType}],         (AB#7110)
                               ddosProtectionPlans[{virtualNetworkCount}],                  (AB#7110)
                               entraDomainServices[{provisioningState}],                    (AB#7110)
                               managedHsms[{provisioningState,sku}],                        (AB#7110)
                               sentinelWorkspaces[{provisioningState}],                     (AB#7110)
                               wafPolicies[{policyType,mode}]},                             (AB#7110,
                               Story AB#7059, Feature AB#7069, Epic AB#7099)
                      identity{managedIdentities[]},                                       (AB#7110,
                               Story AB#7059, Feature AB#7069, Epic AB#7099 -- Identity had no
                               existing canonical domains section; ManagedIds is the only ARG-
                               indexed, non-Graph collector in the Identity(16) coverage gap)
                      ai{cognitiveAccounts[{identityType,cmkEnabled}]},
                      hybrid{arcServers[{patchMode,assessmentMode}],                        (AB#7109)
                             arcExtensions[{machineId,extensionType}],
                             azureLocalClusters[{connectivityStatus,nodeCount,clusterVersion}],            (AB#6819)
                             logicalNetworks[{vmSwitchName,subnetCount,addressPrefix,vlan}],                (AB#6819)
                             arcSites[], azureLocalVirtualMachineInstances[{parentName,powerState}],
                             arcDataControllers[{infrastructure,k8sNamespace,provisioningState}],
                             arcGateways[{provisioningState,gatewayType,gatewayEndpoint}],
                             arcKubernetes[{provisioningState,connectivityStatus,distribution,
                                             kubernetesVersion,totalNodeCount}],
                             arcResourceBridge[{provisioningState,status,distro,version,
                                                 infrastructureProvider}],
                             arcSqlManagedInstances[{provisioningState,dataControllerId,tier,
                                                      vCoresRequest,vCoresLimit}],
                             arcSqlServers[{provisioningState,version,edition,licenseType,vCore,
                                             patchLevel,azureDefenderStatus}],
                             galleryImages[{provisioningState,osType,hyperVGeneration,publisher,
                                             offer,sku,imageVersion}],
                             marketplaceGalleryImages[{provisioningState,status,osType,
                                                        hyperVGeneration,publisher,offer,sku,
                                                        imageVersion}],
                             storageContainers[{provisioningState,status,path,availableSizeGB,
                                                 containerSizeGB}]},                              (AB#7061,
                             Story AB#7059, Feature AB#7069, Epic AB#7099 -- Azure Local child
                             resources: gallery/marketplace images, storage containers, and the
                             remaining Arc-adjacent types (data controllers, gateways, Kubernetes,
                             resource bridge, SQL Server/Managed Instance) -- every one of the nine
                             is an ordinary ARG-indexed `resources`-table row, same pattern as
                             arcServers/azureLocalClusters/logicalNetworks above, not the ARM-child
                             sweep arcSites/azureLocalVirtualMachineInstances need.
                             (arcSites/azureLocalVirtualMachineInstances are ALWAYS present as
                             keys but only ever populated when the caller passes
                             -IncludeAzureLocalArm -- AB#6803, Feature AB#6747)
                      integration{eventHubNamespaces[{autoInflateEnabled}], apiManagement[],
                                  serviceBusNamespaces[{publicAccess}]},
                      iot{iotHubs[{disableLocalAuth}],
                          dpsInstances[{publicAccess,allocationPolicy,linkedHubCount}],
                          digitalTwinsInstances[{publicAccess,privateEndpointConnectionCount,identityType}]},
                      analytics{synapseWorkspaces[{managedVnetEnabled}], purviewAccounts[],
                                databricksWorkspaces[{sku,managedResourceGroupId}],
                                dataExplorerClusters[{sku,state}],
                                streamAnalyticsJobs[{sku,jobState}]} }   (per-category scalars,
                      Epic AB#5056; databricksWorkspaces/dataExplorerClusters/streamAnalyticsJobs
                      AB#7110 -- 3 ordinary ARG-indexed Analytics types)
        advisor[]                                                                   (filled by ingest)
        finops     { available, moduleAvailable, costRows[], anomalies[], blockedSubscriptions[],
                     reservations[], reservationRecommendations[] }  (reservations from ARM/ARG
                     here; available/costRows/anomalies/blockedSubscriptions filled by the
                     Import-ScoutCostInventory ingest, AB#6826)
        devops     { available, attempted, projects[], pipelines[], repositories[],
                     serviceConnections[], agentPools[], managedPools[], devCenters[],
                     loadTesting[], chaosExperiments[], playwrightTesting[],
                     apiConnections[], appConfigurationStores[{sku}],
                     deploymentEnvironmentTypes[], devBoxPools[{licenseType}],
                     devCenterNetworkConnections[{domainJoinType}],
                     devTestLabs[], labServicesLabs[] }  (managedPools through playwrightTesting,
                     and apiConnections through labServicesLabs, from ARM/ARG here;
                     available/attempted/projects through agentPools filled by the
                     Import-ScoutDevOpsCapability ingest, AB#6827; apiConnections..labServicesLabs
                     added AB#7110, Story AB#7059, Feature AB#7069, Epic AB#7099 -- these are
                     ordinary ARG-indexed ARM types, distinct from the org-level `devops/*`
                     Azure DevOps REST surface (projects[]/pipelines[]/etc above) which stays
                     out of scope for this ARG-only plumbing pass)

    Read-only throughout.

.NOTES
    Tracks ADO AB#5081, AB#5082 (Feature AB#5024). Every scalar the rules need
    (peeringCount, zoneRedundant, ipUtilizationPct, coveragePct) is computed here
    in KQL so no rule has to compute array lengths at evaluation time.

    AB#5057 follow-up: extended per-domain collectors so previously-manual CAF/WAF
    rules can assert against real ARG scalars instead of a human review. Every new
    field below was verified against a documented ARM property (or, for
    Microsoft.AzureStackHCI/clusters, the SDK-level enum) via Microsoft Learn before
    being added — sub-resources that Resource Graph does not index (SQL firewall
    rules/auditing/TDE, storage blob-service/management-policy settings, Synapse
    firewall rules, DPS enrollment groups) were deliberately left out; those rules
    stay manual.

    AB#5068/5071/5075 follow-up (Databases/Analytics/IoT rule-depth pass): added
    `sqlDefenderPricing` (Microsoft.Security/pricings, "SqlServers" plan — queried
    from the `SecurityResources` ARG table, not the default `Resources` table),
    `purviewAccounts` (Microsoft.Purview/accounts), and `iotHubs.disableLocalAuth`
    (documented IotHubProperties field). Each was confirmed present in the Azure
    Resource Graph supported-tables-and-resource-types reference before being added.
    Still deliberately NOT ARG-collectable (confirmed absent from that same
    reference) and left manual: SQL TDE/auditing/firewall-rules child resources,
    Data Factory/Synapse pipeline linked-service definitions, Synapse workspace
    firewall rules, DPS enrollment groups, per-device IoT credential type, and any
    metric- or Monitor-backed signal (IoT Hub throughput right-sizing).

    AB#330 follow-up (IoT deep coverage: Device Provisioning Service, Digital
    Twins, Edge): added `domains.iot.dpsInstances` (Microsoft.Devices/
    provisioningServices — confirmed ARG-indexed, entry 473 in the ARG
    supported-tables-and-resource-types reference) projecting `publicAccess`,
    `allocationPolicy` (documented IotDpsPropertiesDescription fields) and
    `linkedHubCount` (`array_length(properties.iotHubs)` — a COUNT only; the
    array's `connectionString` entries are secrets and are never projected), and
    `domains.iot.digitalTwinsInstances` (Microsoft.DigitalTwins/
    digitalTwinsInstances — confirmed ARG-indexed, entry 491 in that same
    reference) projecting `publicAccess`, `privateEndpointConnectionCount`
    (`array_length(properties.privateEndpointConnections)`, a top-level
    resource property, not a sub-resource join) and `identityType` (`identity`
    is a top-level Resource Graph column, same pattern as
    `cognitiveAccounts.identityType`). `networking.privateEndpoints` needed no
    change — its `targetProvider`/`targetType` projection is already
    type-agnostic, so PEs pointed at either new resource type are picked up by
    the existing query.

    AB#7110 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- collector-payload wiring audit
    follow-up. `docs/reference/collector-payload-coverage.md` (AB#7060) found 165 of 242 shipped
    collector manifests never reach this file's output. A first pass (Part 1) wired 20 ordinary
    ARG-indexed types: Networking (13: applicationGateways, bastionHosts, networkConnections,
    expressRouteCircuits, frontDoors, loadBalancers, natGateways, networkInterfaces,
    networkWatchers, publicDnsZones, routeTables, trafficManagerProfiles, virtualWans),
    Containers (4: openShiftClusters, containerApps, containerAppEnvironments,
    containerGroups), Analytics (3: databricksWorkspaces, dataExplorerClusters,
    streamAnalyticsJobs).

    This is Part 2 of the
    docs/reference/collector-payload-coverage.md wiring audit, sweeping Databases/DevOps/
    Identity/Management/Security/Storage/Web (Part 1, AB#7061/7064, covered Networking/
    Containers/Analytics/Hybrid/Monitor). Every type added below is an ordinary ARG-indexed
    `resources`-table row -- verified against the Azure Resource Graph
    supported-tables-and-resource-types reference before being added, same standard as every
    other query in this file. Deliberately EXCLUDED from this pass (confirmed non-ARG or
    synthetic, not a plumbing gap):
      - `entra/*` Identity manifests (AdminUnits, AppRegistrations, ConditionalAccess,
        CrossTenantAccess, DirectoryRoles, Domains, Groups, Licensing, ManagedIdentities
        (the Graph-scoped manifest, distinct from `ManagedIds`/`microsoft.managedidentity/
        userassignedidentities` below), NamedLocations, PIMAssignments, RiskyUsers,
        SecurityPolicies, ServicePrincipals, Users) -- Microsoft Graph API, not ARM/ARG.
      - `devops/*` org-level DevOps manifests (DevOpsAgentPools, DevOpsPipelines,
        DevOpsProjects, DevOpsRepositories, DevOpsServiceConnections) -- Azure DevOps REST
        API, not ARM/ARG; the `devops` canonical section's `agentPools`/`projects`/etc
        stubs above are what the Import-ScoutDevOpsCapability ingest fills.
      - Defender for Cloud manifests (DefenderAlerts, DefenderAssessments, DefenderPricing,
        DefenderSecureScore) and PolicyComplianceStates -- all resolve to the synthetic
        `AZSC/Subscription/SecurityPolicySweep` type (Get-ScoutDefenderPlanSweep), already
        covered by `security.defenderPlans`; the additional per-alert/assessment detail is
        a different, non-plumbing ticket.
      - PolicyDefinitions/PolicySetDefinitions/CustomRoleDefinitions -- synthetic
        `AZSC/Management/*` types; MaintenanceConfigurations (Azure Update Manager) --
        already in flight on a separate branch (AB#7065/AB#7107-7109). None re-wired here
        to avoid duplicating that work.
      - RecoveryVault (`microsoft.recoveryservices/vaults`) -- NOT a gap: the
        `management.recoveryVaults` key already reaches the payload end-to-end (AB#6895/
        AB#6896), just via a shape-only path with no `$q` entry (documented at its
        assignment site below); the coverage doc's static string-match audit cannot see
        that path and reports a false negative.
      - The entire Migration(4) category (AzureMigrateAssessments, AzureMigrateDiscoverySites,
        DataBox, StackEdge) -- NOT a gap: `domains.migration.migrateProjects`/
        `migrationServices`/`discoverySites` (AB#6830/6831/6832, already on main) match
        these exact resource types via `type in~ (...)`/`type startswith` KQL, which the
        coverage doc's literal-substring audit script does not recognize as covering them.
        Verified by direct inspection of this file, not re-wired.

    Deliberately NOT collected here, confirmed absent/out of scope after
    checking the ARM template references before writing this note:
      - DPS enrollment groups (individualEnrollments/enrollmentGroups) — a
        data-plane child store, not a distinct ARM resource type Resource Graph
        indexes (unchanged from the AB#5057 finding; CAF-IOT-03 stays manual).
      - `Microsoft.DigitalTwins/digitalTwinsInstances/endpoints` (the
        EventGrid/EventHub/ServiceBus routing-endpoint child resource) — listed
        in the Microsoft.DigitalTwins resource-type/version reference as its
        own ARM resource type, but it does NOT appear in the Resource Graph
        supported-tables-and-resource-types reference (only the parent
        `digitalTwinsInstances` type does), so it is not ARG-queryable; stays
        manual.
      - An "IoT Edge-enabled hub" indicator — checked the full IotHubProperties
        template reference and found NO Edge-specific field on
        Microsoft.Devices/IotHubs itself. Edge is a per-device concept
        (`capabilities.iotEdge` on a device twin, in the Registry Manager /
        Device Twin data plane), not a hub-level ARM property, so there is
        genuinely nothing honest to add here — not even a coarse/existence
        signal. Left as a documented manual rule (CAF-IOT-12) rather than
        inventing a proxy field.

    Parameter wiring (this pass):
      - `-ManagementGroupId`, when supplied, is passed as `-ManagementGroup` to
        every `Search-AzGraph` call so Collect is actually scoped, not tenant-wide.
        Omitted entirely when not supplied (preserves current tenant-wide behavior).
      - `-Categories` now really filters which ARG queries run. Each query below is
        tagged in `$queryCategories` with the manifest `Collect` category name(s)
        whose rule files reference its output path (cross-checked against every
        `src/assess/rules/*.yaml` `query:` field) — including cross-domain
        references (e.g. `waf.security` needs `domains.databases.sqlServers`, so
        `sqlServers` is tagged both `Databases` and `Security`). `subscriptions` is
        always collected (base data every rule set / the canonical shape needs). A
        `'*'` entry, an empty list, or omitting `-Categories` runs every query
        (unchanged full-collect behavior).

    Collector/pipeline resilience (AB#397/398/399/400/401):
      - `subscriptions` is always collected FIRST (regardless of hashtable
        enumeration order) so its subscription-id list is available as a fallback
        scope for every other query.
      - AB#397: if a tenant/MG-wide batch query throws (DNS blip, expired token,
        any other transient ARG/ARM error), it is retried ONE SUBSCRIPTION AT A
        TIME using the subscription list above. A subscription that still fails on
        retry logs a warning naming that subscription and is skipped — the OTHER
        subscriptions' rows for that same query are still collected and returned.
        Only a query that fails with no subscription list available at all (i.e.
        the `subscriptions` query itself failed) degrades to an empty result for
        that query, same as before this change.
      - AB#398: an `AuthorizationFailed` error on a query scoped to
        `-ManagementGroupId` gets a specific, actionable warning naming the
        management-group Reader-role requirement, instead of a bare ARG exception.
      - AB#399: a small set of documented, known-false ARG/ARM errors (a resource
        provider reported as "not registered" on a subscription that Resource Graph
        can still query successfully) are logged at Verbose and treated as
        non-errors — no per-subscription retry, no warning noise.
      - AB#400: `firewallPolicyRuleGroups`' nested rule-collection/rule structure is
        walked in PowerShell (not KQL) with a try/catch PER GROUP — one malformed
        group is recorded with `parseError` set and the run continues; it never
        blanks out the other, well-formed rule-collection groups in the same run.
      - AB#401: if literally every collected query returns zero rows, a diagnostic
        warning is emitted suggesting the likely causes (missing Reader RBAC, wrong
        subscription/tenant context, an empty/inaccessible `-ManagementGroupId`, or
        a `-Categories` filter that matched nothing) instead of silently handing an
        empty dataset to the report layer.
      - AB#405: when `Write-ScoutProgress` (src/Write-ScoutProgress.ps1) is loaded in
        the calling session, each query reports phase progress through it. The call
        is guarded by `Get-Command` so Collect has zero hard dependency on that
        helper — a session that never loaded it behaves exactly as before.

    AB#5639 (Epic AB#5638) added `Get-ScoutRawInventory.ps1` — `src/collect`'s own Resource
    Graph raw pass (SkipToken paging, 1000-subscription batching, throttling backoff) — plus
    `Get-ScoutApiResources.ps1` / `Get-ScoutVmQuotas.ps1` / `Get-ScoutVmSkuDetails.ps1` /
    `Get-ScoutCostInventory.ps1` for the non-ARG sources, but nothing called any of them:
    v2.7.0 shipped them as capability only.

    AB#5648 (this pass) inverts the dependency and makes them the real source:

      - `-Source Inventory` is now the DEFAULT. With no `-FromInventory` handed in,
        Invoke-Collect calls `Get-ScoutRawInventory` itself — three Resource Graph
        round-trips (`resourcecontainers`, `resources`, `networkresources`) — and shapes all
        34 derivable queries from those rows via `ConvertFrom-ScoutInventory`. Only
        `sqlDefenderPricing` still issues a typed query, because it reads the
        `SecurityResources` table (`microsoft.security/pricings`) which no inventory pass
        collects. A default assessment-only collect therefore costs 4 ARG round-trips
        instead of 35.
      - `-Source TypedQueries` runs the KQL pack below exactly as v2.7.0 did. It is kept as
        the reference implementation (the per-field source of truth
        `ConvertFrom-ScoutInventory` is verified against) and as an escape hatch, not as a
        path the product takes by default.
      - `-FromInventory` is unchanged and still wins over both: a combined inventory +
        assessment run reuses the rows the inventory pass already fetched.

      TRADE-OFF, stated plainly: the round-trip COUNT drops from 35 to 4, but the raw pass
      transfers the full `properties` bag for every resource in scope, where the typed
      queries transferred narrow projections. On a large estate the number of 1000-row PAGES
      can therefore go up even though the number of queries goes down, and `-Categories` no
      longer reduces what is fetched (it still filters what is shaped and returned). This is
      the same shape of trade the combined-run `-FromInventory` path has made since v2.5.0.
      `-Source TypedQueries` remains available for a narrow, single-category collect where
      projection size matters more than call count.

    `scripts/Get-CollectorResourceTypeMap.ps1` derives, from the 174 shipped definitions,
    which ARM types (and which non-ARG synthetic types, e.g. `AZSC/VM/Quotas`) they depend on
    — the cross-check for how much of that surface `src/collect` covers.
#>
function Invoke-Collect {
    [CmdletBinding()]
    param(
        [string[]] $Categories = @('*'),
        [ValidateSet('All', 'ArmOnly', 'EntraOnly')]
        [string]   $Scope = 'All',
        [string]   $ManagementGroupId,

        # AB#5543 — the result of Start-AZSCGraphExtraction from an inventory pass that already
        # ran in this invocation. When supplied, every query below that can be satisfied from
        # those already-fetched rows is shaped locally instead of re-querying Azure, so a
        # combined inventory + assessment run collects once rather than twice. Omitted, the
        # source is decided by -Source below.
        [object]   $FromInventory,

        # AB#5648 — where the 34 derivable queries get their rows from when no -FromInventory
        # was handed in.
        #   Inventory     (default) run ONE raw pass here (Get-ScoutRawInventory) and shape it.
        #   TypedQueries            run the KQL pack below, one query per result set (v2.7.0
        #                           behaviour, kept as the reference implementation).
        [ValidateSet('Inventory', 'TypedQueries')]
        [string]   $Source = 'Inventory',

        # AB#6792/#6793/#6794 (Feature AB#6744) -- opt-in, and deliberately so: the compliance-
        # state sweep (Get-ScoutSubscriptionSecurityPolicySweep, one Get-AzPolicyState call per
        # subscription) is the SAME call an inventory run already makes when -SecurityCenter is
        # requested; every other assessment must not start paying for it on every run. Only
        # Invoke-ScoutAssessmentCore sets this, and only for the 'Assess: Compliance' entry.
        [switch]   $IncludePolicyCompliance,

        # AB#6803 (Feature AB#6747, Epic AB#6454) -- opt-in for the same reason as
        # -IncludePolicyCompliance above: collecting `arcSites` costs the FULL per-subscription
        # ARM REST sweep (Get-ScoutApiResources without -DefinitionsOnly -- resource health,
        # managed identities, advisor score, reservation recommendations, THEN Arc sites, plus
        # the policy-assignment POST), not the two-call -DefinitionsOnly sweep every other
        # assessment pays, and collecting `azureLocalVirtualMachineInstances` costs one ARM GET
        # per Arc-enabled server in the estate (Get-ScoutArmChildResource's per-parent sweep).
        # Both are real, non-trivial Azure costs that only the 'WAF: Azure Local' assessment
        # should pay -- Invoke-ScoutAssessmentCore sets this only when that assessment (or
        # another declaring the same manifest flag) is selected.
        [switch]   $IncludeAzureLocalArm
    )
    Import-Module Az.ResourceGraph -ErrorAction Stop

    # ---- read-only KQL producing SCALAR fields the rules filter on ----
    $q = @{
        subscriptions = @'
resourcecontainers
| where type =~ "microsoft.resources/subscriptions"
| project id = subscriptionId, name, state = tostring(properties.state), tags
'@
        virtualNetworks = @'
resources
| where type =~ "microsoft.network/virtualnetworks"
| extend peeringCount = array_length(properties.virtualNetworkPeerings)
| extend ddosEnabled  = tobool(properties.enableDdosProtection)
| project name, resourceGroup, subscriptionId, peeringCount, ddosEnabled
'@
        subnets = @'
resources
| where type =~ "microsoft.network/virtualnetworks"
| mv-expand subnet = properties.subnets
| extend prefix = tostring(subnet.properties.addressPrefix)
| extend total = toint(exp2(32 - toint(split(prefix,"/")[1]))) - 5
| extend used  = array_length(subnet.properties.ipConfigurations)
| project vnet = name, subnet = tostring(subnet.name), prefix, total, used,
          ipUtilizationPct = iff(total > 0, round(todouble(used) / total * 100, 1), todouble(0))
'@
        azureFirewalls = @'
resources | where type =~ "microsoft.network/azurefirewalls"
| project name, resourceGroup, subscriptionId, sku = tostring(properties.sku.name)
'@
        # AB#400: firewall policy rule-collection groups. The nested rule-collection/rule
        # array is intentionally left as a dynamic column here (`ruleCollections`) rather
        # than walked with KQL mv-expand — the PowerShell-side parse below handles a
        # malformed/unexpected group's shape per-group instead of per-run (see NOTES).
        firewallPolicyRuleGroups = @'
resources
| where type =~ "microsoft.network/firewallpolicies/rulecollectiongroups"
| extend policyName = tostring(split(id, "/")[8])
| project name, resourceGroup, subscriptionId, policyName,
          priority = toint(properties.priority), ruleCollections = properties.ruleCollections
'@
        vpnGateways = @'
resources | where type =~ "microsoft.network/virtualnetworkgateways"
| project name, resourceGroup, gatewayType = tostring(properties.gatewayType),
          sku = tostring(properties.sku.name), activeActive = tobool(properties.activeActive),
          bgp = tobool(properties.enableBgp)
'@
        privateEndpoints = @'
resources | where type =~ "microsoft.network/privateendpoints"
// AB#5057: expose the linked-service target so per-domain rules (CAF-AI-04,
// CAF-IOT-05, ...) can test "does this account/hub have a dedicated PE" without
// a full cross-table join. ARG mv-expand only supports kind=bag|array (no outer),
// so take the first connection instead — preserves endpoints with no connection
// row, keeping the plain existence-count rules ($.networking.privateEndpoints[*])
// unaffected. PEs carry exactly one privateLinkServiceConnection in practice.
| extend conn = coalesce(properties.privateLinkServiceConnections[0], properties.manualPrivateLinkServiceConnections[0])
| extend targetResourceId = tostring(conn.properties.privateLinkServiceId)
| extend targetProvider = tolower(tostring(split(targetResourceId, "/")[6]))
| extend targetType = tolower(tostring(split(targetResourceId, "/")[7]))
| project name, resourceGroup, subscriptionId, targetResourceId, targetProvider, targetType
'@
        privateDnsZones = @'
resources | where type =~ "microsoft.network/privatednszones"
| project name, resourceGroup, subscriptionId
'@
        nsgPublicInbound = @'
resources
| where type =~ "microsoft.network/networksecuritygroups"
| mv-expand rule = properties.securityRules
| where rule.properties.access =~ "Allow" and rule.properties.direction =~ "Inbound"
      and (rule.properties.sourceAddressPrefix in ("*","0.0.0.0/0","Internet"))
| project nsg = name, resourceGroup, rule = tostring(rule.name),
          port = tostring(rule.properties.destinationPortRange)
'@
        # ---- AB#7110 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Networking(13)
        # coverage gap. Every type below is an ordinary ARM resource confirmed against the
        # Azure Resource Graph supported-tables-and-resource-types reference; every projected
        # field is a documented top-level or `sku`/`properties` scalar, no sub-resource joins.
        applicationGateways = @'
resources | where type =~ "microsoft.network/applicationgateways"
| project id, name, resourceGroup, subscriptionId, location,
          sku = tostring(properties.sku.name), tier = tostring(properties.sku.tier),
          provisioningState = tostring(properties.provisioningState)
'@
        bastionHosts = @'
resources | where type =~ "microsoft.network/bastionhosts"
| project id, name, resourceGroup, subscriptionId, location,
          sku = tostring(sku.name), provisioningState = tostring(properties.provisioningState)
'@
        networkConnections = @'
resources | where type =~ "microsoft.network/connections"
| project id, name, resourceGroup, subscriptionId, location,
          connectionType = tostring(properties.connectionType),
          connectionStatus = tostring(properties.connectionStatus)
'@
        expressRouteCircuits = @'
resources | where type =~ "microsoft.network/expressroutecircuits"
| project id, name, resourceGroup, subscriptionId, location,
          sku = tostring(sku.name),
          circuitProvisioningState = tostring(properties.circuitProvisioningState),
          serviceProviderProvisioningState = tostring(properties.serviceProviderProvisioningState)
'@
        frontDoors = @'
resources | where type =~ "microsoft.network/frontdoors"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState),
          enabledState = tostring(properties.enabledState)
'@
        loadBalancers = @'
resources | where type =~ "microsoft.network/loadbalancers"
| project id, name, resourceGroup, subscriptionId, location,
          sku = tostring(sku.name),
          frontendIpCount = array_length(properties.frontendIPConfigurations)
'@
        natGateways = @'
resources | where type =~ "microsoft.network/natgateways"
| project id, name, resourceGroup, subscriptionId, location,
          sku = tostring(sku.name),
          idleTimeoutInMinutes = toint(properties.idleTimeoutInMinutes)
'@
        networkInterfaces = @'
resources | where type =~ "microsoft.network/networkinterfaces"
| project id, name, resourceGroup, subscriptionId, location,
          nsgAttached = isnotempty(tostring(properties.networkSecurityGroup.id)),
          privateIpCount = array_length(properties.ipConfigurations)
'@
        networkWatchers = @'
resources | where type =~ "microsoft.network/networkwatchers"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState)
'@
        publicDnsZones = @'
resources | where type =~ "microsoft.network/dnszones"
| project id, name, resourceGroup, subscriptionId, location,
          zoneType = tostring(properties.zoneType),
          recordSetCount = toint(properties.numberOfRecordSets)
'@
        routeTables = @'
resources | where type =~ "microsoft.network/routetables"
| project id, name, resourceGroup, subscriptionId, location,
          routeCount = array_length(properties.routes),
          disableBgpRoutePropagation = tobool(properties.disableBgpRoutePropagation)
'@
        trafficManagerProfiles = @'
resources | where type =~ "microsoft.network/trafficmanagerprofiles"
| project id, name, resourceGroup, subscriptionId, location,
          profileStatus = tostring(properties.profileStatus),
          trafficRoutingMethod = tostring(properties.trafficRoutingMethod)
'@
        virtualWans = @'
resources | where type =~ "microsoft.network/virtualwans"
| project id, name, resourceGroup, subscriptionId, location,
          wanType = tostring(properties.type),
          allowBranchToBranchTraffic = tobool(properties.allowBranchToBranchTraffic)
'@
        virtualMachines = @'
resources
| where type =~ "microsoft.compute/virtualmachines"
| extend zoneCount = array_length(zones)
| extend zoneRedundant = iff(zoneCount > 0, true, false)
// Region-level AZ availability (documented, stable list) — a coarse but honest
// zone-eligibility signal. SKU-level zone capability needs a join against the
// resourceSkus table, deliberately deferred: it varies per region/SKU/quota
// and would need periodic refresh to stay accurate (AB#5086).
| extend zoneEligible = location in (
    "eastus","eastus2","westus2","westus3","centralus","southcentralus",
    "northeurope","westeurope","uksouth","francecentral","germanywestcentral",
    "switzerlandnorth","norwayeast","swedencentral","southeastasia","eastasia",
    "australiaeast","japaneast","koreacentral","centralindia","canadacentral",
    "brazilsouth","uaenorth","southafricanorth"
  )
// `id` is projected for the cross-resource joins (AB#6835): "which VMs have no backup"
// correlates this id against a backup protected item's sourceResourceId.
// licenseType is how Azure Hybrid Benefit is expressed on a VM, and it is ABSENT from the
// payload unless AHB is actually configured -- so an empty string here is the finding, not
// missing data. Projected alongside osType because the benefit only applies to Windows
// Server and to RHEL/SLES BYOS: without osType a rule cannot tell "eligible but not
// claimed" (real money) from "Linux, never eligible" (noise). The legacy Excel inventory
// path already surfaced this (manifests/collectors/Compute/VirtualMachine.psd1's "Hybrid
// Benefit" column) but the assess pipeline reads collect.json, which never carried it --
// which is why finops.review.yaml correctly reported it as uncollected. (AB#6928 follow-up)
// patchMode/assessmentMode (AB#7109, Story AB#7059, Feature AB#7069, Epic AB#7099) -- the
// machine's own Update Manager ORCHESTRATION setting (who triggers assessment/install:
// AutomaticByPlatform/AutomaticByOS/Manual/ImageDefault), documented on
// properties.osProfile.{windows,linux}Configuration.patchSettings. Neither sub-object is ever
// present on the OTHER OS family, so reading whichever one is non-empty is the correct merge --
// not an ambiguity, since a VM is Windows XOR Linux.
| extend winPatchMode = tostring(properties.osProfile.windowsConfiguration.patchSettings.patchMode)
| extend linPatchMode = tostring(properties.osProfile.linuxConfiguration.patchSettings.patchMode)
| extend winAssessMode = tostring(properties.osProfile.windowsConfiguration.patchSettings.assessmentMode)
| extend linAssessMode = tostring(properties.osProfile.linuxConfiguration.patchSettings.assessmentMode)
| extend patchMode = iff(isnotempty(winPatchMode), winPatchMode, linPatchMode)
| extend assessmentMode = iff(isnotempty(winAssessMode), winAssessMode, linAssessMode)
| project id, name, resourceGroup, subscriptionId, zoneRedundant, zoneEligible,
          size = tostring(properties.hardwareProfile.vmSize),
          licenseType = tostring(properties.licenseType),
          osType = tostring(properties.storageProfile.osDisk.osType),
          patchMode, assessmentMode
'@
        orphanedDisks = @'
resources | where type =~ "microsoft.compute/disks" and properties.diskState =~ "Unattached"
| project name, resourceGroup, location, sku = tostring(sku.name), sizeGb = toint(properties.diskSizeGB)
'@
        orphanedPips = @'
resources | where type =~ "microsoft.network/publicipaddresses" and isnull(properties.ipConfiguration)
| project name, resourceGroup, location, sku = tostring(sku.name)
'@
        diagnosticCoverage = @'
resources
| extend hasDiag = iff(isnotnull(properties.diagnosticSettings), true, false)
| summarize total = count(), withDiag = countif(hasDiag) by type
| extend coveragePct = iff(total > 0, round(todouble(withDiag)/total*100,1), todouble(0))
| project type, total, withDiag, coveragePct
'@
        deployments = @'
resourcecontainers
| where type =~ "microsoft.resources/subscriptions/resourcegroups"
| project name, subscriptionId
'@
        # ---- Management plumbing (AB#7110, Story AB#7059, Feature AB#7069, Epic AB#7099) --------
        # Four ordinary ARG-indexed Management types the Management(10) coverage-doc table listed
        # as "not wired". CustomRoleDefinitions/PolicyComplianceStates/PolicyDefinitions/
        # PolicySetDefinitions (synthetic AZSC/* types) and MaintenanceConfigurations (already in
        # flight on a separate branch) and RecoveryVault (already wired, see the file header) are
        # deliberately not re-declared here.
        advisorScores = @'
resources | where type =~ "microsoft.advisor/advisorscore"
| extend lastRefreshedScore = todouble(properties.lastRefreshedScore.score)
| project id, name, subscriptionId, lastRefreshedScore
'@
        automationAccounts = @'
resources | where type =~ "microsoft.automation/automationaccounts"
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(properties.sku.name)
'@
        recoveryVaultBackupPolicies = @'
resources | where type =~ "microsoft.recoveryservices/vaults/backuppolicies"
| extend backupManagementType = tostring(properties.backupManagementType)
| extend scheduleFrequency = tostring(properties.schedulePolicy.scheduleRunFrequency)
| project id, name, resourceGroup, subscriptionId, backupManagementType, scheduleFrequency
'@
        lighthouseDelegations = @'
resources | where type =~ "microsoft.managedservices/registrationdefinitions"
| extend provisioningState = tostring(properties.provisioningState)
| extend authorizationCount = array_length(properties.authorizations)
| project id, name, subscriptionId, provisioningState, authorizationCount
'@
        storageAccounts = @'
resources | where type =~ "microsoft.storage/storageaccounts"
| extend publicAccess = tobool(properties.allowBlobPublicAccess)
| extend httpsOnly = tobool(properties.supportsHttpsTrafficOnly)
| extend minTls = tostring(properties.minimumTlsVersion)
// properties.networkAcls is on the storage account resource itself (not a
// sub-resource), so it's safe to project directly — CAF-STO-05 (AB#5057).
| extend networkDefaultDeny = tostring(properties.networkAcls.defaultAction) =~ "Deny"
| project id, name, resourceGroup, sku = tostring(sku.name), publicAccess, httpsOnly, minTls, networkDefaultDeny
'@
        # ---- Storage plumbing (AB#7110, Story AB#7059, Feature AB#7069, Epic AB#7099) -----------
        # Five ordinary ARG-indexed Storage-adjacent types the Storage(8) coverage-doc table listed
        # as "not wired" (the other three -- BlobContainers/FileShares/LifecyclePolicies -- are
        # synthetic ARM-child sweeps, out of scope for this flat-ARG plumbing slice).
        edgeHardwareCenterOrders = @'
resources
| where type in~ ("microsoft.edgeorder/orders", "microsoft.edgeorder/orderitems", "microsoft.edgeorder/addresses")
| extend orderStatus = tostring(properties.orderItemDetails.orderItemStatus.status)
| project id, name, type, resourceGroup, subscriptionId, orderStatus
'@
        elasticSanVolumeGroups = @'
resources
| where type in~ ("microsoft.elasticsan/elasticsans", "microsoft.elasticsan/elasticsans/volumegroups")
| extend provisioningState = tostring(properties.provisioningState)
| project id, name, type, resourceGroup, subscriptionId, location,
          sku = tostring(sku.name), provisioningState
'@
        netAppVolumes = @'
resources | where type =~ "microsoft.netapp/netappaccounts/capacitypools/volumes"
| extend provisioningState = tostring(properties.provisioningState)
| extend usageThresholdGB = round(properties.usageThreshold / 1073741824.0, 2)
| project id, name, resourceGroup, subscriptionId, location, provisioningState, usageThresholdGB
'@
        partnerStorageResources = @'
resources
| where type in~ ("purestorage.block/storagepools", "purestorage.block/reservations", "qumulo.storage/filesystems")
| extend provisioningState = tostring(properties.provisioningState)
| project id, name, type, resourceGroup, subscriptionId, location, provisioningState
'@
        storageSyncServices = @'
resources
| where type in~ ("microsoft.storagesync/storagesyncservices", "microsoft.storagesync/storagesyncservices/syncgroups",
                  "microsoft.storagesync/storagesyncservices/registeredservers")
| extend incomingTrafficPolicy = tostring(properties.incomingTrafficPolicy)
| project id, name, type, resourceGroup, subscriptionId, location, incomingTrafficPolicy
'@
        sqlDatabases = @'
resources | where type =~ "microsoft.sql/servers/databases"
| extend zoneRedundant = tobool(properties.zoneRedundant)
| project name, resourceGroup, zoneRedundant, tier = tostring(sku.tier)
'@
        sqlServers = @'
resources | where type =~ "microsoft.sql/servers"
| extend publicNetworkAccess = tostring(properties.publicNetworkAccess)
| project name, resourceGroup, publicNetworkAccess
'@
        # AB#5068: Microsoft.Security/pricings ("SqlServers" plan) is the subscription-scoped
        # Defender for SQL / Advanced Threat Protection toggle and IS indexed by Resource
        # Graph — under the SecurityResources table, not the default Resources table
        # (confirmed via the ARG supported-tables-and-resource-types reference). This is a
        # coarse, subscription-wide signal (same tradeoff as security.defenderPlans /
        # CAF-SEC-02), not a per-server property — Microsoft.Sql/servers/auditingSettings and
        # .../extendedAuditingSettings (the "auditing" half of the old combined rule) are NOT
        # in that reference list, so they stay manual (CAF-DB-07).
        sqlDefenderPricing = @'
SecurityResources
| where type =~ "microsoft.security/pricings" and name =~ "sqlservers"
| project subscriptionId, name, pricingTier = tostring(properties.pricingTier)
'@
        # ---- Databases plumbing (AB#7110, Story AB#7059, Feature AB#7069, Epic AB#7099) ---------
        # Ten ordinary ARG-indexed database/cache PaaS types the Databases(10) coverage-doc table
        # listed as "not wired" -- manifests already collect them (Excel worksheets), this only
        # wires the scalar/count projection into the assessment payload, same pattern as every
        # other typed query in this file.
        cosmosDbAccounts = @'
resources | where type =~ "microsoft.documentdb/databaseaccounts"
| extend accountKind = tostring(['kind'])
| extend publicNetworkAccess = tostring(properties.publicNetworkAccess)
| extend disableLocalAuth = tobool(properties.disableLocalAuth)
| project id, name, resourceGroup, subscriptionId, location, kind = accountKind,
          publicNetworkAccess, disableLocalAuth
'@
        mariaDbServers = @'
resources | where type =~ "microsoft.dbformariadb/servers"
| extend sslEnforcement = tostring(properties.sslEnforcement)
| extend publicNetworkAccess = tostring(properties.publicNetworkAccess)
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name),
          sslEnforcement, publicNetworkAccess
'@
        mySqlServers = @'
resources | where type =~ "microsoft.dbformysql/servers"
| extend sslEnforcement = tostring(properties.sslEnforcement)
| extend publicNetworkAccess = tostring(properties.publicNetworkAccess)
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name),
          sslEnforcement, publicNetworkAccess
'@
        mySqlFlexibleServers = @'
resources | where type =~ "microsoft.dbformysql/flexibleservers"
| extend version = tostring(properties.version)
| extend publicNetworkAccess = tostring(properties.network.publicNetworkAccess)
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name),
          version, publicNetworkAccess
'@
        postgreSqlFlexibleServers = @'
resources | where type =~ "microsoft.dbforpostgresql/flexibleservers"
| extend version = tostring(properties.version)
| extend publicNetworkAccess = tostring(properties.network.publicNetworkAccess)
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name),
          version, publicNetworkAccess
'@
        redisCaches = @'
resources | where type in~ ("microsoft.cache/redis", "microsoft.cache/redisenterprise")
| extend publicNetworkAccess = tostring(properties.publicNetworkAccess)
| project id, name, type, resourceGroup, subscriptionId, location, sku = tostring(sku.name),
          publicNetworkAccess
'@
        sqlManagedInstances = @'
resources | where type =~ "microsoft.sql/managedinstances"
| extend publicDataEndpointEnabled = tobool(properties.publicDataEndpointEnabled)
| extend vCores = toint(sku.capacity)
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name),
          publicDataEndpointEnabled, vCores
'@
        sqlManagedInstanceDatabases = @'
resources | where type =~ "microsoft.sql/managedinstances/databases"
| extend status = tostring(properties.status)
| project id, name, resourceGroup, subscriptionId, status
'@
        sqlElasticPools = @'
resources | where type =~ "microsoft.sql/servers/elasticpools"
| project id, name, resourceGroup, subscriptionId, location,
          skuName = tostring(sku.name), skuTier = tostring(sku.tier)
'@
        sqlVirtualMachines = @'
resources | where type =~ "microsoft.sqlvirtualmachine/sqlvirtualmachines"
| extend sqlImageSku = tostring(properties.sqlImageSku)
| extend sqlServerLicenseType = tostring(properties.sqlServerLicenseType)
| project id, name, resourceGroup, subscriptionId, location, sqlImageSku, sqlServerLicenseType
'@
        webApps = @'
resources | where type =~ "microsoft.web/sites"
| extend httpsOnly = tobool(properties.httpsOnly)
| extend minTls = tostring(properties.siteConfig.minTlsVersion)
// virtualNetworkSubnetId and hostNameSslStates are top-level site properties
// (NOT part of the siteConfig summary object, which Resource Graph does not
// fully expand) — CAF-WEB-04/05 (AB#5057). customDomainBound is a coarse
// signal (more than the always-present *.azurewebsites.net entry), same
// tradeoff as the VM zoneEligible heuristic below.
| extend vnetIntegrated = isnotempty(tostring(properties.virtualNetworkSubnetId))
| extend customDomainBound = array_length(properties.hostNameSslStates) > 1
| project name, resourceGroup, httpsOnly, minTls, vnetIntegrated, customDomainBound
'@
        # ---- Web plumbing (AB#7110, Story AB#7059, Feature AB#7069, Epic AB#7099) ---------------
        # Twelve ordinary ARG-indexed Web/App-Service-adjacent types the Web(12) coverage-doc table
        # listed as "not wired" -- same plumbing fix as the Databases block above.
        appServiceCertificates = @'
resources
| where type in~ ("microsoft.certificateregistration/certificateorders", "microsoft.web/certificates")
| extend keyVaultId = tostring(properties.keyVaultId)
| project id, name, type, resourceGroup, subscriptionId, location, keyVaultId
'@
        appServiceDomains = @'
resources | where type =~ "microsoft.domainregistration/domains"
| extend provisioningState = tostring(properties.provisioningState)
| project id, name, resourceGroup, subscriptionId, provisioningState
'@
        appServiceEnvironments = @'
resources | where type =~ "microsoft.web/hostingenvironments"
| extend status = tostring(properties.status)
| extend aseKind = tostring(['kind'])
| project id, name, resourceGroup, subscriptionId, location, status, kind = aseKind
'@
        appServicePlans = @'
resources | where type =~ "microsoft.web/serverfarms"
| extend reserved = tobool(properties.reserved)
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name), reserved
'@
        communicationServices = @'
resources
| where type in~ ("microsoft.communication/communicationservices", "microsoft.communication/emailservices",
                  "microsoft.communication/emailservices/domains")
| extend provisioningState = tostring(properties.provisioningState)
| project id, name, type, resourceGroup, subscriptionId, location, provisioningState
'@
        webAppDeploymentSlots = @'
resources | where type =~ "microsoft.web/sites/slots"
| extend state = tostring(properties.state)
| extend siteName = tostring(split(id, "/slots/")[0])
| project id, name, siteName, resourceGroup, subscriptionId, state
'@
        fluidRelayServers = @'
resources | where type =~ "microsoft.fluidrelay/fluidrelayservers"
| extend provisioningState = tostring(properties.provisioningState)
| project id, name, resourceGroup, subscriptionId, location, provisioningState
'@
        notificationHubNamespaces = @'
resources
| where type in~ ("microsoft.notificationhubs/namespaces", "microsoft.notificationhubs/namespaces/notificationhubs")
| extend provisioningState = tostring(properties.provisioningState)
| project id, name, type, resourceGroup, subscriptionId, location,
          sku = tostring(sku.name), provisioningState
'@
        signalRServices = @'
resources | where type =~ "microsoft.signalrservice/signalr"
| extend publicNetworkAccess = tostring(properties.publicNetworkAccess)
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name),
          publicNetworkAccess
'@
        springApps = @'
resources | where type in~ ("microsoft.appplatform/spring", "microsoft.appplatform/spring/apps")
| extend zoneRedundant = tobool(properties.zoneRedundant)
| project id, name, type, resourceGroup, subscriptionId, location, sku = tostring(sku.name),
          zoneRedundant
'@
        staticWebApps = @'
resources | where type =~ "microsoft.web/staticsites"
| extend provisioningState = tostring(properties.provisioningState)
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name),
          provisioningState
'@
        webPubSubServices = @'
resources | where type =~ "microsoft.signalrservice/webpubsub"
| extend publicNetworkAccess = tostring(properties.publicNetworkAccess)
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name),
          publicNetworkAccess
'@
        aksClusters = @'
resources | where type =~ "microsoft.containerservice/managedclusters"
| extend k8sVersion = tostring(properties.kubernetesVersion)
| extend privateCluster = tobool(properties.apiServerAccessProfile.enablePrivateCluster)
| extend rbacEnabled = tobool(properties.enableRBAC)
| extend networkPolicyEnabled = isnotempty(tostring(properties.networkProfile.networkPolicy))
| extend aadIntegrated = isnotnull(properties.aadProfile)
// agentPoolProfiles is an array, so per-pool zone spread needs mv-expand +
// summarize back to one row per cluster — CAF-CON-05 (AB#5057).
| mv-expand pool = properties.agentPoolProfiles
| extend poolZoned = array_length(pool.availabilityZones) > 0
| summarize totalPools = count(), zonedPools = countif(poolZoned)
    by name, resourceGroup, k8sVersion, privateCluster, rbacEnabled, networkPolicyEnabled, aadIntegrated
| extend allPoolsZoned = zonedPools == totalPools
| project name, resourceGroup, k8sVersion, privateCluster, rbacEnabled, networkPolicyEnabled, aadIntegrated, allPoolsZoned
'@
        containerRegistries = @'
resources | where type =~ "microsoft.containerregistry/registries"
| extend adminEnabled = tobool(properties.adminUserEnabled)
| extend publicAccess = tostring(properties.publicNetworkAccess)
| project name, resourceGroup, sku = tostring(sku.name), adminEnabled, publicAccess
'@
        # ---- AB#7110 -- Containers(4) coverage gap. Ordinary ARG-indexed ARM types, same
        # verification standard as the rest of this file.
        openShiftClusters = @'
resources | where type =~ "microsoft.redhatopenshift/openshiftclusters"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState)
'@
        containerApps = @'
resources | where type =~ "microsoft.app/containerapps"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState),
          environmentId = tostring(properties.environmentId)
'@
        containerAppEnvironments = @'
resources | where type =~ "microsoft.app/managedenvironments"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState)
'@
        containerGroups = @'
resources | where type =~ "microsoft.containerinstance/containergroups"
| project id, name, resourceGroup, subscriptionId, location,
          osType = tostring(properties.osType), restartPolicy = tostring(properties.restartPolicy)
'@
        keyVaults = @'
resources | where type =~ "microsoft.keyvault/vaults"
| extend softDelete = tobool(properties.enableSoftDelete)
| extend purgeProtection = tobool(properties.enablePurgeProtection)
| project id, name, resourceGroup, softDelete, purgeProtection
'@
        # ---- Security plumbing (AB#7110, Story AB#7059, Feature AB#7069, Epic AB#7099) ----------
        # Ten ordinary ARG-indexed Security types the Security(14) coverage-doc table listed as
        # "not wired" (the other four, DefenderAlerts/Assessments/Pricing/SecureScore, resolve to
        # the synthetic AZSC/Subscription/SecurityPolicySweep type already covered by
        # security.defenderPlans -- deliberately not re-wired here, see the file header).
        # NOTE: wafPolicies/ddosProtectionPlans/applicationSecurityGroups are NOT redeclared here
        # -- AB#7063 (below) already wires all three with a fuller projection.
        appComplianceReports = @'
resources
| where type in~ ("microsoft.appcomplianceautomation/reports", "microsoft.appcomplianceautomation/reports/snapshots")
| extend triggerType = tostring(properties.triggerTime)
| project id, name, type, resourceGroup, subscriptionId, triggerType
'@
        artifactSigningAccounts = @'
resources | where type =~ "microsoft.codesigning/codesigningaccounts"
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name)
'@
        cloudHsmClusters = @'
resources | where type =~ "microsoft.hardwaresecuritymodules/cloudhsmclusters"
| extend provisioningState = tostring(properties.provisioningState)
| project id, name, resourceGroup, subscriptionId, location, provisioningState
'@
        confidentialLedgers = @'
resources | where type =~ "microsoft.confidentialledger/ledgers"
| extend provisioningState = tostring(properties.provisioningState)
| extend ledgerType = tostring(properties.ledgerType)
| project id, name, resourceGroup, subscriptionId, location, provisioningState, ledgerType
'@
        entraDomainServices = @'
resources | where type =~ "microsoft.aad/domainservices"
| extend provisioningState = tostring(properties.provisioningState)
| project id, name, resourceGroup, subscriptionId, location, provisioningState
'@
        managedHsms = @'
resources | where type =~ "microsoft.keyvault/managedhsms"
| extend provisioningState = tostring(properties.provisioningState)
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name),
          provisioningState
'@
        # Sentinel: `microsoft.securityinsights/onboardingstates` is the reliable, Sentinel-
        # specific ARM signal. Its sibling type on the manifest, `microsoft.operationsmanagement/
        # solutions`, is the SAME generic Log Analytics solutions type LAWorkspaceSolutions
        # (deferred in the AB#7064 Monitor plumbing pass) would also match -- deliberately not
        # queried here to avoid a false "Sentinel enabled" positive off an unrelated solution.
        sentinelWorkspaces = @'
resources | where type =~ "microsoft.securityinsights/onboardingstates"
| extend provisioningState = tostring(properties.provisioningState)
| project id, name, resourceGroup, subscriptionId, provisioningState
'@
        # ---- Identity plumbing (AB#7110, Story AB#7059, Feature AB#7069, Epic AB#7099) ----------
        # ManagedIds is the one non-Graph, ARG-indexed collector in the Identity(16) coverage-doc
        # table -- every other Identity collector declares an `entra/*` type (Microsoft Graph API,
        # not ARM/ARG), deliberately out of scope, see the file header.
        managedIdentities = @'
resources | where type =~ "microsoft.managedidentity/userassignedidentities"
| project id, name, resourceGroup, subscriptionId, location
'@
        # ---- AB#7063 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Defender-for-Cloud
        # detail collectors, Security(17) coverage gap ------------------------------------------
        # manifests/collectors/Security/*.psd1 has 17 collectors; only defenderPlans/keyVaults/
        # keyVaultKeys/keyVaultSecrets (4) reached the assessment payload before this pass.
        #
        # Wired here -- ordinary ARG-indexed `resources` table rows, same fix pattern as
        # AB#7064/7065/7066:
        #   wafPolicies / ddosProtectionPlans / applicationSecurityGroups
        #
        # Deliberately DEFERRED (not a wiring gap -- a missing collection mechanism):
        # DefenderAlerts.psd1, DefenderAssessments.psd1 and DefenderSecureScore.psd1 all declare
        # the synthetic `AZSC/Subscription/SecurityPolicySweep` type -- their SourceCollector
        # header points at Modules/Public/InventoryModules/Security/Defender*.ps1, but the ONLY
        # code that ever populates that sweep on the assessment collect path is
        # Get-ScoutDefenderPlanSweep.ps1, which calls exactly one REST endpoint
        # (`/providers/Microsoft.Security/pricings`, i.e. plans/pricing tiers) and nothing else.
        # Alerts/assessments/secure-score come from three DIFFERENT Defender-for-Cloud REST
        # endpoints (`/alerts`, `/assessments`, `/secureScores`) that Resource Graph does not
        # index under the default `resources` table and that today's collect makes zero calls
        # to -- there is no existing data to project into the payload, and adding three new
        # per-subscription REST round trips is a genuinely new collection mechanism, not a
        # plumbing fix. Confirmed against scripts/Test-CollectorPayloadCoverage.ps1's
        # $syntheticVerdicts entry for 'azsc/subscription/securitypolicysweep' (AB#7060), which
        # already documents this same gap.
        #
        # DefenderPricing.psd1 ALSO declares that same synthetic type and reads from the same
        # single `/pricings` endpoint Get-ScoutDefenderPlanSweep already calls -- its columns
        # (Plan Name, Plan ID, Pricing Tier, Enabled) duplicate what `security.defenderPlans`
        # already carries (id/name/properties.pricingTier/properties.subPlan). Its few genuinely
        # extra columns (Extensions, Deprecated, Replaced By, Free Trial Remaining Days) require
        # reshaping Get-ScoutDefenderPlanSweep's own projection, which CAF-SEC/WAF-SEC rules
        # already query as `security.defenderPlans[?(@.properties.pricingTier == 'Standard')]`
        # (AB#6903) -- changing that shared function's output risks regressing those live rules
        # for detail fields no rule currently needs. Left out of this pass as a duplicate-key
        # risk, not a missing mechanism; a follow-up should extend
        # Get-ScoutDefenderPlanSweep.ps1's own projection instead of adding a second query.
        wafPolicies = @'
resources
| where type in~ (
    "microsoft.network/applicationgatewaywebapplicationfirewallpolicies",
    "microsoft.network/frontdoorwebapplicationfirewallpolicies",
    "microsoft.cdn/cdnwebapplicationfirewallpolicies")
| extend enabledStateRaw = tostring(properties.policySettings.enabledState)
| extend stateRaw = tostring(properties.policySettings.state)
| extend enabledState = iff(isnotempty(enabledStateRaw), enabledStateRaw, stateRaw)
| extend mode = tostring(properties.policySettings.mode)
| extend managedRuleSetCount = array_length(properties.managedRules.managedRuleSets)
| extend customRuleCount = iff(isnotnull(properties.customRules.rules), array_length(properties.customRules.rules), array_length(properties.customRules))
| project id, name, resourceGroup, subscriptionId, location, type,
          sku = tostring(sku.name), provisioningState = tostring(properties.provisioningState),
          enabledState, mode, managedRuleSetCount, customRuleCount
'@
        ddosProtectionPlans = @'
resources | where type =~ "microsoft.network/ddosprotectionplans"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState),
          protectedVNetCount = array_length(properties.virtualNetworks),
          resourceGuid = tostring(properties.resourceGuid)
'@
        applicationSecurityGroups = @'
resources | where type =~ "microsoft.network/applicationsecuritygroups"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState),
          resourceGuid = tostring(properties.resourceGuid)
'@
        # ---- cross-resource join sources (AB#6835) --------------------------------------------
        # Each of these exists to be the OTHER half of a rule, not to be scored on its own.
        #
        # THEY DO NOT COST A ROUND TRIP. Every one is also shaped by ConvertFrom-ScoutInventory
        # from rows the single raw pass already returned, so on the default (inverted) path these
        # KQL bodies are never sent. They exist for the `-UseLiveQueries` escape hatch and as the
        # executable specification the shaper is verified against -- the same arrangement as the
        # other 34 derivable queries (see the AB#5639 note at the top of this file).
        #
        # backupProtectedItems is the answer to "which VMs have no backup". A protected item's
        # properties.sourceResourceId IS the protected resource's ARM id, which is the join key.
        backupProtectedItems = @'
recoveryservicesresources
| where type =~ "microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems"
| extend sourceResourceId = tostring(properties.sourceResourceId)
| extend protectionState = tostring(properties.protectionState)
| extend lastBackupStatus = tostring(properties.lastBackupStatus)
| extend backupManagementType = tostring(properties.backupManagementType)
| project id, name, resourceGroup, subscriptionId, sourceResourceId, protectionState,
          lastBackupStatus, backupManagementType
'@
        snapshots = @'
resources | where type =~ "microsoft.compute/snapshots"
| extend sourceDiskId = tostring(properties.creationData.sourceResourceId)
| extend sizeGb = toint(properties.diskSizeGB)
| extend created = tostring(properties.timeCreated)
| project id, name, resourceGroup, subscriptionId, sourceDiskId, sizeGb, created,
          sku = tostring(sku.name)
'@
        managedDisks = @'
resources | where type =~ "microsoft.compute/disks"
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name),
          diskState = tostring(properties.diskState), sizeGb = toint(properties.diskSizeGB)
'@
        # ---- Migration domain (AB#6830/AB#6831/AB#6832) ---------------------------------------
        # The SMART assessment scores migration readiness and cannot run on an estate where none
        # of this was ever queried. Before this existed the Migration category had zero collectors
        # and zero assessment inputs, so a SMART score would have been manufactured from nothing.
        migrateProjects = @'
resources
| where type in~ ("microsoft.migrate/migrateprojects", "microsoft.migrate/projects", "microsoft.migrate/assessmentprojects")
| extend publicNetworkAccess = tostring(properties.publicNetworkAccess)
| extend projectStatus = tostring(properties.projectStatus)
| project id, name, type, resourceGroup, subscriptionId, location, publicNetworkAccess, projectStatus
'@
        migrationServices = @'
resources
| where type in~ ("microsoft.datamigration/services", "microsoft.datamigration/sqlmigrationservices",
                  "microsoft.databox/jobs", "microsoft.databoxedge/databoxedgedevices")
| project id, name, type, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState)
'@
        discoverySites = @'
resources
| where type startswith "microsoft.offazure/"
| project id, name, type, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState)
'@
        diskEncryptionSets = @'
resources | where type =~ "microsoft.compute/diskencryptionsets"
| extend keyVaultId = tostring(properties.activeKey.sourceVault.id)
| extend encryptionType = tostring(properties.encryptionType)
| extend autoKeyRotation = tobool(properties.rotationToLatestKeyVersionEnabled)
| project id, name, resourceGroup, subscriptionId, keyVaultId, encryptionType, autoKeyRotation
'@
        cognitiveAccounts = @'
resources | where type =~ "microsoft.cognitiveservices/accounts"
| extend publicAccess = tostring(properties.publicNetworkAccess)
// `kind` is a reserved Kusto keyword — it can be neither an extend target nor a
// project alias; read the built-in column via ['kind'] and expose it as accountKind.
| extend accountKind = tostring(['kind'])
// `identity` is a top-level Resource Graph column (not under properties) —
// CAF-AI-03 (AB#5057). properties.encryption.keySource is the standard
// BYOK/CMK marker used across RPs (matches EventHub/Synapse) — CAF-AI-05.
| extend identityType = tostring(identity.type)
| extend cmkEnabled = tostring(properties.encryption.keySource) =~ "Microsoft.KeyVault"
| project name, resourceGroup, accountKind, publicAccess, identityType, cmkEnabled
'@
        arcServers = @'
resources | where type =~ "microsoft.hybridcompute/machines"
| extend status = tostring(properties.status)
// patchMode/assessmentMode (AB#7109) -- same PatchSettings shape Microsoft.HybridCompute
// documents for an Arc-enabled server as Microsoft.Compute does for an Azure VM; see the
// virtualMachines query above for why reading whichever OS family's sub-object is non-empty is
// the correct (not ambiguous) merge.
| extend winPatchMode = tostring(properties.osProfile.windowsConfiguration.patchSettings.patchMode)
| extend linPatchMode = tostring(properties.osProfile.linuxConfiguration.patchSettings.patchMode)
| extend winAssessMode = tostring(properties.osProfile.windowsConfiguration.patchSettings.assessmentMode)
| extend linAssessMode = tostring(properties.osProfile.linuxConfiguration.patchSettings.assessmentMode)
| extend patchMode = iff(isnotempty(winPatchMode), winPatchMode, linPatchMode)
| extend assessmentMode = iff(isnotempty(winAssessMode), winAssessMode, linAssessMode)
| project name, resourceGroup, status, agentVersion = tostring(properties.agentVersion),
          patchMode, assessmentMode
'@
        # ---- Azure Update Manager patch detail (AB#7107 AB#7108, Story AB#7059, Feature AB#7069,
        # Epic AB#7099) -- reads Update Manager's OWN Resource Graph tables, exactly as the raw
        # pass's -IncludeUpdateManagerResources sweep does (see Get-ScoutRawInventory.ps1's
        # AB#6731 comment for the full read-only rationale: this is what Update Manager already
        # recorded, never a fresh guest-OS scan). Both tables cover
        # microsoft.compute/virtualmachines, microsoft.hybridcompute/machines AND
        # microsoft.connectedvmwarevsphere/virtualmachines (Arc-enabled VMware) in one query, so
        # `platform` distinguishes which kind of machine a row is about.
        #
        # Each table also carries child `.../softwarepatches` rows (per-update KB/classification
        # detail) -- excluded here because this is the per-MACHINE summary row a rule scores
        # against, not the per-update detail a future collector could add separately.
        #
        # `id` is `<machineId>/patch{Assessment,Installation}Results/<latest-or-GUID>`
        # (documented ARM id shape) -- `machineId` below recovers the machine's own ARM id so a
        # rule can join this row back to compute.virtualMachines[].id / a future
        # hybrid.arcServers[].id, the same join pattern backupProtectedItems.sourceResourceId
        # already establishes for XR-BKP-01/02.
        patchAssessments = @'
patchassessmentresources
| where type !endswith "softwarepatches"
| extend sepIdx = indexof(tolower(id), "/patchassessmentresults/")
| extend machineId = substring(id, 0, sepIdx)
| extend platform = case(
    type startswith "microsoft.compute", "AzureVM",
    type startswith "microsoft.hybridcompute", "ArcServer",
    type startswith "microsoft.connectedvmwarevsphere", "AVS",
    "Unknown")
| project machineId, platform, subscriptionId, resourceGroup,
          osType = tostring(properties.osType),
          rebootPending = tobool(properties.rebootPending),
          patchServiceUsed = tostring(properties.patchServiceUsed),
          startDateTime = tostring(properties.startDateTime),
          lastModifiedDateTime = tostring(properties.lastModifiedDateTime),
          availablePatchCountByClassification = properties.availablePatchCountByClassification
'@
        patchInstallations = @'
patchinstallationresources
| where type !endswith "softwarepatches"
| extend sepIdx = indexof(tolower(id), "/patchinstallationresults/")
| extend machineId = substring(id, 0, sepIdx)
| extend platform = case(
    type startswith "microsoft.compute", "AzureVM",
    type startswith "microsoft.hybridcompute", "ArcServer",
    type startswith "microsoft.connectedvmwarevsphere", "AVS",
    "Unknown")
| project machineId, platform, subscriptionId, resourceGroup,
          osType = tostring(properties.osType),
          status = tostring(properties.status),
          installationActivityId = tostring(properties.installationActivityId),
          installedPatchCount = toint(properties.installedPatchCount),
          failedPatchCount = toint(properties.failedPatchCount),
          pendingPatchCount = toint(properties.pendingPatchCount),
          notSelectedPatchCount = toint(properties.notSelectedPatchCount),
          excludedPatchCount = toint(properties.excludedPatchCount),
          rebootStatus = tostring(properties.rebootStatus),
          maintenanceWindowExceeded = tobool(properties.maintenanceWindowExceeded),
          startDateTime = tostring(properties.startDateTime),
          lastModifiedDateTime = tostring(properties.lastModifiedDateTime)
'@
        eventHubNamespaces = @'
resources | where type =~ "microsoft.eventhub/namespaces"
| extend zoneRedundant = tobool(properties.zoneRedundant)
| extend publicAccess = tostring(properties.publicNetworkAccess)
// The ARM property is isAutoInflateEnabled, not autoInflateEnabled — CAF-INT-05 (AB#5057).
| extend autoInflateEnabled = tobool(properties.isAutoInflateEnabled)
| project name, resourceGroup, zoneRedundant, publicAccess, autoInflateEnabled
'@
        apiManagement = @'
resources | where type =~ "microsoft.apimanagement/service"
| extend virtualNetworkType = tostring(properties.virtualNetworkType)
| project name, resourceGroup, sku = tostring(sku.name), virtualNetworkType
'@
        serviceBusNamespaces = @'
resources | where type =~ "microsoft.servicebus/namespaces"
| extend publicAccess = tostring(properties.publicNetworkAccess)
| project name, resourceGroup, publicAccess
'@
        iotHubs = @'
resources | where type =~ "microsoft.devices/iothubs"
| extend publicAccess = tostring(properties.publicNetworkAccess)
// disableLocalAuth (documented IotHubProperties field) is true when SAS
// tokens issued from the hub's own shared access policies are rejected,
// forcing Microsoft Entra ID + RBAC for service-API access — CAF-IOT-06
// (AB#5075). This is a hub-level *service-API* auth control, distinct from
// per-device X.509/TPM-vs-symmetric-key credential choice (CAF-IOT-02, still
// manual — that lives in the device registry, a data-plane store Resource
// Graph does not index).
| extend disableLocalAuth = tobool(properties.disableLocalAuth)
| project name, resourceGroup, sku = tostring(sku.name), publicAccess, disableLocalAuth
'@
        # AB#330: Microsoft.Devices/provisioningServices (Device Provisioning Service) IS
        # indexed by Resource Graph (confirmed via the ARG supported-tables-and-resource-types
        # reference, entry 473). allocationPolicy and publicNetworkAccess are documented
        # top-level IotDpsPropertiesDescription fields. linkedHubCount is a COUNT of the
        # linked-hub array only (array_length(properties.iotHubs)) -- each entry's
        # `connectionString` is a secret and is never read or projected here. DPS enrollment
        # groups (where the per-device cert-vs-symmetric-key auth type actually lives) remain
        # a data-plane child store Resource Graph does not index -- CAF-IOT-03 stays manual.
        dpsInstances = @'
resources | where type =~ "microsoft.devices/provisioningservices"
| extend publicAccess = tostring(properties.publicNetworkAccess)
| extend allocationPolicy = tostring(properties.allocationPolicy)
| extend linkedHubCount = array_length(properties.iotHubs)
| project name, resourceGroup, sku = tostring(sku.name), publicAccess, allocationPolicy, linkedHubCount
'@
        # AB#330: Microsoft.DigitalTwins/digitalTwinsInstances IS indexed by Resource Graph
        # (confirmed via the ARG supported-tables-and-resource-types reference, entry 491).
        # publicNetworkAccess and privateEndpointConnections are documented top-level
        # properties on the digitalTwinsInstances resource itself (not a sub-resource join).
        # `identity` is a top-level Resource Graph column -- same pattern as
        # cognitiveAccounts.identityType (AB#5057) -- CAF-IOT-11. The message-routing
        # endpoints (Microsoft.DigitalTwins/digitalTwinsInstances/endpoints -- EventGrid/
        # EventHub/ServiceBus routes) are a distinct ARM child resource type that does NOT
        # appear in that same ARG reference, so they are not ARG-queryable and stay manual.
        digitalTwinsInstances = @'
resources | where type =~ "microsoft.digitaltwins/digitaltwinsinstances"
| extend publicAccess = tostring(properties.publicNetworkAccess)
| extend privateEndpointConnectionCount = array_length(properties.privateEndpointConnections)
| extend identityType = tostring(identity.type)
| project name, resourceGroup, publicAccess, privateEndpointConnectionCount, identityType
'@
        synapseWorkspaces = @'
resources | where type =~ "microsoft.synapse/workspaces"
| extend publicAccess = tostring(properties.publicNetworkAccess)
// properties.managedVirtualNetwork is "default" when the workspace-managed
// VNet is on, empty otherwise — a top-level workspace property, not a
// sub-resource — CAF-ANL-03 (AB#5057).
| extend managedVnetEnabled = isnotempty(tostring(properties.managedVirtualNetwork))
| project name, resourceGroup, publicAccess, managedVnetEnabled
'@
        # AB#5071: Microsoft.Purview/accounts IS indexed by Resource Graph (confirmed via the
        # ARG supported-tables-and-resource-types reference), unlike Data Factory/Synapse
        # pipeline linked services (CAF-ANL-04, still manual — linked services are a
        # data-plane sub-object of the factory/pipeline payload, not a distinct ARM child
        # resource) or Synapse workspace firewall rules (CAF-ANL-05, still manual — not in
        # that reference list either). Existence-only signal, same coarse tradeoff as the
        # VM zoneEligible / webApps customDomainBound heuristics above: a Purview account
        # existing is evidence a governance foundation is in place, not proof the whole
        # analytics estate is catalogued/classified — CAF-ANL-02.
        purviewAccounts = @'
resources | where type =~ "microsoft.purview/accounts"
| project name, resourceGroup, subscriptionId
'@
        # ---- AB#7110 -- Analytics(3) coverage gap. Ordinary ARG-indexed ARM types, same
        # verification standard as the rest of this file.
        databricksWorkspaces = @'
resources | where type =~ "microsoft.databricks/workspaces"
| project id, name, resourceGroup, subscriptionId, location,
          sku = tostring(sku.name),
          managedResourceGroupId = tostring(properties.managedResourceGroupId)
'@
        dataExplorerClusters = @'
resources | where type =~ "microsoft.kusto/clusters"
| project id, name, resourceGroup, subscriptionId, location,
          sku = tostring(sku.name), state = tostring(properties.state)
'@
        streamAnalyticsJobs = @'
resources | where type =~ "microsoft.streamanalytics/streamingjobs"
| project id, name, resourceGroup, subscriptionId, location,
          sku = tostring(properties.sku.name), jobState = tostring(properties.jobState)
'@
        arcExtensions = @'
resources | where type =~ "microsoft.hybridcompute/machines/extensions"
| extend extensionType = tostring(properties.type)
| extend machineId = tostring(split(id, "/extensions/")[0])
| project machineId, name, extensionType, resourceGroup
'@
        azureLocalClusters = @'
resources | where type =~ "microsoft.azurestackhci/clusters"
// connectivityStatus is the documented cluster-resource health enum
// (Connected/Disconnected/NotConnectedRecently/PartiallyConnected/
// NotYetRegistered/NotSpecified) — CAF-HYB-05 (AB#5057).
// nodeCount/clusterVersion added for AB#6803 (WAF-AZLOCAL-RE-02/RE-03/OE-06) — same
// agent-reported properties the pre-retirement Hybrid/Clusters collector already read.
| extend connectivityStatus = tostring(properties.connectivityStatus)
// nodeCount — WAF-AVD-RE-01 (AB#6819) / WAF-AZLOCAL-RE-02 (AB#6803). clusterNodes is the
// field the pre-retirement Hybrid/Clusters collector and ConvertFrom-ScoutInventory.ps1 both
// read (properties.reportedProperties.clusterNodes); a cluster that has not yet reported
// (nodes absent) yields $null, not 0 — treated as "not yet known", not "single node".
| extend nodeCount = array_length(properties.reportedProperties.clusterNodes)
| extend clusterVersion = tostring(properties.reportedProperties.clusterVersion)
| project name, resourceGroup, subscriptionId, connectivityStatus, nodeCount, clusterVersion
'@
        # AB#6803 (WAF-AZLOCAL-RE-03/OE-03) — confirmed ARG-indexed
        # (microsoft.azurestackhci/logicalnetworks, learn.microsoft.com/azure/governance/
        # resource-graph/reference/supported-tables-resources). First-subnet fields match the
        # existing Hybrid/LogicalNetworks declarative collector's "primary subnet" convention.
        logicalNetworks = @'
resources | where type =~ "microsoft.azurestackhci/logicalnetworks"
| extend subnetCount = array_length(properties.subnets)
| extend firstSubnet = properties.subnets[0]
| extend vmSwitchName = tostring(properties.vmSwitchName)
| extend addressPrefix = tostring(firstSubnet.properties.addressPrefix)
| extend vlan = toint(firstSubnet.properties.vlan)
| project name, resourceGroup, subscriptionId, vmSwitchName, subnetCount, addressPrefix, vlan
'@
        # AB#7061 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Azure Local child resources.
        # `manifests/collectors/Hybrid/*.psd1` for each of the nine types below already exist and
        # are confirmed ARG-indexed (ordinary `resources`-table rows -- verified against the Azure
        # Resource Graph supported-tables-and-resource-types reference before being added, same
        # standard as every other query in this file); this only wires their query into the
        # assessment payload the way AB#7064/7065/7066 wired the last three plumbing slices.
        # VirtualMachines/ArcSites are deliberately NOT re-declared here -- they are already wired,
        # via the ARM-child sweep (azureLocalVirtualMachineInstances/arcSites above), because
        # Resource Graph does not index their synthetic types. ArcServerOperationalData is also
        # not re-declared -- its ResourceTypes is `microsoft.hybridcompute/machines`, the same type
        # arcServers already queries above; its distinguishing operational fields (patch
        # assessment, backup status) come from a separate per-machine REST envelope this collect
        # pass does not make, so only the base machine row (already covered by arcServers) is
        # in scope here.
        arcDataControllers = @'
resources
| where type =~ "microsoft.azurearcdata/datacontrollers"
| project id, name, resourceGroup, subscriptionId, location,
          infrastructure = tostring(properties.infrastructure),
          k8sNamespace = tostring(properties.k8sRaw.metadata.namespace),
          provisioningState = tostring(properties.provisioningState)
'@
        arcGateways = @'
resources
| where type =~ "microsoft.hybridcompute/gateways"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState),
          gatewayType = tostring(properties.gatewayType),
          gatewayEndpoint = tostring(properties.gatewayEndpoint)
'@
        arcKubernetes = @'
resources
| where type =~ "microsoft.kubernetes/connectedclusters"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState),
          connectivityStatus = tostring(properties.connectivityStatus),
          distribution = tostring(properties.distribution),
          kubernetesVersion = tostring(properties.kubernetesVersion),
          totalNodeCount = toint(properties.totalNodeCount)
'@
        arcResourceBridge = @'
resources
| where type =~ "microsoft.resourceconnector/appliances"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState),
          status = tostring(properties.status),
          distro = tostring(properties.distro),
          version = tostring(properties.version),
          infrastructureProvider = tostring(properties.infrastructureConfig.provider)
'@
        arcSqlManagedInstances = @'
resources
| where type =~ "microsoft.azurearcdata/sqlmanagedinstances"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState),
          dataControllerId = tostring(properties.dataControllerId),
          tier = tostring(properties.tier),
          vCoresRequest = toint(properties.vCores.request),
          vCoresLimit = toint(properties.vCores.limit)
'@
        arcSqlServers = @'
resources
| where type =~ "microsoft.azurearcdata/sqlserverinstances"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState),
          version = tostring(properties.version),
          edition = tostring(properties.edition),
          licenseType = tostring(properties.licenseType),
          vCore = toint(properties.vCore),
          patchLevel = tostring(properties.patchLevel),
          azureDefenderStatus = tostring(properties.azureDefenderStatus)
'@
        galleryImages = @'
resources
| where type =~ "microsoft.azurestackhci/galleryimages"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState),
          osType = tostring(properties.osType),
          hyperVGeneration = tostring(properties.hyperVGeneration),
          publisher = tostring(properties.identifier.publisher),
          offer = tostring(properties.identifier.offer),
          sku = tostring(properties.identifier.sku),
          imageVersion = tostring(properties.version.name)
'@
        marketplaceGalleryImages = @'
resources
| where type =~ "microsoft.azurestackhci/marketplacegalleryimages"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState),
          status = tostring(properties.status.provisioningStatus.status),
          osType = tostring(properties.osType),
          hyperVGeneration = tostring(properties.hyperVGeneration),
          publisher = tostring(properties.identifier.publisher),
          offer = tostring(properties.identifier.offer),
          sku = tostring(properties.identifier.sku),
          imageVersion = tostring(properties.version.name)
'@
        storageContainers = @'
resources
| where type =~ "microsoft.azurestackhci/storagecontainers"
| project id, name, resourceGroup, subscriptionId, location,
          provisioningState = tostring(properties.provisioningState),
          status = tostring(properties.status.provisioningStatus.status),
          path = tostring(properties.path),
          availableSizeGB = round(properties.status.availableSizeBytes / 1073741824.0, 2),
          containerSizeGB = round(properties.status.containerSizeBytes / 1073741824.0, 2)
'@
        logAnalyticsWorkspaces = @'
resources | where type =~ "microsoft.operationalinsights/workspaces"
| extend retentionInDays = toint(properties.retentionInDays)
| project name, resourceGroup, retentionInDays
'@
        # ---- Azure Update Manager (AB#7065, Story AB#7065, Feature AB#7069, Epic AB#7099) -------
        # microsoft.maintenance/maintenanceconfigurations IS Resource Graph indexed (confirmed
        # against the ARG supported-tables-and-resource-types reference, same verification
        # standard as every other query in this file) -- the manifest
        # manifests/collectors/Management/MaintenanceConfigurations.psd1 already renders it as an
        # Excel worksheet, but nothing projected it into the scalar assessment shape until now.
        # Every field below mirrors a column that manifest already reads off the Az cmdlet
        # equivalent (maintenanceScope, maintenanceWindow.recurEvery/startDateTime/duration/
        # timeZone, installPatches.rebootSetting) -- documented MaintenanceConfiguration ARM
        # properties, kept as scalars so a rule never needs `.length`/array tricks (AB#5083).
        maintenanceConfigurations = @'
resources | where type =~ "microsoft.maintenance/maintenanceconfigurations"
| extend scope = tostring(properties.maintenanceScope)
| extend recurEvery = tostring(properties.maintenanceWindow.recurEvery)
| extend startDateTime = tostring(properties.maintenanceWindow.startDateTime)
| extend duration = tostring(properties.maintenanceWindow.duration)
| extend timeZone = tostring(properties.maintenanceWindow.timeZone)
| extend rebootSetting = tostring(properties.installPatches.rebootSetting)
| project name, resourceGroup, subscriptionId, scope, recurEvery, startDateTime, duration,
          timeZone, rebootSetting
'@
        # ---- AI workload domain additions (AB#6818) --------------------------------------------
        # `cognitiveAccounts` above already carries accountKind, so OpenAI/Applied-AI PaaS
        # presence is read from it directly (no new query needed for that half). What is missing
        # is the custom-build side of WAF-AI-APPD-06/APPP-03's PaaS-vs-custom comparison and the
        # grounding-pipeline existence check WAF-AI-GROUND-02 -- both need resource types
        # `cognitiveAccounts` does not cover.
        mlWorkspaces = @'
resources | where type =~ "microsoft.machinelearningservices/workspaces"
| extend workspaceKind = tostring(['kind'])
| extend publicAccess = tostring(properties.publicNetworkAccess)
| extend identityType = tostring(identity.type)
| project name, resourceGroup, workspaceKind, publicAccess, identityType
'@
        searchServices = @'
resources | where type =~ "microsoft.search/searchservices"
| project name, resourceGroup, sku = tostring(sku.name)
'@
        # ---- AVD (on Azure Local) workload domain additions (AB#6819) --------------------------
        # microsoft.desktopvirtualization/* and microsoft.azurestackhci/logicalnetworks are both
        # confirmed ARG-indexed resource types (Azure Resource Graph supported-tables-and-
        # resource-types reference) — same verification standard as every other query in this
        # file. Scout already renders these as Excel inventory collectors
        # (manifests/collectors/Compute/AVD*.psd1); this is the first time they are also
        # projected into the scalar `domains`/`compute` shape the rule engine reads.
        avdHostPools = @'
resources | where type =~ "microsoft.desktopvirtualization/hostpools"
| extend hostPoolType = tostring(properties.hostPoolType)
| extend loadBalancerType = tostring(properties.loadBalancerType)
| extend maxSessionLimit = toint(properties.maxSessionLimit)
| project name, resourceGroup, hostPoolType, loadBalancerType, maxSessionLimit
'@
        avdSessionHosts = @'
resources | where type =~ "microsoft.desktopvirtualization/hostpools/sessionhosts"
| extend hostPoolName = tostring(split(id, "/sessionHosts/")[0])
| extend status = tostring(properties.status)
| extend agentVersion = tostring(properties.agentVersion)
| project name, hostPoolName, status, agentVersion
'@
        avdScalingPlans = @'
resources | where type =~ "microsoft.desktopvirtualization/scalingplans"
| extend hostPoolRefCount = array_length(properties.hostPoolReferences)
| project name, resourceGroup, hostPoolRefCount
'@
        # NOTE: logicalNetworks (microsoft.azurestackhci/logicalnetworks) is declared once,
        # above, under the AB#6803 Azure Local block — that projection is a superset (adds
        # vmSwitchName/subnetCount/addressPrefix/vlan) of what AB#6819's AVD-on-Azure-Local
        # assessment needs, so it is reused rather than re-declared here.
        # ---- Azure VMware Solution (AB#6820, Epic AB#6454) -------------------------------------
        # Microsoft.AVS/privateClouds IS Resource Graph indexed (it is what the existing
        # Compute/VMWare.psd1 inventory collector already queries) -- unlike almost everything
        # else the WAF-AVS-* enumeration cites, the private-cloud resource itself is a normal ARM
        # resource, not vCenter/NSX-T/vSAN-internal state. Every field below is a documented
        # top-level property on the AVS PrivateCloud resource (verified against the
        # Microsoft.AVS/privateClouds ARM template reference before being added):
        #   availability.strategy / availability.zone  -- WAF-AVS-RE-04 (zonal/stretched-cluster)
        #   managementCluster.clusterSize               -- WAF-AVS-RE-05 (minimum host count)
        #   circuit.expressRouteID                       -- AVS-C5 (hub/vWAN connectivity)
        #   encryption.status                            -- WAF-AVS-SEC-05 (encryption enabled)
        #   internet                                     -- AVS-C3 (internet egress toggle)
        #   identitySources / externalCloudLinks          -- array counts only, no credential material
        privateClouds = @'
resources | where type =~ "microsoft.avs/privateclouds"
| extend availabilityStrategy = tostring(properties.availability.strategy)
| extend availabilityZone = tostring(properties.availability.zone)
| extend clusterSize = toint(properties.managementCluster.clusterSize)
| extend expressRouteCircuitId = tostring(properties.circuit.expressRouteID)
| extend encryptionStatus = tostring(properties.encryption.status)
| extend internet = tostring(properties.internet)
| extend identitySourceCount = array_length(properties.identitySources)
| extend externalCloudLinkCount = array_length(properties.externalCloudLinks)
| project id, name, resourceGroup, subscriptionId, sku = tostring(sku.name),
          availabilityStrategy, availabilityZone, clusterSize, expressRouteCircuitId,
          encryptionStatus, internet, identitySourceCount, externalCloudLinkCount
'@
        # ---- FinOps / DevOps Capability enumerations (AB#6826/AB#6827, Feature AB#6749) --------
        # Every query in this block is ARM/Resource Graph, Reader-scoped, and NEVER gated behind
        # the EA/MCA billing permission system or Azure DevOps org access -- that gate only
        # applies to the Cost Management API pull and the ADO REST calls, both handled by the
        # Import-ScoutCostInventory / Import-ScoutDevOpsCapability ingestors, not here. See
        # docs/frameworks/finops-review-question-set.md and
        # docs/frameworks/devops-capability-question-set.md.
        #
        # microsoft.capacity/reservationorders/reservations IS indexed by Resource Graph --
        # confirmed by the existing General/Reservations inventory collector, which matches this
        # exact type against the same `resources` table (ResourceTypeMatching: SinglePass).
        reservations = @'
resources | where type =~ "microsoft.capacity/reservationorders/reservations"
| project id, name, subscriptionId, provisioningState = tostring(properties.provisioningState),
          sku = tostring(sku.name)
'@
        # microsoft.devopsinfrastructure/pools (Managed DevOps Pools -- DEVOPS-OPS-01), and the
        # four Dev Center / testing / chaos service types DEVOPS-OPS-02/03 read, are all plain
        # ARM resource types with existing General/DevOps declarative collectors that already
        # match them against `resources` the same way -- ARG indexing is not new here, only the
        # JSON assessment shape is.
        managedDevOpsPools = @'
resources | where type =~ "microsoft.devopsinfrastructure/pools"
| project name, resourceGroup, subscriptionId
'@
        devCenters = @'
resources | where type in~ ("microsoft.devcenter/devcenters", "microsoft.devcenter/projects")
| project name, resourceGroup, subscriptionId, type
'@
        loadTesting = @'
resources | where type =~ "microsoft.loadtestservice/loadtests"
| project name, resourceGroup, subscriptionId
'@
        chaosExperiments = @'
resources | where type =~ "microsoft.chaos/experiments"
| project name, resourceGroup, subscriptionId
'@
        playwrightTesting = @'
resources | where type =~ "microsoft.azureplaywrightservice/accounts"
| project name, resourceGroup, subscriptionId
'@
        # ---- DevOps plumbing (AB#7110, Story AB#7059, Feature AB#7069, Epic AB#7099) ------------
        # Seven ordinary ARG-indexed DevOps types the DevOps(12) coverage-doc table listed as "not
        # wired" (the other five -- DevOpsAgentPools/Pipelines/Projects/Repositories/
        # ServiceConnections -- declare the org-level Azure DevOps REST `devops/*` synthetic type,
        # deliberately out of scope, see the file header).
        apiConnections = @'
resources | where type =~ "microsoft.web/connections"
| project id, name, resourceGroup, subscriptionId, location
'@
        appConfigurationStores = @'
resources | where type =~ "microsoft.appconfiguration/configurationstores"
| project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name)
'@
        deploymentEnvironmentTypes = @'
resources
| where type in~ ("microsoft.devcenter/devcenters/environmenttypes", "microsoft.devcenter/projects/environmenttypes",
                  "microsoft.devcenter/devcenters/catalogs", "microsoft.devcenter/projects/catalogs")
| project id, name, type, resourceGroup, subscriptionId
'@
        devBoxPools = @'
resources | where type =~ "microsoft.devcenter/projects/pools"
| extend licenseType = tostring(properties.licenseType)
| project id, name, resourceGroup, subscriptionId, location, licenseType
'@
        devCenterNetworkConnections = @'
resources | where type =~ "microsoft.devcenter/networkconnections"
| extend domainJoinType = tostring(properties.domainJoinType)
| project id, name, resourceGroup, subscriptionId, location, domainJoinType
'@
        devTestLabs = @'
resources | where type in~ ("microsoft.devtestlab/labs", "microsoft.devtestlab/schedules")
| project id, name, type, resourceGroup, subscriptionId, location
'@
        labServicesLabs = @'
resources | where type in~ ("microsoft.labservices/labs", "microsoft.labservices/labplans")
| project id, name, type, resourceGroup, subscriptionId, location
'@
        # AB#7064 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- the five Monitor collectors
        # deferred out of the first AB#7064 slice. `manifests/collectors/Monitor/*.psd1` for each
        # already exists and is confirmed ARG-indexed; this wires their query into the assessment
        # payload the same way the first slice wired dataCollectionRules etc. Every projection is
        # a scalar or a count (`array_length`) -- never an array a rule would need `.length` on
        # (AB#5083).
        appInsights = @'
resources
| where type =~ "microsoft.insights/components"
| project id, name, resourceGroup, subscriptionId, location,
          applicationType = tostring(properties.Application_Type),
          flowType = tostring(properties.Flow_Type),
          retentionInDays = toint(properties.RetentionInDays),
          samplingPercentage = tostring(properties.SamplingPercentage),
          ingestionMode = tostring(properties.IngestionMode),
          publicNetworkAccessForIngestion = tostring(properties.publicNetworkAccessForIngestion),
          publicNetworkAccessForQuery = tostring(properties.publicNetworkAccessForQuery)
'@
        workbooks = @'
resources
| where type =~ "microsoft.insights/workbooks"
| project id, name, resourceGroup, subscriptionId, location,
          kind = tostring(kind),
          category = tostring(properties.category),
          sourceId = tostring(properties.sourceId),
          version = tostring(properties.version)
'@
        privateLinkScopes = @'
resources
| where type =~ "microsoft.insights/privatelinkscopes"
| project id, name, resourceGroup, subscriptionId, location,
          accessMode = tostring(properties.accessModeSettings.queryAccessMode),
          ingestionAccessMode = tostring(properties.accessModeSettings.ingestionAccessMode),
          privateEndpointConnectionCount = array_length(properties.privateEndpointConnections),
          scopedResourceCount = array_length(properties.scopedResources)
'@
        workspaceSolutions = @'
resources
| where type =~ "microsoft.operationsmanagement/solutions"
| project id, name, resourceGroup, subscriptionId, location,
          workspaceResourceId = tostring(properties.workspaceResourceId),
          planName = tostring(plan.name),
          planPublisher = tostring(plan.publisher),
          planProduct = tostring(plan.product)
'@
        # `AppInsightsAvailabilityTests.psd1` and `AppInsightsWebTests.psd1` both match
        # `microsoft.insights/webtests` -- AvailabilityTests carries no `AdditionalFilter` (every
        # Kind), WebTests filters `$_.KIND -eq 'standard'` (a strict subset). One combined query
        # over every webtest row, carrying `kind` per row, reproduces both manifests' scope without
        # a second identical ARG round-trip; a consumer that needs the WebTests-only subset filters
        # this array on `kind -eq 'standard'` the same way the manifest's AdditionalFilter does.
        appInsightsAvailabilityTests = @'
resources
| where type =~ "microsoft.insights/webtests"
| project id, name, resourceGroup, subscriptionId, location,
          kind = tostring(kind),
          enabled = tobool(properties.Enabled),
          frequency = toint(properties.Frequency),
          timeoutSeconds = toint(properties.Timeout),
          syntheticMonitorId = tostring(properties.SyntheticMonitorId),
          testLocationCount = array_length(properties.Locations)
'@
        # AB#7064 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Azure Monitor plumbing.
        # `manifests/collectors/Monitor/*.psd1` for each of the eight types below already exist
        # and are confirmed ARG-indexed (ordinary `resources`-table rows, not a synthetic AZSC/*
        # sweep); this only wires their query into the assessment payload the way AB#7065/7066
        # wired maintenanceConfigurations/policyDefinitions. Every projection is a scalar or a
        # count (`array_length`) -- never an array a rule would need `.length` on (AB#5083).
        dataCollectionRules = @'
resources
| where type =~ "microsoft.insights/datacollectionrules"
| project id, name, resourceGroup, subscriptionId, location,
          dataCollectionEndpointId = tostring(properties.dataCollectionEndpointId),
          hasLogAnalyticsDestination = isnotnull(properties.destinations.logAnalytics),
          dataFlowCount = array_length(properties.dataFlows),
          immutableId = tostring(properties.immutableId)
'@
        dataCollectionEndpoints = @'
resources
| where type =~ "microsoft.insights/datacollectionendpoints"
| project id, name, resourceGroup, subscriptionId, location,
          publicNetworkAccess = tostring(properties.networkAcls.publicNetworkAccess),
          configurationAccessEndpoint = tostring(properties.configurationAccess.endpoint),
          immutableId = tostring(properties.immutableId)
'@
        actionGroups = @'
resources
| where type =~ "microsoft.insights/actiongroups"
| project id, name, resourceGroup, subscriptionId,
          enabled = tobool(properties.enabled),
          groupShortName = tostring(properties.groupShortName),
          emailReceiverCount = array_length(properties.emailReceivers),
          smsReceiverCount = array_length(properties.smsReceivers),
          webhookReceiverCount = array_length(properties.webhookReceivers)
'@
        autoscaleSettings = @'
resources
| where type =~ "microsoft.insights/autoscalesettings"
| project id, name, resourceGroup, subscriptionId, location,
          enabled = tobool(properties.enabled),
          targetResourceUri = tostring(properties.targetResourceUri),
          profileCount = array_length(properties.profiles)
'@
        metricAlertRules = @'
resources
| where type =~ "microsoft.insights/metricalerts"
| project id, name, resourceGroup, subscriptionId,
          enabled = tobool(properties.enabled),
          severity = toint(properties.severity),
          autoMitigate = tobool(properties.autoMitigate),
          scopeCount = array_length(properties.scopes),
          actionGroupCount = array_length(properties.actions)
'@
        scheduledQueryRules = @'
resources
| where type =~ "microsoft.insights/scheduledqueryrules"
| project id, name, resourceGroup, subscriptionId,
          enabled = tobool(properties.enabled),
          severity = toint(properties.severity),
          autoMitigate = tobool(properties.autoMitigate),
          kind = tostring(properties.kind),
          scopeCount = array_length(properties.scopes)
'@
        activityLogAlertRules = @'
resources
| where type =~ "microsoft.insights/activitylogalerts"
| project id, name, resourceGroup, subscriptionId,
          enabled = tobool(properties.enabled),
          scopeCount = array_length(properties.scopes),
          actionGroupCount = array_length(properties.actions.actionGroups)
'@
        smartDetectorAlertRules = @'
resources
| where type =~ "microsoft.alertsmanagement/smartdetectoralertrules"
| project id, name, resourceGroup, subscriptionId,
          state = tostring(properties.state),
          severity = tostring(properties.severity),
          frequency = tostring(properties.frequency),
          actionGroupCount = array_length(properties.actionGroups.groupIds)
'@
    }

    # ---- category tagging (AB#5057 follow-up) ----
    # Which manifest `Collect` categories need each query's output, derived from
    # every rule file's `query:` JSONPath (see .NOTES). '*' means "always run"
    # regardless of the requested categories.
    $queryCategories = @{
        subscriptions       = @('*')
        virtualNetworks     = @('Networking')
        subnets             = @('Networking', 'Compute')
        azureFirewalls      = @('Networking')
        firewallPolicyRuleGroups = @('Networking', 'Security')
        vpnGateways         = @('Networking')
        # caf.security (CAF-SEC-03/06), caf.ai (CAF-AI-04), caf.iot (CAF-IOT-05)
        # all filter networking.privateEndpoints by target — those categories need
        # this query too, not just Networking.
        privateEndpoints    = @('Networking', 'Security', 'AI', 'IoT')
        privateDnsZones     = @('Networking', 'Security')
        nsgPublicInbound    = @('Networking', 'Security')
        # AB#7110 -- 13 ordinary ARG-indexed Networking types.
        applicationGateways = @('Networking')
        bastionHosts        = @('Networking')
        networkConnections  = @('Networking')
        expressRouteCircuits = @('Networking')
        frontDoors          = @('Networking')
        loadBalancers       = @('Networking')
        natGateways         = @('Networking')
        networkInterfaces   = @('Networking')
        networkWatchers     = @('Networking')
        publicDnsZones      = @('Networking')
        routeTables         = @('Networking')
        trafficManagerProfiles = @('Networking')
        virtualWans         = @('Networking')
        virtualMachines     = @('Compute')
        # caf.billing (CAF-BIL-02/03) and waf.cost both need these under Management
        # and Compute/Cost respectively.
        orphanedDisks       = @('Compute', 'Cost', 'Management')
        orphanedPips        = @('Compute', 'Cost', 'Management')
        diagnosticCoverage  = @('Monitor', 'Management')
        deployments         = @('Monitor', 'Management')
        storageAccounts     = @('Storage')
        sqlDatabases        = @('Databases')
        # waf.security (WAF-SE-03) filters domains.databases.sqlServers too.
        sqlServers          = @('Databases', 'Security')
        sqlDefenderPricing  = @('Databases')
        webApps             = @('Web')
        aksClusters         = @('Containers')
        containerRegistries = @('Containers')
        # AB#7110 -- 4 ordinary ARG-indexed Containers types.
        openShiftClusters   = @('Containers')
        containerApps       = @('Containers')
        containerAppEnvironments = @('Containers')
        containerGroups     = @('Containers')
        keyVaults           = @('Security')
        # AB#7063 -- ordinary Networking-typed resources that are also Security-scoped review
        # subjects (same reasoning as firewallPolicyRuleGroups/nsgPublicInbound above).
        wafPolicies               = @('Networking', 'Security')
        ddosProtectionPlans       = @('Networking', 'Security')
        applicationSecurityGroups = @('Networking', 'Security')
        # The cross-resource rule set spans categories by definition, so its sources must be
        # gathered whenever EITHER side's category was asked for -- a -Category Compute run that
        # skipped backupProtectedItems would silently Pass "every VM has a backup" (AB#6835).
        backupProtectedItems = @('Compute', 'Management', 'Security')
        snapshots           = @('Compute', 'Storage', 'Cost', 'Management')
        managedDisks        = @('Compute', 'Storage', 'Cost', 'Management')
        diskEncryptionSets  = @('Compute', 'Storage', 'Security')
        migrateProjects     = @('Migration')
        migrationServices   = @('Migration')
        discoverySites      = @('Migration')
        cognitiveAccounts   = @('AI')
        arcServers          = @('Hybrid')
        # AB#7107/AB#7108 -- Azure Update Manager patch state spans Azure VMs (Compute) and
        # Arc-enabled servers (Hybrid) equally, and the owner named Update Manager itself as core
        # Management-pillar data (AB#7059's description), so all three categories must gather it.
        patchAssessments    = @('Compute', 'Hybrid', 'Management')
        patchInstallations  = @('Compute', 'Hybrid', 'Management')
        arcExtensions       = @('Hybrid')
        azureLocalClusters  = @('Hybrid')
        logicalNetworks     = @('Hybrid')
        # AB#7061 -- Azure Local child resources (gallery/marketplace images, storage containers,
        # remaining Arc-adjacent types).
        arcDataControllers       = @('Hybrid')
        arcGateways              = @('Hybrid')
        arcKubernetes            = @('Hybrid')
        arcResourceBridge        = @('Hybrid')
        arcSqlManagedInstances   = @('Hybrid')
        arcSqlServers            = @('Hybrid')
        galleryImages            = @('Hybrid')
        marketplaceGalleryImages = @('Hybrid')
        storageContainers        = @('Hybrid')
        eventHubNamespaces  = @('Integration')
        apiManagement       = @('Integration')
        serviceBusNamespaces = @('Integration')
        iotHubs             = @('IoT')
        dpsInstances        = @('IoT')
        digitalTwinsInstances = @('IoT')
        synapseWorkspaces   = @('Analytics')
        purviewAccounts     = @('Analytics')
        # AB#7110 -- 3 ordinary ARG-indexed Analytics types.
        databricksWorkspaces = @('Analytics')
        dataExplorerClusters = @('Analytics')
        streamAnalyticsJobs  = @('Analytics')
        logAnalyticsWorkspaces = @('Management', 'Monitor')
        # AB#7065 (Azure Update Manager) — patch-schedule coverage spans the ordinary Management
        # pillar and the Azure Local operational checklist (waf.azurelocal.operational.yaml's
        # Update Manager composite item), so both categories must gather it.
        maintenanceConfigurations = @('Management', 'Hybrid')
        # AB#6818 (AI workload assessment) — waf.ai.yaml's WAF-AI-* rules.
        mlWorkspaces        = @('AI')
        searchServices      = @('AI')
        # AB#6819 (AVD workload assessment) — waf.avd.yaml's WAF-AVD-* rules. AVD-on-Azure-Local
        # is Compute + Hybrid data, so both categories must gather these, not just one.
        avdHostPools        = @('Compute', 'Hybrid')
        avdSessionHosts     = @('Compute', 'Hybrid')
        avdScalingPlans     = @('Compute', 'Hybrid')
        # NOTE: logicalNetworks is already declared once above (Hybrid, line ~827) -- not
        # re-declared here, see the AB#6803 collector-declaration comment for why.
        # avs.workload (WAF-AVS-*) and caf.avslandingzone (AVS-*) both read this -- AB#6820.
        privateClouds       = @('Compute')
        reservations        = @('FinOps', 'Cost', 'Management')
        managedDevOpsPools  = @('DevOps', 'Management')
        devCenters          = @('DevOps', 'Management')
        loadTesting         = @('DevOps', 'Management')
        chaosExperiments    = @('DevOps', 'Management')
        playwrightTesting   = @('DevOps', 'Management')
        # AB#7110 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Databases plumbing.
        cosmosDbAccounts         = @('Databases')
        mariaDbServers           = @('Databases')
        mySqlServers             = @('Databases')
        mySqlFlexibleServers     = @('Databases')
        postgreSqlFlexibleServers = @('Databases')
        redisCaches              = @('Databases')
        sqlManagedInstances      = @('Databases')
        sqlManagedInstanceDatabases = @('Databases')
        sqlElasticPools          = @('Databases')
        sqlVirtualMachines       = @('Databases')
        # AB#7110 -- Web plumbing.
        appServiceCertificates   = @('Web')
        appServiceDomains        = @('Web')
        appServiceEnvironments   = @('Web')
        appServicePlans          = @('Web')
        communicationServices    = @('Web')
        webAppDeploymentSlots    = @('Web')
        fluidRelayServers        = @('Web')
        notificationHubNamespaces = @('Web')
        signalRServices          = @('Web')
        springApps               = @('Web')
        staticWebApps            = @('Web')
        webPubSubServices        = @('Web')
        # AB#7110 -- Security plumbing (wafPolicies/ddosProtectionPlans/applicationSecurityGroups
        # already tagged above via AB#7063).
        appComplianceReports      = @('Security')
        artifactSigningAccounts   = @('Security')
        cloudHsmClusters          = @('Security')
        confidentialLedgers       = @('Security')
        entraDomainServices       = @('Security')
        managedHsms               = @('Security')
        sentinelWorkspaces        = @('Security')
        # AB#7110 -- Storage plumbing.
        edgeHardwareCenterOrders  = @('Storage')
        elasticSanVolumeGroups    = @('Storage')
        netAppVolumes             = @('Storage')
        partnerStorageResources   = @('Storage')
        storageSyncServices       = @('Storage')
        # AB#7110 -- Management plumbing.
        advisorScores                = @('Management')
        automationAccounts           = @('Management')
        recoveryVaultBackupPolicies  = @('Management')
        lighthouseDelegations        = @('Management')
        # AB#7110 -- Identity plumbing.
        managedIdentities         = @('Identity')
        # AB#7110 -- DevOps plumbing.
        apiConnections             = @('DevOps')
        appConfigurationStores     = @('DevOps')
        deploymentEnvironmentTypes = @('DevOps')
        devBoxPools                = @('DevOps')
        devCenterNetworkConnections = @('DevOps')
        devTestLabs                = @('DevOps')
        labServicesLabs            = @('DevOps')
        # AB#7064 -- dataCollectionRules/dataCollectionEndpoints are also tagged Hybrid: they are
        # the AMA-agent plumbing Arc-enabled servers and Azure Local clusters route telemetry
        # through, the same reasoning logAnalyticsWorkspaces above is tagged Management+Monitor.
        dataCollectionRules    = @('Monitor', 'Hybrid')
        dataCollectionEndpoints = @('Monitor', 'Hybrid')
        actionGroups            = @('Monitor')
        autoscaleSettings       = @('Monitor')
        metricAlertRules        = @('Monitor')
        scheduledQueryRules     = @('Monitor')
        activityLogAlertRules   = @('Monitor')
        smartDetectorAlertRules = @('Monitor')
        # AB#7064 -- ordinary Monitor-native resources, same category as the first AB#7064 slice.
        appInsights                  = @('Monitor')
        workbooks                    = @('Monitor')
        privateLinkScopes            = @('Monitor')
        workspaceSolutions           = @('Monitor')
        appInsightsAvailabilityTests = @('Monitor')
    }

    $runAllCategories = (-not $Categories) -or (@($Categories).Count -eq 0) -or ($Categories -contains '*')
    $selectedKeys = if ($runAllCategories) {
        $q.Keys
    }
    else {
        $q.Keys | Where-Object {
            $cats = $queryCategories[$_]
            $cats -and (($cats -contains '*') -or ($Categories | Where-Object { $cats -contains $_ }))
        }
    }

    function Invoke-Arg {
        param([string] $Query, [string] $SubscriptionId, [switch] $OmitManagementGroup)
        $rows = @(); $skip = 0
        do {
            # Search-AzGraph rejects -Skip 0 (ValidateRange minimum is 1) — omit it on the first page.
            $params = @{ Query = $Query; First = 1000; ErrorAction = 'Stop' }
            if ($skip -gt 0) { $params.Skip = $skip }
            # -ManagementGroup and -Subscription are DIFFERENT, mutually exclusive
            # Search-AzGraph parameter sets (ManagementGroupScopedQuery vs.
            # SubscriptionScopedQuery) — passing both throws an ambiguous-parameter-set
            # error, so a per-subscription call (below, AB#397) always omits
            # -ManagementGroup regardless of whether one was supplied for this run.
            if ($ManagementGroupId -and -not $OmitManagementGroup) { $params.ManagementGroup = $ManagementGroupId }
            if ($SubscriptionId) { $params.Subscription = @($SubscriptionId) }
            # AB#6779. `@(Search-AzGraph @params)` collects the PSResourceGraphResponse WRAPPER as
            # a single element rather than the rows -- always, not only when the result is empty.
            # That made $batch.Count permanently 1, so this loop's `-eq 1000` condition could NEVER
            # fire and every query here was silently capped at its first page. Reading `.Data` is
            # the only shape that behaves the same whether the result is empty or not.
            # Assigned in STATEMENTS, not as `$batch = if (...) { @($response.Data) }`: an if-block
            # yields its body through the output stream and an EMPTY array contributes zero objects
            # to it, so the expression form assigns $null on exactly the empty result this handles,
            # and `$batch.Count` below then throws under StrictMode.
            $response = Search-AzGraph @params
            $batch = @()
            if ($null -ne $response -and $response.PSObject.Properties['Data']) {
                $batch = @($response.Data)
            }
            elseif ($null -ne $response) {
                $batch = @($response)
            }
            $rows += $batch; $skip += 1000
        } while ($batch.Count -eq 1000)
        return , $rows
    }

    # A small set of ARG/ARM errors are documented, KNOWN FALSE POSITIVES — most
    # commonly a "resource provider not registered" condition reported for a
    # subscription that Resource Graph can (and does) still query successfully
    # (AB#399). These are noise, not a real collection gap: log at Verbose and move
    # on without a warning or a per-subscription retry.
    function Test-ScoutKnownNoiseError([string] $Message) {
        return [bool]($Message -match '(?i)resource provider.*not\s+registered' -or
                       $Message -match '(?i)MissingSubscriptionRegistration' -or
                       $Message -match '(?i)SubscriptionNotRegistered')
    }

    function Invoke-CollectQuery {
        param([string] $Key, [string] $Query, [string[]] $SubscriptionIds)
        try {
            return Invoke-Arg -Query $Query
        }
        catch {
            $errText = $_.Exception.Message

            # AB#399 — known noise: log at Verbose only, no retry, no warning.
            if (Test-ScoutKnownNoiseError $errText) {
                Write-Verbose "Invoke-Collect: query '$Key' hit the known false 'resource provider not registered' condition — ignoring (AB#399): $errText"
                # `return @()` (without the leading comma) gets pipeline-UNROLLED to
                # zero output objects -- the caller's `$r[$k] = Invoke-CollectQuery ...`
                # would capture $null instead of an empty array. The unary comma
                # prevents that (same idiom Invoke-Arg already uses for `$rows`).
                return , @()
            }

            # AB#398 — an AuthorizationFailed error on an MG-scoped query is almost
            # always a missing Reader assignment AT THE MANAGEMENT GROUP (a Reader
            # role at subscription scope alone does not satisfy an MG-scoped ARG
            # query), so surface that as an explicit, actionable hint.
            if ($ManagementGroupId -and $errText -match '(?i)AuthorizationFailed') {
                Write-Warning "Invoke-Collect: query '$Key' failed with AuthorizationFailed while scoped to management group '$ManagementGroupId'. Hint: assign the caller (user or service principal) the Reader role at the '$ManagementGroupId' management group scope — a Reader role assigned only at a subscription underneath it is not sufficient for a management-group-scoped Resource Graph query."
            }
            else {
                Write-Warning "Invoke-Collect: query '$Key' failed: $errText"
            }

            # AB#397 — fall back to one query per known subscription instead of losing
            # the whole dataset for this resource type: a single subscription with a
            # transient/DNS/token problem must not blank out every OTHER
            # subscription's data for the same query.
            if (-not $SubscriptionIds -or @($SubscriptionIds).Count -eq 0) { return , @() }

            $rows = @()
            foreach ($subId in $SubscriptionIds) {
                try { $rows += Invoke-Arg -Query $Query -SubscriptionId $subId -OmitManagementGroup }
                catch {
                    $subErrText = $_.Exception.Message
                    if (Test-ScoutKnownNoiseError $subErrText) {
                        Write-Verbose "Invoke-Collect: query '$Key' hit the known false 'resource provider not registered' condition for subscription '$subId' — ignoring (AB#399): $subErrText"
                        continue
                    }
                    Write-Warning "Invoke-Collect: query '$Key' failed for subscription '$subId' — skipping this subscription and continuing with the rest (AB#397): $subErrText"
                }
            }
            return , $rows
        }
    }

    $r = @{}

    # ---- reuse an inventory pass instead of re-querying Azure (AB#5543) ----
    # Start-AZSCGraphExtraction already projects the FULL `properties` bag from `resources`,
    # `networkresources` and `resourcecontainers`, which is a superset of what the typed queries
    # above re-fetch. When those rows are handed in, shape them locally so the run costs one
    # collection pass instead of two.
    #
    # `sqlDefenderPricing` is deliberately NOT satisfiable this way: it reads the
    # SecurityResources table (Microsoft.Security/pricings), which inventory only touches under
    # -SecurityCenter and then filters to microsoft.security/assessments. It still goes to ARG.
    #
    # AB#5648 inverted the default: when NO rows were handed in and -Source is 'Inventory'
    # (the default), this function now makes that single raw pass ITSELF rather than falling
    # through to 35 typed queries. `-Source TypedQueries` opts back into the typed pack.
    $rawInventory = $FromInventory
    if (-not $rawInventory -and $Source -eq 'Inventory') {
        if (-not (Get-Command Get-ScoutRawInventory -ErrorAction SilentlyContinue)) {
            . (Join-Path $PSScriptRoot 'Get-ScoutRawInventory.ps1')
        }
        try {
            # Only the three tables ConvertFrom-ScoutInventory actually shapes from. The
            # -Include* tables (support tickets, backup, AVD, advisor, security assessments)
            # feed inventory REPORT collectors, not assessment scalars, so collecting them here
            # would be round-trips for rows nothing downstream of this function reads.
            #
            # -IncludeTags is REQUIRED here, not optional. The canonical contract's top-level
            # `tags` key is aggregated from `subscriptions[*].tags` (AB#367), and
            # ConvertFrom-ScoutInventory reads that straight off the raw container row. The raw
            # pass omits the `tags` COLUMN unless asked, so without this switch the inverted
            # path would return `tags = @()` for every estate while the typed path returned the
            # real aggregation -- a silently empty report section, not an error. Found by the
            # path-equivalence test below, not by a live run.
            #
            # -IncludeBackupResources is the ONE -Include* switch this path does need, added by
            # AB#6835. Its rationale above -- "the -Include* tables feed inventory REPORT
            # collectors, not assessment scalars" -- was true when written and is not true for
            # this one: `recoveryservicesresources` carries the backup protected items that
            # XR-BKP-01 ("which VMs have no backup") joins virtual machines against, and no other
            # table can supply them. It is a fifth Resource Graph round-trip on the default
            # assessment collect, up from four, and it is the only round-trip AB#6741 added.
            #
            # Tenant-wide collection is the AB#6755 half. Management groups, custom role
            # definitions, policy definitions and policy set definitions are what the Landing
            # Zone, AVS Landing Zone, Cloud Governance and CASA assessments score, and no
            # production caller had ever set the switch that collects them -- so those four
            # rule sets were reading empty arrays and passing. It is unconditional now and there
            # is no parameter here to set: Get-ScoutRawInventory always collects it.
            #
            # -TenantWideDefinitionsOnly keeps the price honest: this path wants the four
            # envelopes, not the five inventory-report datasets the same sweep can return, so
            # it pays two REST calls per subscription rather than seven. -SkipApiResourceSweep
            # is deliberately NOT set, because the policy definitions are the point.
            # AB#6821 (Feature AB#6748, Epic AB#6454) -- CASA scores confidentiality/integrity
            # controls that live on Key Vault CHILD objects (a secret's contentType distinguishes
            # a certificate from a plain secret; both carry attributes.enabled/exp), which are not
            # Resource Graph indexed -- only reachable via the vault's own ARM REST child listing.
            # -ArmChildDataset scopes Get-ScoutArmChildResource to exactly these two datasets
            # (KeyVaultSecrets, KeyVaultKeys) rather than its full 'All' sweep (ML/Search/Storage/
            # Backup/diagnostics children an assessment collect has no rule that reads), so the
            # added cost is bounded to two REST calls per Key Vault in scope, not per-parent across
            # every dataset the declarative inventory collectors need.
            #
            # -IncludeUpdateManagerResources (AB#7107 AB#7108, Story AB#7059, Feature AB#7069,
            # Epic AB#7099) is the second -Include* switch this path needs, added the same way
            # -IncludeBackupResources was by AB#6835 above: `patchassessmentresources` and
            # `patchinstallationresources` are their OWN Resource Graph tables (NOT part of the
            # default `resources`/`networkresources` pass), so nothing short of asking for them by
            # name ever returns Update Manager's patch state. Two more Resource Graph round-trips
            # on the default assessment collect, same tradeoff class as the backup-items call.
            $rawArgs = @{
                IncludeTags = $true; IncludeBackupResources = $true; TenantWideDefinitionsOnly = $true
                IncludeArmChildResources = $true; ArmChildDataset = @('KeyVaultSecrets', 'KeyVaultKeys')
                IncludeUpdateManagerResources = $true
            }
            if ($ManagementGroupId) { $rawArgs.ManagementGroupId = $ManagementGroupId }
            # AB#6803 -- -IncludeAzureLocalArm turns on BOTH switches this needs:
            # -IncludeArmChildResources (the per-parent AzureLocalVirtualMachineInstances sweep)
            # and dropping -TenantWideDefinitionsOnly to $false (the fuller ARM REST sweep that
            # actually issues the Arc-sites call -- see Get-ScoutApiResources, which gates that
            # call behind `-not $DefinitionsOnly`). The four -DefinitionsOnly envelopes
            # (management groups, custom roles, policy/policy-set definitions) are still
            # collected either way; this only adds calls, never removes any.
            if ($IncludeAzureLocalArm) {
                $rawArgs.IncludeArmChildResources = $true
                $rawArgs.TenantWideDefinitionsOnly = $false
            }
            $rawInventory = Get-ScoutRawInventory @rawArgs
        }
        catch {
            # A failed raw pass must not cost the caller their assessment: fall through to the
            # typed pack, which is the reference implementation.
            Write-Warning "Invoke-Collect: the single-pass raw collection failed, falling back to the typed Resource Graph queries (AB#5648): $($_.Exception.Message)"
            $rawInventory = $null
        }
    }

    # ---- governance, collected once by the raw pass (AB#6779) ---------------------------------
    # Role assignments, policy assignments, resource locks and budgets used to be collected by
    # Import-Governance, which ran AFTER this function and threw the rows away as soon as the
    # rules had read them -- no collector rendered them, so no worksheet could answer "who has
    # Owner". Get-ScoutRawInventory now collects them (so the four new inventory collectors have
    # something to render) and hands them up here; Import-Governance skips whatever it finds
    # already populated below. The queries MOVED; none was added.
    #
    # Empty when no raw pass ran at all (-Source TypedQueries), in which case Import-Governance
    # collects them exactly as it always did.
    $rawGovernance = [pscustomobject]@{
        roleAssignments = @(); policyAssignments = @(); budgets = @(); resourceLocks = @()
    }
    if ($rawInventory -and $rawInventory.PSObject.Properties['Governance'] -and $rawInventory.Governance) {
        $governanceSource = $rawInventory.Governance
        foreach ($key in @('roleAssignments', 'policyAssignments', 'budgets', 'resourceLocks')) {
            if ($governanceSource.PSObject.Properties[$key]) {
                $rawGovernance.$key = @($governanceSource.$key | Where-Object { $_ })
            }
        }
        Write-Verbose ('Invoke-Collect: governance came from the raw pass (AB#6779) -- roleAssignments={0} policyAssignments={1} budgets={2} resourceLocks={3}; Import-Governance will not re-query them.' -f `
                $rawGovernance.roleAssignments.Count, $rawGovernance.policyAssignments.Count,
                $rawGovernance.budgets.Count, $rawGovernance.resourceLocks.Count)
    }

    $inventoryShaped = @{}
    if ($rawInventory) {
        if (-not (Get-Command ConvertFrom-ScoutInventory -ErrorAction SilentlyContinue)) {
            . (Join-Path $PSScriptRoot 'ConvertFrom-ScoutInventory.ps1')
        }
        try {
            $invResources = if ($rawInventory.PSObject.Properties['Resources']) { $rawInventory.Resources } else { @() }
            $invContainers = if ($rawInventory.PSObject.Properties['ResourceContainers']) { $rawInventory.ResourceContainers } else { @() }
            $inventoryShaped = ConvertFrom-ScoutInventory -Resources $invResources -ResourceContainers $invContainers
            Write-Verbose "Invoke-Collect: shaping $($inventoryShaped.Keys.Count) queries from one collection pass (AB#5543/AB#5648); only 'sqlDefenderPricing' still goes to Resource Graph."
        }
        catch {
            # Never let a shaping bug cost the caller their assessment — fall back to the ARG
            # path, which is the reference implementation.
            Write-Warning "Invoke-Collect: could not shape the collection pass, falling back to Resource Graph queries (AB#5543): $($_.Exception.Message)"
            $inventoryShaped = @{}
        }
    }

    # Always collect `subscriptions` first, regardless of hashtable enumeration
    # order, so its subscription-id list is available for the AB#397 per-subscription
    # fallback used by every OTHER query below.
    $subscriptionIds = @()
    if ($selectedKeys -contains 'subscriptions' -and $inventoryShaped.ContainsKey('subscriptions')) {
        $r['subscriptions'] = @($inventoryShaped['subscriptions'])
        $subscriptionIds = @($r['subscriptions'] | ForEach-Object {
                if ($_ -and $_.PSObject.Properties['id']) { $_.id }
            } | Where-Object { $_ })
    }
    elseif ($selectedKeys -contains 'subscriptions') {
        try {
            $r['subscriptions'] = Invoke-Arg -Query $q['subscriptions']
            $subscriptionIds = @($r['subscriptions'] | ForEach-Object {
                    if ($_ -and $_.PSObject.Properties['id']) { $_.id }
                } | Where-Object { $_ })
        }
        catch {
            Write-Warning "Invoke-Collect: query 'subscriptions' failed: $_ — the per-subscription retry (AB#397) is unavailable for the rest of this run because the subscription list itself could not be collected."
            $r['subscriptions'] = @()
        }
    }

    $progressAvailable = [bool](Get-Command Write-ScoutProgress -ErrorAction SilentlyContinue)
    $remainingKeys = @($q.Keys | Where-Object { $_ -ne 'subscriptions' })
    $queryIndex = 0
    foreach ($k in $remainingKeys) {
        $queryIndex++
        if ($selectedKeys -notcontains $k) { $r[$k] = @(); continue }
        # AB#5543 — already satisfied from the inventory pass; do not query Azure again.
        if ($inventoryShaped.ContainsKey($k)) { $r[$k] = @($inventoryShaped[$k]); continue }
        if ($progressAvailable) {
            $pct = if (@($remainingKeys).Count -gt 0) { [Math]::Min(100, [Math]::Round(($queryIndex / @($remainingKeys).Count) * 100)) } else { -1 }
            try { Write-ScoutProgress -Activity 'Scout Collect' -Status "Querying: $k" -PercentComplete $pct -Id 1 }
            catch { Write-Verbose "Invoke-Collect: Write-ScoutProgress failed, continuing without progress UX: $_" }
        }
        $r[$k] = Invoke-CollectQuery -Key $k -Query $q[$k] -SubscriptionIds $subscriptionIds
    }
    if ($progressAvailable) {
        try { Write-ScoutProgress -Activity 'Scout Collect' -Id 1 -Completed }
        catch { Write-Verbose "Invoke-Collect: Write-ScoutProgress completion call failed: $_" }
    }

    # AB#6803 (Feature AB#6747, Epic AB#6454) — `arcSites` and
    # `azureLocalVirtualMachineInstances` have NO `$q` entry above and never can: both are ARM
    # REST datasets Resource Graph does not index (AB#6801/AB#6802), so there is no KQL that
    # could produce them under `-Source TypedQueries`. They exist ONLY when
    # `-IncludeAzureLocalArm` asked `Get-ScoutRawInventory` to collect them and
    # `ConvertFrom-ScoutInventory` shaped rows out of the result; every other path (including a
    # normal default collect with the switch unset) leaves them as the empty array assigned here,
    # which is the correct, honest answer -- "not asked", not "asked and found none". Assigned
    # explicitly, outside the `$q.Keys` loop above, because a hashtable key with no `$q` entry is
    # never visited by that loop and `$r.arcSites` would otherwise be an access to a key that was
    # never set.
    $r['arcSites'] = if ($inventoryShaped.ContainsKey('arcSites')) { @($inventoryShaped['arcSites']) } else { @() }
    $r['azureLocalVirtualMachineInstances'] = if ($inventoryShaped.ContainsKey('azureLocalVirtualMachineInstances')) { @($inventoryShaped['azureLocalVirtualMachineInstances']) } else { @() }

    # AB#6896. `recoveryVaults` is the SAME case and was missed: AB#6895 taught
    # ConvertFrom-ScoutInventory to shape Recovery Services vaults out of the raw `resources`
    # rows, but gave it no `$q` entry (there is no typed KQL for it) -- so the copy loop above,
    # which walks `$q.Keys` and nothing else, never visited the key and the shaped vaults were
    # dropped on the floor. The AB#6895 fix was therefore a no-op in production: vaults still
    # reported zero on every run while `backupProtectedItems` returned rows, which is the
    # vanishing-parent class (AB#6845) it was supposed to close.
    # `Collect.ShapedDatasetsReachTheResult.Tests.ps1` now fails if any shaped dataset is left
    # without a `$q` entry and without an explicit copy here, so the next one cannot go unnoticed.
    $r['recoveryVaults'] = if ($inventoryShaped.ContainsKey('recoveryVaults')) { @($inventoryShaped['recoveryVaults']) } else { @() }

    # ---- firewall policy rule-collection group parsing (AB#400) ----
    # properties.ruleCollections is a nested dynamic array (rule collections -> rules)
    # that Resource Graph hands back as-is; walking it needs real conditional logic,
    # not just KQL projection, so the walk happens here in PowerShell. A single
    # malformed/unexpected-shape rule-collection group must not blank out every OTHER
    # (perfectly fine) group from the same run, so each row gets its own try/catch —
    # a parse error is logged per-group, not per-run, and collection continues with a
    # placeholder entry that records what happened via `parseError`.
    $firewallPolicyRuleGroups = @()
    foreach ($group in $r['firewallPolicyRuleGroups']) {
        if (-not $group) { continue }
        try {
            $ruleCollections = @($group.ruleCollections)
            $ruleCount = 0
            foreach ($rc in $ruleCollections) { $ruleCount += @($rc.rules).Count }
            $firewallPolicyRuleGroups += [pscustomobject]@{
                name                = $group.name
                resourceGroup       = $group.resourceGroup
                policyName          = $group.policyName
                priority            = $group.priority
                ruleCollectionCount = $ruleCollections.Count
                ruleCount           = $ruleCount
                parseError          = $null
            }
        }
        catch {
            Write-Warning "Invoke-Collect: firewall policy rule-collection group '$($group.name)' (policy '$($group.policyName)') failed to parse — skipping this group and continuing (AB#400): $($_.Exception.Message)"
            $firewallPolicyRuleGroups += [pscustomobject]@{
                name                = $group.name
                resourceGroup       = $group.resourceGroup
                policyName          = $group.policyName
                priority            = $group.priority
                ruleCollectionCount = 0
                ruleCount           = 0
                parseError          = $_.Exception.Message
            }
        }
    }

    # ---- empty-data guard (AB#401) ----
    # A collect that returns literally nothing across every requested query is a
    # strong signal something is mis-configured (missing Reader RBAC, the wrong
    # tenant/subscription selected in the current Az context, an empty or
    # inaccessible -ManagementGroupId, or a -Categories filter that matched nothing)
    # rather than a genuinely empty estate — surface a diagnostic hint instead of
    # silently handing an empty dataset to the assess/report layers.
    $totalRows = 0
    foreach ($k in $r.Keys) { $totalRows += @($r[$k]).Count }
    if ($totalRows -eq 0) {
        $scopeHint = if ($ManagementGroupId) { "management group '$ManagementGroupId'" } else { 'the current subscription/tenant context' }
        Write-Warning ("Invoke-Collect: no resources were returned for any collected query, scoped to {0}. This usually means (1) the signed-in identity is missing the Reader role at that scope, (2) the wrong tenant/subscription is selected in the current Az context, (3) -ManagementGroupId points at an empty or inaccessible management group, or (4) -Categories filtered out every query that would otherwise have run — verify RBAC and scope before treating this as a genuinely empty estate." -f $scopeHint)
    }

    # ---- unique tag-key/value aggregation across subscriptions (AB#367) ----
    # $r.subscriptions[*].tags is a per-subscription dynamic bag (the KQL `tags`
    # column deserializes to a PSCustomObject keyed by tag name, or $null when a
    # subscription has no tags). The old code just concatenated those raw bags
    # (`ForEach-Object { $_.tags }`), which duplicated a value every time two
    # subscriptions shared it and never actually rolled values up per key.
    # Aggregate into one entry per distinct tag KEY with the deduplicated, sorted
    # set of values seen for that key across every subscription instead.
    $tagValuesByKey = [ordered]@{}
    foreach ($sub in $r.subscriptions) {
        $bag = $sub.tags
        if ($null -eq $bag) { continue }
        foreach ($prop in $bag.PSObject.Properties) {
            $key = $prop.Name
            $value = $prop.Value
            if ($null -eq $value) { continue }
            if (-not $tagValuesByKey.Contains($key)) {
                $tagValuesByKey[$key] = [System.Collections.Generic.HashSet[string]]::new()
            }
            [void] $tagValuesByKey[$key].Add([string] $value)
        }
    }
    $tags = @(
        foreach ($key in ($tagValuesByKey.Keys | Sort-Object)) {
            [pscustomobject]@{
                key    = $key
                values = @($tagValuesByKey[$key] | Sort-Object)
            }
        }
    )

    # ---- policy compliance state and initiative definitions (AB#6792/#6793/#6794) ------------
    # `policyInitiatives` costs NO extra Azure call: Get-ScoutRawInventory's tenant-wide pass
    # (above, TenantWideDefinitionsOnly) already collects policy set definitions unconditionally
    # for every assessment collect, as `AZSC/Management/PolicySetDefinition` envelope rows in
    # $rawInventory.Resources -- nothing downstream of this function read them before this
    # feature. Extracting them here adds zero round-trips.
    $policyInitiatives = @()
    if ($rawInventory -and $rawInventory.PSObject.Properties['Resources'] -and $rawInventory.Resources) {
        $initiativeEnvelope = @($rawInventory.Resources | Where-Object { $_ -and $_.PSObject.Properties['type'] -and $_.type -eq 'AZSC/Management/PolicySetDefinition' })
        $policyInitiatives = @(
            foreach ($envelope in $initiativeEnvelope) {
                if (-not $envelope.PSObject.Properties['properties'] -or -not $envelope.properties) { continue }
                foreach ($item in @($envelope.properties)) {
                    if (-not $item) { continue }
                    # Raw ARM REST list-response shape (camelCase); PowerShell property lookup is
                    # case-insensitive, so `.Id`/`.DisplayName` below match the JSON `id`/
                    # `displayName` keys without a separate case-normalising pass.
                    $itemId = if ($item.PSObject.Properties['Id']) { [string]$item.Id } else { $null }
                    if ([string]::IsNullOrWhiteSpace($itemId)) { continue }
                    $props = if ($item.PSObject.Properties['Properties']) { $item.Properties } else { $null }
                    $displayName = if ($props -and $props.PSObject.Properties['DisplayName']) { [string]$props.DisplayName } else { $null }
                    $policyType  = if ($props -and $props.PSObject.Properties['PolicyType']) { [string]$props.PolicyType } else { $null }
                    $version = $null
                    if ($props -and $props.PSObject.Properties['Metadata'] -and $props.Metadata -and $props.Metadata.PSObject.Properties['Version']) {
                        $version = [string]$props.Metadata.Version
                    }
                    $policyCount = $null
                    if ($props -and $props.PSObject.Properties['PolicyDefinitions'] -and $props.PolicyDefinitions) {
                        $policyCount = @($props.PolicyDefinitions).Count
                    }
                    [pscustomobject]@{
                        Id          = $itemId
                        DisplayName = $displayName
                        PolicyType  = $policyType
                        Version     = $version
                        PolicyCount = $policyCount
                    }
                }
            }
        )
        # A policy set definition can be visible from more than one subscription context in a
        # multi-subscription tenant (the built-in ones are tenant-global); collapse to one row
        # per distinct id so Resolve-ScoutAssignedInitiative sees each initiative once.
        $policyInitiatives = @($policyInitiatives | Sort-Object Id -Unique)
    }

    # ---- governance.policyDefinitions / governance.policySetDefinitions (AB#7066) -------------
    # Same source as `policyInitiatives` immediately above: Get-ScoutTenantWideResource already
    # appends AZSC/Management/PolicyDefinition and AZSC/Management/PolicySetDefinition envelopes
    # to $rawInventory.Resources on every assessment collect (the TenantWideDefinitionsOnly
    # sweep is unconditional -- see the $rawArgs comment above), so extracting them here adds
    # zero Azure round-trips, exactly like policyInitiatives.
    #
    # Unlike policyInitiatives (which flattens to five PascalCase scalar fields for
    # Resolve-ScoutAssignedInitiative), these rows are kept as the RAW ARM REST list-response
    # shape (id/name/type/properties) with `properties` whole -- the same convention
    # governance.policyAssignments above uses (Get-ScoutGovernanceDataset never flattens its
    # `properties` object either), so a rule's JSONPath (@.properties.policyType,
    # @.properties.metadata.category, @.properties.parameters, @.properties.policyRule.then.effect)
    # resolves against these exactly as it does against a policy assignment.
    function Get-ScoutTenantWideDefinitionRow {
        param([Parameter(Mandatory)] [string] $EnvelopeType)
        @(
            if ($rawInventory -and $rawInventory.PSObject.Properties['Resources'] -and $rawInventory.Resources) {
                $envelopes = @($rawInventory.Resources | Where-Object { $_ -and $_.PSObject.Properties['type'] -and $_.type -eq $EnvelopeType })
                foreach ($envelope in $envelopes) {
                    if (-not $envelope.PSObject.Properties['properties'] -or -not $envelope.properties) { continue }
                    foreach ($item in @($envelope.properties)) {
                        # `id` is read case-insensitively (PowerShell property lookup), matching
                        # the raw ARM REST list-response shape's `id` field -- see the
                        # policyInitiatives block above for the same idiom.
                        if ($item -and $item.PSObject.Properties['Id'] -and -not [string]::IsNullOrWhiteSpace([string]$item.Id)) { $item }
                    }
                }
            }
        )
    }
    # A definition can be visible from more than one subscription's ARM REST sweep in a
    # multi-subscription tenant (built-ins repeat per subscription); collapse to one row per
    # distinct id, matching the policyInitiatives dedup immediately above.
    $policyDefinitions = @(Get-ScoutTenantWideDefinitionRow -EnvelopeType 'AZSC/Management/PolicyDefinition' | Sort-Object Id -Unique)
    $policySetDefinitions = @(Get-ScoutTenantWideDefinitionRow -EnvelopeType 'AZSC/Management/PolicySetDefinition' | Sort-Object Id -Unique)

    # ---- Key Vault children: secrets and keys (AB#6821, Epic AB#6454) -------------------------
    # These rows come from Get-ScoutArmChildResource's ARM REST sweep (see the ArmChildDataset
    # note above) rather than Resource Graph -- $rawInventory.Resources carries them as
    # AZSC/ARMChild/KeyVaultSecrets and AZSC/ARMChild/KeyVaultKeys rows, one per secret/key
    # version-less object, with ConvertTo-ArmChildRow's synthetic PARENTNAME/PARENTID/
    # subscriptionId/RESOURCEGROUP columns identifying which vault each one belongs to. Field
    # names below (contentType, attributes.enabled/exp/nbf) are the documented Key Vault
    # GetSecrets/GetKeys list-response shape -- the exact fields
    # manifests/collectors/Security/KeyVaultSecrets.psd1 / KeyVaultKeys.psd1 already read to
    # render the Excel worksheet (Content Type, Enabled, Expires), so a rule here and that
    # worksheet agree on what a given secret/key looks like.
    function ConvertTo-ScoutKeyVaultChildRow {
        param([Parameter(Mandatory)] $Row)
        $attrs = if ($Row.PSObject.Properties['attributes']) { $Row.attributes } else { $null }
        [pscustomobject]@{
            id             = if ($Row.PSObject.Properties['id']) { [string]$Row.id } else { $null }
            keyVaultName   = if ($Row.PSObject.Properties['PARENTNAME']) { [string]$Row.PARENTNAME } else { $null }
            keyVaultId     = if ($Row.PSObject.Properties['PARENTID']) { [string]$Row.PARENTID } else { $null }
            subscriptionId = if ($Row.PSObject.Properties['subscriptionId']) { [string]$Row.subscriptionId } else { $null }
            resourceGroup  = if ($Row.PSObject.Properties['RESOURCEGROUP']) { [string]$Row.RESOURCEGROUP } else { $null }
            # Certificates are secrets whose contentType is x-pkcs12 (PFX) or x-pem-file (PEM) --
            # Key Vault has no separate "certificate" list API result shape at this level; see
            # src/collect/Get-ScoutArmChildResource.ps1 (~line 453) and
            # manifests/collectors/Security/KeyVaultSecrets.psd1's $Kind derivation.
            contentType    = if ($Row.PSObject.Properties['contentType']) { [string]$Row.contentType } else { $null }
            enabled        = ConvertTo-ScoutBool ($(if ($attrs -and $attrs.PSObject.Properties['enabled']) { $attrs.enabled } else { $null }))
            expires        = if ($attrs -and $attrs.PSObject.Properties['exp']) { $attrs.exp } else { $null }
        }
    }
    $keyVaultSecrets = @()
    $keyVaultKeys = @()
    if ($rawInventory -and $rawInventory.PSObject.Properties['Resources'] -and $rawInventory.Resources) {
        $keyVaultSecrets = @(
            $rawInventory.Resources |
                Where-Object { $_ -and $_.PSObject.Properties['type'] -and $_.type -eq 'AZSC/ARMChild/KeyVaultSecrets' } |
                ForEach-Object { ConvertTo-ScoutKeyVaultChildRow -Row $_ }
        )
        $keyVaultKeys = @(
            $rawInventory.Resources |
                Where-Object { $_ -and $_.PSObject.Properties['type'] -and $_.type -eq 'AZSC/ARMChild/KeyVaultKeys' } |
                ForEach-Object { ConvertTo-ScoutKeyVaultChildRow -Row $_ }
        )
    }

    $policyComplianceStates = @()
    if ($IncludePolicyCompliance) {
        try {
            if (-not (Get-Command Get-ScoutSubscriptionSecurityPolicySweep -ErrorAction SilentlyContinue)) {
                . (Join-Path $PSScriptRoot 'Get-ScoutSubscriptionSecurityPolicySweep.ps1')
            }
            $sweepSubscriptions = @($r.subscriptions | Where-Object { $_ -and $_.PSObject.Properties['id'] })
            $sweepResults = @(Get-ScoutSubscriptionSecurityPolicySweep -Subscriptions $sweepSubscriptions)
            $policyComplianceStates = @(
                foreach ($sweep in $sweepResults) {
                    if (-not $sweep -or -not $sweep.PSObject.Properties['properties'] -or -not $sweep.properties) { continue }
                    foreach ($state in @($sweep.properties.PolicyComplianceStates)) {
                        if (-not $state) { continue }
                        $state | Add-Member -NotePropertyName SubscriptionId -NotePropertyValue $sweep.subscriptionId -Force
                        $state | Add-Member -NotePropertyName SubscriptionName -NotePropertyValue $sweep.subscriptionName -Force -PassThru
                    }
                }
            )
        }
        catch {
            Write-Warning "Invoke-Collect: the policy compliance sweep failed; the compliance assessment will report Not assessed rather than a fabricated score: $($_.Exception.Message)"
            $policyComplianceStates = @()
        }
    }

    # ---- Defender for Cloud plan sweep (AB#6903) ----
    # security.defenderPlans shipped as a hard-coded @() placeholder while caf.security /
    # waf.security rules query $.security.defenderPlans[?(@.properties.pricingTier ==
    # 'Standard')] -- those rules could never pass on any tenant. Unconditional (no gate:
    # Defender plan assignment is core security posture); one ARM GET per subscription, and
    # an unregistered Microsoft.Security provider stays quiet (AB#6900).
    $defenderPlans = @()
    try {
        if (-not (Get-Command Get-ScoutDefenderPlanSweep -ErrorAction SilentlyContinue)) {
            . (Join-Path $PSScriptRoot 'Get-ScoutDefenderPlanSweep.ps1')
        }
        $defenderPlans = @(Get-ScoutDefenderPlanSweep -Subscriptions @($r.subscriptions))
    }
    catch {
        Write-Warning "Invoke-Collect: the Defender plan sweep failed; security.defenderPlans will be empty for this run: $($_.Exception.Message)"
        $defenderPlans = @()
    }

    # ---- every declared dataset exists, even when nothing populated it ----
    #
    # `$r` is a hashtable, and under Set-StrictMode -Version Latest reading a key that was never
    # assigned THROWS -- it does not return $null. Two collection paths populate it: the typed
    # query pack sets a key per query it runs, and the inverted single-pass path sets only the
    # keys ConvertFrom-ScoutInventory shapes. Any dataset present in one path and not the other
    # therefore blows up the canonical-contract literal below, and because that literal is a
    # single expression the exception names whichever key it happened to hit first -- which is
    # why this presented as `privateClouds` when `avdHostPools` was equally unset.
    #
    # Seeding every declared query key with an empty array makes "collected nothing" and
    # "this path does not populate this dataset" both render as an empty collection rather than
    # a crash. It also means a new dataset added to `$q` alone can never take the shape block
    # down again, which is the failure this replaces.
    foreach ($declaredKey in $q.Keys) {
        if (-not $r.ContainsKey($declaredKey)) { $r[$declaredKey] = @() }
    }

    # ---- shape into the canonical contract ----
    $collect = [pscustomobject]@{
        subscriptions = $r.subscriptions
        tags          = $tags
        networking    = [pscustomobject]@{
            virtualNetworks          = $r.virtualNetworks
            subnets                  = $r.subnets
            azureFirewalls           = $r.azureFirewalls
            firewallPolicyRuleGroups = $firewallPolicyRuleGroups
            vpnGateways              = $r.vpnGateways
            privateEndpoints         = $r.privateEndpoints
            privateDnsZones          = $r.privateDnsZones
            nsgPublicInbound         = $r.nsgPublicInbound
            # AB#7110 -- 13 ordinary ARG-indexed Networking types.
            applicationGateways      = $r.applicationGateways
            bastionHosts             = $r.bastionHosts
            networkConnections       = $r.networkConnections
            expressRouteCircuits     = $r.expressRouteCircuits
            frontDoors               = $r.frontDoors
            loadBalancers            = $r.loadBalancers
            natGateways              = $r.natGateways
            networkInterfaces        = $r.networkInterfaces
            networkWatchers          = $r.networkWatchers
            publicDnsZones           = $r.publicDnsZones
            routeTables              = $r.routeTables
            trafficManagerProfiles   = $r.trafficManagerProfiles
            virtualWans              = $r.virtualWans
        }
        # avdHostPools/avdSessionHosts/avdScalingPlans (AB#6819) and privateClouds (AB#6820) sit
        # under `compute`, not `domains`, alongside virtualMachines -- the existing pattern for
        # Compute-category data.
        compute       = [pscustomobject]@{
            virtualMachines = $r.virtualMachines
            avdHostPools    = $r.avdHostPools
            avdSessionHosts = $r.avdSessionHosts
            avdScalingPlans = $r.avdScalingPlans
            privateClouds   = $r.privateClouds
        }
        management    = [pscustomobject]@{
            # AB#6895: was hardcoded @(), so no run in the product's history ever reported a
            # Recovery Services vault -- while backupProtectedItems returned rows, leaving a child
            # with no parent (the AB#6845 class). The vault itself lives in the ordinary
            # `resources` table, not in recoveryservicesresources, so the inverted path shapes it
            # from rows the raw pass already holds and it costs no extra round-trip.
            #
            # Read defensively: the typed-query path has no such key, and a dot-access would throw
            # PropertyNotFound under StrictMode.
            # `$r` is a HASHTABLE. `$r.PSObject.Properties['x']` is the dictionary adapter's member
            # list -- Keys, Values, Count -- and never the keys themselves, so that guard was
            # unconditionally false and this read returned `@()` on every run regardless of what
            # had been collected (AB#6896). `ContainsKey` is the only correct test here.
            recoveryVaults = @(if ($r.ContainsKey('recoveryVaults')) { $r['recoveryVaults'] } else { @() })
            deployments = $r.deployments
            logAnalyticsWorkspaces = $r.logAnalyticsWorkspaces
            # The right-hand side of XR-BKP-01/02 (AB#6835). Filed under management because that
            # is where the vault lives, not under compute where the protected VM does.
            backupProtectedItems = $r.backupProtectedItems
            # AB#7065: was a manifest that only ever rendered an Excel worksheet -- Azure Update
            # Manager schedule/patch-configuration data never reached the assessment payload.
            maintenanceConfigurations = $r.maintenanceConfigurations
            # AB#7110 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Management plumbing.
            advisorScores = $r.advisorScores
            automationAccounts = $r.automationAccounts
            recoveryVaultBackupPolicies = $r.recoveryVaultBackupPolicies
            lighthouseDelegations = $r.lighthouseDelegations
        }
        # AB#7107/AB#7108 -- Update Manager's own assessment/installation history, a new
        # top-level section for the same reason `monitor` is one: the data spans both Azure VMs
        # and Arc-enabled servers, not one existing category's resource type. See the canonical
        # contract comment at the top of this file.
        updateManager = [pscustomobject]@{
            patchAssessments   = $r.patchAssessments
            patchInstallations = $r.patchInstallations
        }
        # AB#6903: was hardcoded @() -- see the sweep above.
        # AB#7063: wafPolicies/ddosProtectionPlans/applicationSecurityGroups (AB#7063, Story
        # AB#7059, Feature AB#7069, Epic AB#7099) -- ordinary ARG-indexed types, see the query
        # pack above for what was deliberately deferred (DefenderAlerts/Assessments/SecureScore/
        # Pricing) and why.
        security      = [pscustomobject]@{
            defenderPlans = $defenderPlans
            wafPolicies = $r.wafPolicies
            ddosProtectionPlans = $r.ddosProtectionPlans
            applicationSecurityGroups = $r.applicationSecurityGroups
        }
        governance    = [pscustomobject]@{
            managementGroups = @()
            policyAssignments = $rawGovernance.policyAssignments
            # AB#7066: definitions BEHIND an assignment/initiative were never surfaced, only the
            # assignment itself -- see the extraction block above for the source and shape.
            policyDefinitions = $policyDefinitions
            policySetDefinitions = $policySetDefinitions
            roleAssignments = $rawGovernance.roleAssignments
            budgets = $rawGovernance.budgets
            resourceLocks = $rawGovernance.resourceLocks
            pimEligibility = @(); classicAdministrators = @()
        }
        costCleanup   = [pscustomobject]@{ orphanedDisks = $r.orphanedDisks; orphanedPips = $r.orphanedPips }
        opsPosture    = [pscustomobject]@{ diagnosticCoverage = $r.diagnosticCoverage }
        # AB#7064 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Monitor-native resources sit
        # under their own top-level key rather than being folded into `management`/`opsPosture`,
        # which already carry unrelated meanings (deployments/backup vs derived diagnostic-coverage
        # percentages).
        monitor       = [pscustomobject]@{
            dataCollectionRules     = $r.dataCollectionRules
            dataCollectionEndpoints = $r.dataCollectionEndpoints
            actionGroups            = $r.actionGroups
            autoscaleSettings       = $r.autoscaleSettings
            metricAlertRules        = $r.metricAlertRules
            scheduledQueryRules     = $r.scheduledQueryRules
            activityLogAlertRules   = $r.activityLogAlertRules
            smartDetectorAlertRules = $r.smartDetectorAlertRules
            appInsights                  = $r.appInsights
            workbooks                    = $r.workbooks
            privateLinkScopes            = $r.privateLinkScopes
            workspaceSolutions           = $r.workspaceSolutions
            appInsightsAvailabilityTests = $r.appInsightsAvailabilityTests
        }
        # Per-domain resource data (scalar compliance fields) for the per-category
        # assessments in Epic AB#5056.
        domains       = [pscustomobject]@{
            storage      = [pscustomobject]@{
                storageAccounts = $r.storageAccounts
                snapshots = $r.snapshots; managedDisks = $r.managedDisks
                diskEncryptionSets = $r.diskEncryptionSets
                # AB#7110 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Storage plumbing.
                edgeHardwareCenterOrders = $r.edgeHardwareCenterOrders
                elasticSanVolumeGroups = $r.elasticSanVolumeGroups
                netAppVolumes = $r.netAppVolumes
                partnerStorageResources = $r.partnerStorageResources
                storageSyncServices = $r.storageSyncServices
            }
            databases    = [pscustomobject]@{
                sqlDatabases = $r.sqlDatabases; sqlServers = $r.sqlServers
                sqlDefenderPricing = $r.sqlDefenderPricing
                # AB#7110 -- Databases plumbing.
                cosmosDbAccounts = $r.cosmosDbAccounts
                mariaDbServers = $r.mariaDbServers
                mySqlServers = $r.mySqlServers
                mySqlFlexibleServers = $r.mySqlFlexibleServers
                postgreSqlFlexibleServers = $r.postgreSqlFlexibleServers
                redisCaches = $r.redisCaches
                sqlManagedInstances = $r.sqlManagedInstances
                sqlManagedInstanceDatabases = $r.sqlManagedInstanceDatabases
                sqlElasticPools = $r.sqlElasticPools
                sqlVirtualMachines = $r.sqlVirtualMachines
            }
            web          = [pscustomobject]@{
                webApps = $r.webApps
                # AB#7110 -- Web plumbing.
                appServiceCertificates = $r.appServiceCertificates
                appServiceDomains = $r.appServiceDomains
                appServiceEnvironments = $r.appServiceEnvironments
                appServicePlans = $r.appServicePlans
                communicationServices = $r.communicationServices
                webAppDeploymentSlots = $r.webAppDeploymentSlots
                fluidRelayServers = $r.fluidRelayServers
                notificationHubNamespaces = $r.notificationHubNamespaces
                signalRServices = $r.signalRServices
                springApps = $r.springApps
                staticWebApps = $r.staticWebApps
                webPubSubServices = $r.webPubSubServices
            }
            # openShiftClusters/containerApps/containerAppEnvironments/containerGroups AB#7110.
            containers   = [pscustomobject]@{
                aksClusters = $r.aksClusters; containerRegistries = $r.containerRegistries
                openShiftClusters = $r.openShiftClusters; containerApps = $r.containerApps
                containerAppEnvironments = $r.containerAppEnvironments
                containerGroups = $r.containerGroups
            }
            # keyVaultSecrets/keyVaultKeys (AB#6821) carry the expiry and rotation metadata CASA
            # scores; they come from the ARM-child sweep, not from the ARG keyVaults row.
            security     = [pscustomobject]@{
                keyVaults = $r.keyVaults
                keyVaultSecrets = $keyVaultSecrets; keyVaultKeys = $keyVaultKeys
                # AB#7110 -- Security plumbing.
                appComplianceReports = $r.appComplianceReports
                applicationSecurityGroups = $r.applicationSecurityGroups
                artifactSigningAccounts = $r.artifactSigningAccounts
                cloudHsmClusters = $r.cloudHsmClusters
                confidentialLedgers = $r.confidentialLedgers
                ddosProtectionPlans = $r.ddosProtectionPlans
                entraDomainServices = $r.entraDomainServices
                managedHsms = $r.managedHsms
                sentinelWorkspaces = $r.sentinelWorkspaces
                wafPolicies = $r.wafPolicies
            }
            # AB#7110 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Identity had no existing
            # canonical domains section; ManagedIds is the only ARG-indexed, non-Graph collector
            # in the Identity(16) coverage gap.
            identity     = [pscustomobject]@{
                managedIdentities = $r.managedIdentities
            }
            # mlWorkspaces/searchServices (AB#6818) are the custom-build and grounding-pipeline
            # halves of the AI workload assessment that cognitiveAccounts alone doesn't cover.
            ai           = [pscustomobject]@{
                cognitiveAccounts = $r.cognitiveAccounts
                mlWorkspaces      = $r.mlWorkspaces
                searchServices    = $r.searchServices
            }
            hybrid       = [pscustomobject]@{
                arcServers = $r.arcServers; arcExtensions = $r.arcExtensions
                azureLocalClusters = $r.azureLocalClusters
                # logicalNetworks (AB#6819) — WAF-AVD-SE-04 network-isolation evidence.
                # AB#6803 (Feature AB#6747, Epic AB#6454) — Azure Local WAF review support.
                # logicalNetworks is ARG-indexed and always populated on a normal collect.
                # arcSites / azureLocalVirtualMachineInstances are the two collectors AB#6801/
                # AB#6802 re-sourced off ARM REST (Resource Graph does not index either type) --
                # they are ONLY populated when the caller opts into -IncludeAzureLocalArm, and are
                # empty arrays otherwise. `manifests/assessments.psd1`'s 'WAF: Azure Local' entry
                # gates its own menu visibility on these two paths being non-empty for exactly
                # that reason: an empty array here can mean "collected, tenant has none" OR
                # "never asked Azure", and only the caller who set the switch knows which.
                logicalNetworks = $r.logicalNetworks
                arcSites = $r.arcSites
                azureLocalVirtualMachineInstances = $r.azureLocalVirtualMachineInstances
                # AB#7061 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- Azure Local child
                # resources. All nine are ordinary ARG-indexed types (see the $q declaration
                # above), always populated on a normal collect, same as arcServers/
                # azureLocalClusters/logicalNetworks -- no -IncludeAzureLocalArm gate needed.
                arcDataControllers = $r.arcDataControllers
                arcGateways = $r.arcGateways
                arcKubernetes = $r.arcKubernetes
                arcResourceBridge = $r.arcResourceBridge
                arcSqlManagedInstances = $r.arcSqlManagedInstances
                arcSqlServers = $r.arcSqlServers
                galleryImages = $r.galleryImages
                marketplaceGalleryImages = $r.marketplaceGalleryImages
                storageContainers = $r.storageContainers
            }
            integration  = [pscustomobject]@{
                eventHubNamespaces = $r.eventHubNamespaces; apiManagement = $r.apiManagement
                serviceBusNamespaces = $r.serviceBusNamespaces
            }
            iot          = [pscustomobject]@{
                iotHubs = $r.iotHubs; dpsInstances = $r.dpsInstances
                digitalTwinsInstances = $r.digitalTwinsInstances
            }
            migration    = [pscustomobject]@{
                migrateProjects = $r.migrateProjects
                migrationServices = $r.migrationServices
                discoverySites = $r.discoverySites
            }
            # databricksWorkspaces/dataExplorerClusters/streamAnalyticsJobs AB#7110.
            analytics    = [pscustomobject]@{
                synapseWorkspaces = $r.synapseWorkspaces; purviewAccounts = $r.purviewAccounts
                databricksWorkspaces = $r.databricksWorkspaces
                dataExplorerClusters = $r.dataExplorerClusters
                streamAnalyticsJobs = $r.streamAnalyticsJobs
            }
            # AB#6792/#6793/#6794 -- policyInitiatives is always populated (free, see above);
            # policyComplianceStates is only non-empty when -IncludePolicyCompliance was set.
            management   = [pscustomobject]@{
                policyComplianceStates = $policyComplianceStates
                policyInitiatives      = $policyInitiatives
            }
        }
        advisor       = @()
        # ---- AB#6826/AB#6827 (Feature AB#6749) -- stubs the ARM-sourced half of each domain.
        # `available`/`costRows`/`anomalies`/`blockedSubscriptions` (finops) and
        # `available`/`attempted`/`projects`/`pipelines`/`repositories`/`serviceConnections`/
        # `agentPools` (devops) are the billing-/DevOps-access-gated halves, filled by
        # Import-ScoutCostInventory / Import-ScoutDevOpsCapability when those ingestors run --
        # a caller that never invokes them (a rule set neither -Assessment entry needs) still
        # gets a well-formed, empty object rather than a missing key that throws under
        # StrictMode.
        finops        = [pscustomobject]@{
            available = $false; costRows = @(); anomalies = @(); blockedSubscriptions = @()
            reservations = $r.reservations; reservationRecommendations = @()
        }
        devops        = [pscustomobject]@{
            available = $false; attempted = $false
            projects = @(); pipelines = @(); repositories = @(); serviceConnections = @(); agentPools = @()
            managedPools = $r.managedDevOpsPools; devCenters = $r.devCenters
            loadTesting = $r.loadTesting; chaosExperiments = $r.chaosExperiments
            playwrightTesting = $r.playwrightTesting
            # AB#7110 (Story AB#7059, Feature AB#7069, Epic AB#7099) -- DevOps plumbing.
            apiConnections = $r.apiConnections
            appConfigurationStores = $r.appConfigurationStores
            deploymentEnvironmentTypes = $r.deploymentEnvironmentTypes
            devBoxPools = $r.devBoxPools
            devCenterNetworkConnections = $r.devCenterNetworkConnections
            devTestLabs = $r.devTestLabs
            labServicesLabs = $r.labServicesLabs
        }
        _meta         = [pscustomobject]@{
            generatedOn = (Get-Date).ToString('o'); scope = $Scope
            categories = $Categories; managementGroupId = $ManagementGroupId
        }
    }
    return $collect
}

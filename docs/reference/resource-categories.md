---
description: Every Azure resource provider namespace and the AzureScout category its discovered resources are filed under.
---

# Resource Categories

Every resource AzureScout discovers belongs to one of the 18 categories in
[Category Structure](category-structure.md), whether or not a collector reads it. Discovery records the
category on each resource (`Category`, and `CategorySource` for where it came from) in
`ReportCache/Discovery.json`, and the React report lists resources without a collector under their
category as **Other discovered resources**.

::: tip This page is generated
Regenerate it with `scripts/Build-ResourceCategoryCatalog.ps1` from `manifests/resource-categories.psd1`.
A test fails if this page and the map differ, or if a namespace in Azure's provider catalogue
(`manifests/azure-provider-types.json`) has no category.
:::

## How a resource's category is decided

1. **Collector** — if a collector reads the resource type, the category is that collector's folder under
   `manifests/collectors/`.
2. **Type** — otherwise the longest entry in the type table below that is the type itself or one of its
   parents (for example `microsoft.compute/virtualmachines/patchassessmentresults` covers its
   `softwarepatches` children).
3. **Namespace** — otherwise the category of the type's resource provider namespace.
4. **Fallback** — a namespace Azure adds after this map was updated is filed under General and marked
   `CategorySource = Fallback`, and the discovery page counts it as uncategorized, so it is visible
   rather than silently misfiled.

## Summary

| Category | Namespaces | Type entries |
|---|---:|---:|
| AI (AI + Machine Learning) | 29 | 0 |
| Analytics | 26 | 1 |
| Compute | 29 | 0 |
| Containers | 10 | 1 |
| Databases | 14 | 0 |
| DevOps | 28 | 0 |
| General | 54 | 0 |
| Hybrid (Hybrid + multicloud) | 23 | 0 |
| Identity | 14 | 10 |
| Integration | 18 | 3 |
| IoT (Internet of Things) | 18 | 0 |
| Management (Management and governance) | 41 | 6 |
| Migration | 14 | 1 |
| Monitor | 19 | 0 |
| Networking | 19 | 0 |
| Security | 23 | 7 |
| Storage | 27 | 4 |
| Web (Web & Mobile) | 13 | 0 |
| **Total** | **419** | **33** |

## Type entries

For namespaces whose resources span categories. Each entry also covers its child types.

| Resource type | Category |
|---|---|
| `microsoft.authorization/classicadministrators` | Identity |
| `microsoft.authorization/denyassignments` | Identity |
| `microsoft.authorization/roleassignments` | Identity |
| `microsoft.authorization/roleassignmentscheduleinstances` | Identity |
| `microsoft.authorization/roleassignmentschedules` | Identity |
| `microsoft.authorization/roledefinitions` | Identity |
| `microsoft.authorization/roleeligibilityscheduleinstances` | Identity |
| `microsoft.authorization/roleeligibilityschedules` | Identity |
| `microsoft.authorization/rolemanagementpolicies` | Identity |
| `microsoft.authorization/rolemanagementpolicyassignments` | Identity |
| `microsoft.cdn/cdnwebapplicationfirewallpolicies` | Security |
| `microsoft.compute/diskaccesses` | Storage |
| `microsoft.compute/diskencryptionsets` | Storage |
| `microsoft.compute/disks` | Storage |
| `microsoft.compute/snapshots` | Storage |
| `microsoft.compute/virtualmachines/patchassessmentresults` | Management |
| `microsoft.compute/virtualmachines/patchinstallationresults` | Management |
| `microsoft.eventhub/namespaces` | Analytics |
| `microsoft.hybridcompute/machines/patchassessmentresults` | Management |
| `microsoft.hybridcompute/machines/patchinstallationresults` | Management |
| `microsoft.migrate/assessmentprojects` | Migration |
| `microsoft.network/applicationgatewaywebapplicationfirewallpolicies` | Security |
| `microsoft.network/ddosprotectionplans` | Security |
| `microsoft.network/firewallpolicies` | Security |
| `microsoft.network/frontdoorwebapplicationfirewallpolicies` | Security |
| `microsoft.network/networksecurityperimeters` | Security |
| `microsoft.operationalinsights/workspaces/providers/microsoft.securityinsights` | Security |
| `microsoft.resources/resourcegroups` | Management |
| `microsoft.resources/subscriptions` | Management |
| `microsoft.web/connections` | Integration |
| `microsoft.web/customapis` | Integration |
| `microsoft.web/kubeenvironments` | Containers |
| `microsoft.web/sites/workflows` | Integration |

## Namespaces by category

### AI — AI + Machine Learning

`anyscale.platform`, `arizeai.observabilityeval`, `kore.agentplatform`, `microsoft.autonomousdevelopmentplatform`, `microsoft.autonomoussystems`, `microsoft.bing`, `microsoft.botservice`, `microsoft.cognition`, `microsoft.cognitivesearch`, `microsoft.cognitiveservices`, `microsoft.copilot`, `microsoft.devai`, `microsoft.discovery`, `microsoft.foundrylocal`, `microsoft.genome`, `microsoft.healthbot`, `microsoft.inferenceservice`, `microsoft.machinelearning`, `microsoft.machinelearningservices`, `microsoft.modsimworkbench`, `microsoft.orbital`, `microsoft.recommendationsservice`, `microsoft.search`, `microsoft.singularity`, `microsoft.syntex`, `microsoft.videoindexer`, `microsoft.weightsandbiases`, `napster.companionapi`, `pinecone.vectordb`

### Analytics

`astronomer.astro`, `informatica.datamanagement`, `microsoft.agfoodplatform`, `microsoft.analysisservices`, `microsoft.cleanroom`, `microsoft.confluent`, `microsoft.d365customerinsights`, `microsoft.databricks`, `microsoft.datacollaboration`, `microsoft.datafactory`, `microsoft.datalakeanalytics`, `microsoft.dataplatform`, `microsoft.datashare`, `microsoft.energydataplatform`, `microsoft.eventhub`, `microsoft.fabric`, `microsoft.hdinsight`, `microsoft.kusto`, `microsoft.kx`, `microsoft.networkanalytics`, `microsoft.openenergyplatform`, `microsoft.powerbi`, `microsoft.powerbidedicated`, `microsoft.purview`, `microsoft.streamanalytics`, `microsoft.synapse`

### Compute

`citrix.services`, `microsoft.avs`, `microsoft.azurefleet`, `microsoft.azureimagetestingforlinux`, `microsoft.azurelargeinstance`, `microsoft.baremetal`, `microsoft.baremetalinfrastructure`, `microsoft.batch`, `microsoft.classiccompute`, `microsoft.compute`, `microsoft.computebulkactions`, `microsoft.computelimit`, `microsoft.computeschedule`, `microsoft.desktopvirtualization`, `microsoft.hanaonazure`, `microsoft.hpcworkbench`, `microsoft.ibmpower`, `microsoft.nutanix`, `microsoft.quantum`, `microsoft.remoteapp`, `microsoft.serialconsole`, `microsoft.skytap`, `microsoft.standbypool`, `microsoft.supercomputerinfrastructure`, `microsoft.swiftlet`, `microsoft.virtualmachineimages`, `microsoft.vmware`, `microsoft.windows365`, `microsoft.workloads`

### Containers

`microsoft.app`, `microsoft.containerinstance`, `microsoft.containerregistry`, `microsoft.containerservice`, `microsoft.kubernetesruntime`, `microsoft.managedstorageclass`, `microsoft.redhatopenshift`, `microsoft.secretsynccontroller`, `microsoft.servicefabric`, `microsoft.servicefabricmesh`

### Databases

`microsoft.azuredata`, `microsoft.cache`, `microsoft.databasefleetmanager`, `microsoft.dbformariadb`, `microsoft.dbformysql`, `microsoft.dbforpostgresql`, `microsoft.documentdb`, `microsoft.horizondb`, `microsoft.infinitydb`, `microsoft.oriondb`, `microsoft.sql`, `microsoft.sqlvirtualmachine`, `mongodb.atlas`, `oracle.database`

### DevOps

`devops`, `github.enterprise`, `lambdatest.hyperexecute`, `microsoft.anybuild`, `microsoft.appconfiguration`, `microsoft.azuredevopsplatform`, `microsoft.azureplaywrightservice`, `microsoft.azureterraform`, `microsoft.chaos`, `microsoft.cloudtest`, `microsoft.codespaces`, `microsoft.devcenter`, `microsoft.developmentwindows365`, `microsoft.devhub`, `microsoft.devops`, `microsoft.devopsinfrastructure`, `microsoft.devtestlab`, `microsoft.devtunnels`, `microsoft.experimentation`, `microsoft.labservices`, `microsoft.loadtestservice`, `microsoft.onlineexperimentation`, `microsoft.platformvalidation`, `microsoft.testbase`, `microsoft.toolchainorchestrator`, `microsoft.visualstudio`, `microsoft.vsonline`, `splitio.experimentation`

### General

`liftrbasic.samplerp`, `microsoft.addons`, `microsoft.alicespringsdataplane`, `microsoft.asterra`, `microsoft.azurecontextcache`, `microsoft.azurescan`, `microsoft.bami`, `microsoft.billingtrust`, `microsoft.blockchaintokens`, `microsoft.bluefin`, `microsoft.capacity`, `microsoft.cloudes`, `microsoft.cloudshell`, `microsoft.commerce`, `microsoft.community`, `microsoft.compositesolutions`, `microsoft.consumption`, `microsoft.contoso`, `microsoft.cosmic`, `microsoft.dataaccelerator`, `microsoft.decisionworkflows`, `microsoft.digitalassets`, `microsoft.edgemarketplace`, `microsoft.enterprisesupport`, `microsoft.falcon`, `microsoft.graduationtest`, `microsoft.hardware`, `microsoft.help`, `microsoft.liftrpilot`, `microsoft.marketplace`, `microsoft.marketplaceordering`, `microsoft.metaverse`, `microsoft.openlogisticsplatform`, `microsoft.partnerenrollment`, `microsoft.partnermanagedconsumerrecurrence`, `microsoft.portal`, `microsoft.portalsdk`, `microsoft.portalservices`, `microsoft.premonition`, `microsoft.professionalservice`, `microsoft.programenrollment`, `microsoft.proposal`, `microsoft.providerhub`, `microsoft.quota`, `microsoft.saas`, `microsoft.saashub`, `microsoft.serviceshub`, `microsoft.softwareplan`, `microsoft.spoolservice`, `microsoft.support`, `microsoft.symphony`, `microsoft.throttling`, `microsoft.usagebilling`, `microsoft.validate`

### Hybrid — Hybrid + multicloud

`microsoft.arccontainerstorage`, `microsoft.arcnetworking`, `microsoft.awsconnector`, `microsoft.azurearcdata`, `microsoft.azurestack`, `microsoft.azurestackhci`, `microsoft.connectedcredentials`, `microsoft.connectedopenstack`, `microsoft.connectedvmwarevsphere`, `microsoft.deviceonboarding`, `microsoft.edge`, `microsoft.edgezones`, `microsoft.extendedlocation`, `microsoft.gcpconnector`, `microsoft.hybridcloud`, `microsoft.hybridcompute`, `microsoft.hybridconnectivity`, `microsoft.hybridcontainerservice`, `microsoft.kubernetes`, `microsoft.kubernetesconfiguration`, `microsoft.resourceconnector`, `microsoft.scvmm`, `microsoft.windowsesu`

### Identity

`entra`, `microsoft.aad`, `microsoft.aadcustomsecurityattributesdiagnosticsettings`, `microsoft.aadiam`, `microsoft.adhybridhealthservice`, `microsoft.azureactivedirectory`, `microsoft.directorystore`, `microsoft.entitlementmanagement`, `microsoft.entraidgovernance`, `microsoft.entraidgovernanceaccelerator`, `microsoft.graph`, `microsoft.graphservices`, `microsoft.managedidentity`, `microsoft.verifiedid`

### Integration

`microsoft.apicenter`, `microsoft.apimanagement`, `microsoft.applink`, `microsoft.biztalkservices`, `microsoft.durabletask`, `microsoft.eventgrid`, `microsoft.healthcareapis`, `microsoft.healthcareinterop`, `microsoft.healthdataaiservices`, `microsoft.healthplatform`, `microsoft.integrationspaces`, `microsoft.logic`, `microsoft.messagingcatalog`, `microsoft.messagingconnectors`, `microsoft.powerplatform`, `microsoft.relay`, `microsoft.servicebus`, `microsoft.servicelinker`

### IoT — Internet of Things

`microsoft.azurepercept`, `microsoft.azuresphere`, `microsoft.clouddeviceplatform`, `microsoft.connectedvehicle`, `microsoft.deviceregistry`, `microsoft.devices`, `microsoft.deviceupdate`, `microsoft.digitaltwins`, `microsoft.iotcentral`, `microsoft.iotfirmwaredefense`, `microsoft.iotoperations`, `microsoft.iotoperationsdataprocessor`, `microsoft.iotoperationsmq`, `microsoft.iotoperationsorchestrator`, `microsoft.iotsecurity`, `microsoft.maps`, `microsoft.timeseriesinsights`, `microsoft.windowsiot`

### Management — Management and governance

`automationprojects`, `microsoft.advisor`, `microsoft.approvals`, `microsoft.authorization`, `microsoft.automanage`, `microsoft.automation`, `microsoft.azurebusinesscontinuity`, `microsoft.azureresiliencemanagement`, `microsoft.backupsolutions`, `microsoft.billing`, `microsoft.billingbenefits`, `microsoft.blueprint`, `microsoft.carbon`, `microsoft.changesafety`, `microsoft.costmanagement`, `microsoft.costmanagementexports`, `microsoft.customproviders`, `microsoft.dataprotection`, `microsoft.datareplication`, `microsoft.easm`, `microsoft.features`, `microsoft.guestconfiguration`, `microsoft.maintenance`, `microsoft.managedops`, `microsoft.managedservices`, `microsoft.management`, `microsoft.mission`, `microsoft.policyinsights`, `microsoft.recoveryservices`, `microsoft.relationships`, `microsoft.resiliency`, `microsoft.resourcebuilder`, `microsoft.resourcegraph`, `microsoft.resourceintelligence`, `microsoft.resources`, `microsoft.solutions`, `microsoft.sovereign`, `microsoft.subscription`, `microsoft.sustainabilityservices`, `microsoft.updatemanager`, `microsoft.workloadbuilder`

### Migration

`microsoft.appassessment`, `microsoft.applicationmigration`, `microsoft.azuredatatransfer`, `microsoft.databox`, `microsoft.databoxedge`, `microsoft.datamigration`, `microsoft.dependencymap`, `microsoft.importexport`, `microsoft.migrate`, `microsoft.mysqldiscovery`, `microsoft.offazure`, `microsoft.offazurespringboot`, `microsoft.resourcemover`, `wandisco.fusion`

### Monitor

`dynatrace.observability`, `microsoft.alertsmanagement`, `microsoft.cloudhealth`, `microsoft.dashboard`, `microsoft.databasewatcher`, `microsoft.datadog`, `microsoft.elastic`, `microsoft.footprintmonitoring`, `microsoft.healthmodel`, `microsoft.impact`, `microsoft.insights`, `microsoft.monitor`, `microsoft.operationalinsights`, `microsoft.operationsmanagement`, `microsoft.powerplatformmonitoringhub`, `microsoft.resourcehealth`, `microsoft.resourcenotifications`, `microsoft.scom`, `newrelic.observability`

### Networking

`github.network`, `microsoft.cdn`, `microsoft.classicnetwork`, `microsoft.connectedcache`, `microsoft.delegatednetwork`, `microsoft.dns`, `microsoft.hybridnetwork`, `microsoft.managednetworkfabric`, `microsoft.mobilepacketcore`, `microsoft.network`, `microsoft.networkcloud`, `microsoft.networkfunction`, `microsoft.networkresourceprovider`, `microsoft.nexusidentity`, `microsoft.operatorvoicemail`, `microsoft.peering`, `microsoft.programmableconnectivity`, `microsoft.servicenetworking`, `nginx.nginxplus`

### Security

`microsoft.appcomplianceautomation`, `microsoft.appsecurity`, `microsoft.attestation`, `microsoft.codesigning`, `microsoft.confidentialledger`, `microsoft.customerlockbox`, `microsoft.dynamics365fraudprotection`, `microsoft.hardwaresecuritymodules`, `microsoft.keyvault`, `microsoft.networksecurity`, `microsoft.pki`, `microsoft.privacy`, `microsoft.security`, `microsoft.securitybaseplatform`, `microsoft.securitycopilot`, `microsoft.securitydetonation`, `microsoft.securitydevops`, `microsoft.securityinsights`, `microsoft.securityplatform`, `microsoft.sentinelplatformservices`, `microsoft.systemintegritymonitoring`, `microsoft.zerotrustsegmentation`, `paloaltonetworks.cloudngfw`

### Storage

`commvault.contentstore`, `dell.storage`, `microsoft.baremetalstorageinfrastructure`, `microsoft.classicstorage`, `microsoft.clusterstor`, `microsoft.containerstorage`, `microsoft.datalakestore`, `microsoft.edgeorder`, `microsoft.edgeorderpartner`, `microsoft.elasticsan`, `microsoft.fileshares`, `microsoft.hybriddata`, `microsoft.netapp`, `microsoft.objectstore`, `microsoft.storage`, `microsoft.storageactions`, `microsoft.storagecache`, `microsoft.storagediscovery`, `microsoft.storageinsights`, `microsoft.storagemover`, `microsoft.storagepool`, `microsoft.storagesync`, `microsoft.storagetasks`, `microsoft.storsimple`, `purestorage.block`, `qumulo.qaas`, `qumulo.storage`

### Web — Web & Mobile

`microsoft.appplatform`, `microsoft.certificateregistration`, `microsoft.communication`, `microsoft.domainregistration`, `microsoft.fluidrelay`, `microsoft.gaming`, `microsoft.notificationhubs`, `microsoft.playfab`, `microsoft.signalrservice`, `microsoft.web`, `microsoft.webiq`, `microsoft.windowspushnotificationservices`, `sendgrid.email`

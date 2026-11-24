#
# Every Azure resource provider namespace, and the AzureScout category its resources belong to
# (AB#9300). Used by discovery so that EVERY discovered resource carries a category, not only the
# ones a collector reads.
#
# Resolution (Get-ScoutResourceCategory):
#   1. A collector that reads the type decides (its manifests/collectors/<Category> folder).
#   2. Otherwise the longest matching entry in Types (an exact type or a type prefix).
#   3. Otherwise the type's namespace in Namespaces.
#   4. Otherwise 'General', flagged as uncategorized in the discovery record.
#
# Namespaces covers every namespace in manifests/azure-provider-types.json (Get-AzResourceProvider
# -ListAvailable) and in Microsoft's Resource Graph table reference
# (learn.microsoft.com/azure/governance/resource-graph/reference/supported-tables-resources).
# tests/Discovery.ResourceCategories.Tests.ps1 fails when a namespace in either list has no entry,
# and docs/reference/resource-categories.md is generated from this file.
#
# Categories are the 18 in docs/reference/category-structure.md, which follow the Azure portal.
#
@{
    Categories = @('AI', 'Analytics', 'Compute', 'Containers', 'Databases', 'DevOps', 'General', 'Hybrid', 'Identity', 'Integration', 'IoT', 'Management', 'Migration', 'Monitor', 'Networking', 'Security', 'Storage', 'Web')

    # Type-level entries for namespaces whose resources span categories. A key matches the type
    # itself and every child type under it; the longest match wins.
    Types = @{
        'microsoft.authorization/roleassignments'                    = 'Identity'
        'microsoft.authorization/roledefinitions'                    = 'Identity'
        'microsoft.authorization/roleassignmentschedules'            = 'Identity'
        'microsoft.authorization/roleassignmentscheduleinstances'    = 'Identity'
        'microsoft.authorization/roleeligibilityschedules'           = 'Identity'
        'microsoft.authorization/roleeligibilityscheduleinstances'   = 'Identity'
        'microsoft.authorization/rolemanagementpolicies'             = 'Identity'
        'microsoft.authorization/rolemanagementpolicyassignments'    = 'Identity'
        'microsoft.authorization/classicadministrators'              = 'Identity'
        'microsoft.authorization/denyassignments'                    = 'Identity'
        'microsoft.compute/disks'                                    = 'Storage'
        'microsoft.compute/snapshots'                                = 'Storage'
        'microsoft.compute/diskaccesses'                             = 'Storage'
        'microsoft.compute/diskencryptionsets'                       = 'Storage'
        'microsoft.compute/virtualmachines/patchassessmentresults'   = 'Management'
        'microsoft.compute/virtualmachines/patchinstallationresults' = 'Management'
        'microsoft.hybridcompute/machines/patchassessmentresults'    = 'Management'
        'microsoft.hybridcompute/machines/patchinstallationresults'  = 'Management'
        'microsoft.web/connections'                                  = 'Integration'
        'microsoft.web/customapis'                                   = 'Integration'
        'microsoft.web/sites/workflows'                              = 'Integration'
        'microsoft.web/kubeenvironments'                             = 'Containers'
        'microsoft.network/firewallpolicies'                         = 'Security'
        'microsoft.network/applicationgatewaywebapplicationfirewallpolicies' = 'Security'
        'microsoft.network/frontdoorwebapplicationfirewallpolicies'  = 'Security'
        'microsoft.network/ddosprotectionplans'                      = 'Security'
        'microsoft.network/networksecurityperimeters'                = 'Security'
        'microsoft.cdn/cdnwebapplicationfirewallpolicies'            = 'Security'
        'microsoft.operationalinsights/workspaces/providers/microsoft.securityinsights' = 'Security'
        'microsoft.migrate/assessmentprojects'                       = 'Migration'
        'microsoft.eventhub/namespaces'                              = 'Analytics'
        'microsoft.resources/subscriptions'                          = 'Management'
        'microsoft.resources/resourcegroups'                         = 'Management'
    }

    Namespaces = @{
        # AI + Machine Learning
        'anyscale.platform' = 'AI'; 'arizeai.observabilityeval' = 'AI'; 'kore.agentplatform' = 'AI'; 'napster.companionapi' = 'AI'
        'pinecone.vectordb' = 'AI'; 'microsoft.autonomousdevelopmentplatform' = 'AI'; 'microsoft.autonomoussystems' = 'AI'
        'microsoft.bing' = 'AI'; 'microsoft.botservice' = 'AI'; 'microsoft.cognition' = 'AI'; 'microsoft.cognitivesearch' = 'AI'
        'microsoft.cognitiveservices' = 'AI'; 'microsoft.copilot' = 'AI'; 'microsoft.devai' = 'AI'; 'microsoft.discovery' = 'AI'
        'microsoft.foundrylocal' = 'AI'; 'microsoft.genome' = 'AI'; 'microsoft.healthbot' = 'AI'; 'microsoft.inferenceservice' = 'AI'
        'microsoft.machinelearning' = 'AI'; 'microsoft.machinelearningservices' = 'AI'; 'microsoft.modsimworkbench' = 'AI'
        'microsoft.orbital' = 'AI'; 'microsoft.recommendationsservice' = 'AI'; 'microsoft.search' = 'AI'; 'microsoft.singularity' = 'AI'
        'microsoft.syntex' = 'AI'; 'microsoft.videoindexer' = 'AI'; 'microsoft.weightsandbiases' = 'AI'

        # Analytics
        'astronomer.astro' = 'Analytics'; 'informatica.datamanagement' = 'Analytics'; 'microsoft.agfoodplatform' = 'Analytics'
        'microsoft.analysisservices' = 'Analytics'; 'microsoft.cleanroom' = 'Analytics'; 'microsoft.confluent' = 'Analytics'
        'microsoft.d365customerinsights' = 'Analytics'; 'microsoft.databricks' = 'Analytics'; 'microsoft.datacollaboration' = 'Analytics'
        'microsoft.datafactory' = 'Analytics'; 'microsoft.datalakeanalytics' = 'Analytics'; 'microsoft.dataplatform' = 'Analytics'
        'microsoft.datashare' = 'Analytics'; 'microsoft.energydataplatform' = 'Analytics'; 'microsoft.eventhub' = 'Analytics'
        'microsoft.fabric' = 'Analytics'; 'microsoft.hdinsight' = 'Analytics'; 'microsoft.kusto' = 'Analytics'; 'microsoft.kx' = 'Analytics'
        'microsoft.networkanalytics' = 'Analytics'; 'microsoft.openenergyplatform' = 'Analytics'; 'microsoft.powerbi' = 'Analytics'
        'microsoft.powerbidedicated' = 'Analytics'; 'microsoft.purview' = 'Analytics'; 'microsoft.streamanalytics' = 'Analytics'
        'microsoft.synapse' = 'Analytics'

        # Compute
        'citrix.services' = 'Compute'; 'microsoft.avs' = 'Compute'; 'microsoft.azurefleet' = 'Compute'; 'microsoft.azureimagetestingforlinux' = 'Compute'
        'microsoft.azurelargeinstance' = 'Compute'; 'microsoft.baremetal' = 'Compute'; 'microsoft.baremetalinfrastructure' = 'Compute'
        'microsoft.batch' = 'Compute'; 'microsoft.classiccompute' = 'Compute'; 'microsoft.compute' = 'Compute'
        'microsoft.computebulkactions' = 'Compute'; 'microsoft.computelimit' = 'Compute'; 'microsoft.computeschedule' = 'Compute'
        'microsoft.desktopvirtualization' = 'Compute'; 'microsoft.hanaonazure' = 'Compute'; 'microsoft.hpcworkbench' = 'Compute'
        'microsoft.ibmpower' = 'Compute'; 'microsoft.nutanix' = 'Compute'; 'microsoft.quantum' = 'Compute'; 'microsoft.remoteapp' = 'Compute'
        'microsoft.serialconsole' = 'Compute'; 'microsoft.skytap' = 'Compute'; 'microsoft.standbypool' = 'Compute'
        'microsoft.supercomputerinfrastructure' = 'Compute'; 'microsoft.swiftlet' = 'Compute'; 'microsoft.virtualmachineimages' = 'Compute'
        'microsoft.vmware' = 'Compute'; 'microsoft.windows365' = 'Compute'; 'microsoft.workloads' = 'Compute'

        # Containers
        'microsoft.app' = 'Containers'; 'microsoft.containerinstance' = 'Containers'; 'microsoft.containerregistry' = 'Containers'
        'microsoft.containerservice' = 'Containers'; 'microsoft.kubernetesruntime' = 'Containers'; 'microsoft.managedstorageclass' = 'Containers'
        'microsoft.redhatopenshift' = 'Containers'; 'microsoft.secretsynccontroller' = 'Containers'; 'microsoft.servicefabric' = 'Containers'
        'microsoft.servicefabricmesh' = 'Containers'

        # Databases
        'mongodb.atlas' = 'Databases'; 'oracle.database' = 'Databases'; 'microsoft.azuredata' = 'Databases'; 'microsoft.cache' = 'Databases'
        'microsoft.databasefleetmanager' = 'Databases'; 'microsoft.dbformariadb' = 'Databases'; 'microsoft.dbformysql' = 'Databases'
        'microsoft.dbforpostgresql' = 'Databases'; 'microsoft.documentdb' = 'Databases'; 'microsoft.horizondb' = 'Databases'
        'microsoft.infinitydb' = 'Databases'; 'microsoft.oriondb' = 'Databases'; 'microsoft.sql' = 'Databases'
        'microsoft.sqlvirtualmachine' = 'Databases'

        # DevOps
        'devops' = 'DevOps'; 'github.enterprise' = 'DevOps';'lambdatest.hyperexecute' = 'DevOps'; 'splitio.experimentation' = 'DevOps'
        'microsoft.anybuild' = 'DevOps'; 'microsoft.appconfiguration' = 'DevOps'; 'microsoft.azuredevopsplatform' = 'DevOps'
        'microsoft.azureplaywrightservice' = 'DevOps'; 'microsoft.azureterraform' = 'DevOps'; 'microsoft.chaos' = 'DevOps'
        'microsoft.cloudtest' = 'DevOps'; 'microsoft.codespaces' = 'DevOps'; 'microsoft.devcenter' = 'DevOps'
        'microsoft.developmentwindows365' = 'DevOps'; 'microsoft.devhub' = 'DevOps'; 'microsoft.devops' = 'DevOps'
        'microsoft.devopsinfrastructure' = 'DevOps'; 'microsoft.devtestlab' = 'DevOps'; 'microsoft.devtunnels' = 'DevOps'
        'microsoft.experimentation' = 'DevOps'; 'microsoft.labservices' = 'DevOps'; 'microsoft.loadtestservice' = 'DevOps'
        'microsoft.onlineexperimentation' = 'DevOps'; 'microsoft.platformvalidation' = 'DevOps'; 'microsoft.testbase' = 'DevOps'
        'microsoft.toolchainorchestrator' = 'DevOps'; 'microsoft.visualstudio' = 'DevOps'; 'microsoft.vsonline' = 'DevOps'

        # General: support, reservations, quotas, marketplace and platform plumbing
        'liftrbasic.samplerp' = 'General'; 'microsoft.addons' = 'General'; 'microsoft.alicespringsdataplane' = 'General'
        'microsoft.asterra' = 'General'; 'microsoft.azurecontextcache' = 'General'; 'microsoft.azurescan' = 'General'
        'microsoft.bami' = 'General'; 'microsoft.billingtrust' = 'General'; 'microsoft.blockchaintokens' = 'General'
        'microsoft.bluefin' = 'General'; 'microsoft.capacity' = 'General'; 'microsoft.cloudes' = 'General'; 'microsoft.cloudshell' = 'General'
        'microsoft.commerce' = 'General'; 'microsoft.community' = 'General'; 'microsoft.compositesolutions' = 'General'
        'microsoft.consumption' = 'General'; 'microsoft.contoso' = 'General'; 'microsoft.cosmic' = 'General'
        'microsoft.dataaccelerator' = 'General'; 'microsoft.decisionworkflows' = 'General'; 'microsoft.digitalassets' = 'General'
        'microsoft.edgemarketplace' = 'General'; 'microsoft.enterprisesupport' = 'General'; 'microsoft.falcon' = 'General'
        'microsoft.graduationtest' = 'General'; 'microsoft.hardware' = 'General'; 'microsoft.help' = 'General'
        'microsoft.liftrpilot' = 'General'; 'microsoft.marketplace' = 'General'; 'microsoft.marketplaceordering' = 'General'
        'microsoft.metaverse' = 'General'; 'microsoft.openlogisticsplatform' = 'General'; 'microsoft.partnerenrollment' = 'General'
        'microsoft.partnermanagedconsumerrecurrence' = 'General'; 'microsoft.portal' = 'General'; 'microsoft.portalsdk' = 'General'
        'microsoft.portalservices' = 'General'; 'microsoft.premonition' = 'General'; 'microsoft.professionalservice' = 'General'
        'microsoft.programenrollment' = 'General'; 'microsoft.proposal' = 'General'; 'microsoft.providerhub' = 'General'
        'microsoft.quota' = 'General'; 'microsoft.saas' = 'General'; 'microsoft.saashub' = 'General'; 'microsoft.serviceshub' = 'General'
        'microsoft.softwareplan' = 'General'; 'microsoft.spoolservice' = 'General'; 'microsoft.support' = 'General'
        'microsoft.symphony' = 'General'; 'microsoft.throttling' = 'General'; 'microsoft.usagebilling' = 'General'
        'microsoft.validate' = 'General'

        # Hybrid + multicloud
        'microsoft.arccontainerstorage' = 'Hybrid'; 'microsoft.arcnetworking' = 'Hybrid'; 'microsoft.awsconnector' = 'Hybrid'
        'microsoft.azurearcdata' = 'Hybrid'; 'microsoft.azurestack' = 'Hybrid'; 'microsoft.azurestackhci' = 'Hybrid'
        'microsoft.connectedcredentials' = 'Hybrid'; 'microsoft.connectedopenstack' = 'Hybrid'; 'microsoft.connectedvmwarevsphere' = 'Hybrid'
        'microsoft.deviceonboarding' = 'Hybrid'; 'microsoft.edge' = 'Hybrid'; 'microsoft.edgezones' = 'Hybrid'
        'microsoft.extendedlocation' = 'Hybrid'; 'microsoft.gcpconnector' = 'Hybrid'; 'microsoft.hybridcloud' = 'Hybrid'
        'microsoft.hybridcompute' = 'Hybrid'; 'microsoft.hybridconnectivity' = 'Hybrid'; 'microsoft.hybridcontainerservice' = 'Hybrid'
        'microsoft.kubernetes' = 'Hybrid'; 'microsoft.kubernetesconfiguration' = 'Hybrid'; 'microsoft.resourceconnector' = 'Hybrid'
        'microsoft.scvmm' = 'Hybrid'; 'microsoft.windowsesu' = 'Hybrid'

        # Identity
        'entra' = 'Identity'; 'microsoft.aad' = 'Identity'; 'microsoft.aadcustomsecurityattributesdiagnosticsettings' = 'Identity'
        'microsoft.aadiam' = 'Identity'; 'microsoft.adhybridhealthservice' = 'Identity'; 'microsoft.azureactivedirectory' = 'Identity'
        'microsoft.directorystore' = 'Identity'; 'microsoft.entitlementmanagement' = 'Identity'; 'microsoft.entraidgovernance' = 'Identity'
        'microsoft.entraidgovernanceaccelerator' = 'Identity'; 'microsoft.graph' = 'Identity'; 'microsoft.graphservices' = 'Identity'
        'microsoft.managedidentity' = 'Identity'; 'microsoft.verifiedid' = 'Identity'

        # Integration
        'microsoft.apicenter' = 'Integration'; 'microsoft.apimanagement' = 'Integration'; 'microsoft.applink' = 'Integration'
        'microsoft.biztalkservices' = 'Integration'; 'microsoft.durabletask' = 'Integration'; 'microsoft.eventgrid' = 'Integration'
        'microsoft.healthcareapis' = 'Integration'; 'microsoft.healthcareinterop' = 'Integration'; 'microsoft.healthdataaiservices' = 'Integration'
        'microsoft.healthplatform' = 'Integration'; 'microsoft.integrationspaces' = 'Integration'; 'microsoft.logic' = 'Integration'
        'microsoft.messagingcatalog' = 'Integration'; 'microsoft.messagingconnectors' = 'Integration'; 'microsoft.powerplatform' = 'Integration'
        'microsoft.relay' = 'Integration'; 'microsoft.servicebus' = 'Integration'; 'microsoft.servicelinker' = 'Integration'

        # Internet of Things
        'microsoft.azurepercept' = 'IoT'; 'microsoft.azuresphere' = 'IoT'; 'microsoft.clouddeviceplatform' = 'IoT'
        'microsoft.connectedvehicle' = 'IoT'; 'microsoft.deviceregistry' = 'IoT'; 'microsoft.devices' = 'IoT'; 'microsoft.deviceupdate' = 'IoT'
        'microsoft.digitaltwins' = 'IoT'; 'microsoft.iotcentral' = 'IoT'; 'microsoft.iotfirmwaredefense' = 'IoT'; 'microsoft.iotoperations' = 'IoT'
        'microsoft.iotoperationsdataprocessor' = 'IoT'; 'microsoft.iotoperationsmq' = 'IoT'; 'microsoft.iotoperationsorchestrator' = 'IoT'
        'microsoft.iotsecurity' = 'IoT'; 'microsoft.maps' = 'IoT'; 'microsoft.timeseriesinsights' = 'IoT'; 'microsoft.windowsiot' = 'IoT'

        # Management and governance
        'automationprojects' = 'Management'; 'microsoft.advisor' = 'Management'; 'microsoft.approvals' = 'Management'
        'microsoft.authorization' = 'Management'; 'microsoft.automanage' = 'Management'; 'microsoft.automation' = 'Management'
        'microsoft.azurebusinesscontinuity' = 'Management'; 'microsoft.azureresiliencemanagement' = 'Management'
        'microsoft.backupsolutions' = 'Management'; 'microsoft.billing' = 'Management'; 'microsoft.billingbenefits' = 'Management'
        'microsoft.blueprint' = 'Management'; 'microsoft.carbon' = 'Management'; 'microsoft.changesafety' = 'Management'
        'microsoft.costmanagement' = 'Management'; 'microsoft.costmanagementexports' = 'Management'; 'microsoft.customproviders' = 'Management'
        'microsoft.dataprotection' = 'Management'; 'microsoft.datareplication' = 'Management'; 'microsoft.easm' = 'Management'
        'microsoft.features' = 'Management'; 'microsoft.guestconfiguration' = 'Management'; 'microsoft.maintenance' = 'Management'
        'microsoft.managedops' = 'Management'; 'microsoft.managedservices' = 'Management'; 'microsoft.management' = 'Management'
        'microsoft.mission' = 'Management'; 'microsoft.policyinsights' = 'Management'; 'microsoft.recoveryservices' = 'Management'
        'microsoft.relationships' = 'Management'; 'microsoft.resiliency' = 'Management'; 'microsoft.resourcebuilder' = 'Management'
        'microsoft.resourcegraph' = 'Management'; 'microsoft.resourceintelligence' = 'Management'; 'microsoft.resources' = 'Management'
        'microsoft.solutions' = 'Management'; 'microsoft.sovereign' = 'Management'; 'microsoft.subscription' = 'Management'
        'microsoft.sustainabilityservices' = 'Management'; 'microsoft.updatemanager' = 'Management'; 'microsoft.workloadbuilder' = 'Management'

        # Migration
        'wandisco.fusion' = 'Migration'; 'microsoft.applicationmigration' = 'Migration'; 'microsoft.appassessment' = 'Migration'
        'microsoft.azuredatatransfer' = 'Migration'; 'microsoft.databox' = 'Migration'; 'microsoft.databoxedge' = 'Migration'
        'microsoft.datamigration' = 'Migration'; 'microsoft.dependencymap' = 'Migration'; 'microsoft.importexport' = 'Migration'
        'microsoft.migrate' = 'Migration'; 'microsoft.mysqldiscovery' = 'Migration'; 'microsoft.offazure' = 'Migration'
        'microsoft.offazurespringboot' = 'Migration'; 'microsoft.resourcemover' = 'Migration'

        # Monitor
        'dynatrace.observability' = 'Monitor'; 'newrelic.observability' = 'Monitor'; 'microsoft.alertsmanagement' = 'Monitor'
        'microsoft.cloudhealth' = 'Monitor'; 'microsoft.dashboard' = 'Monitor'; 'microsoft.databasewatcher' = 'Monitor'
        'microsoft.datadog' = 'Monitor'; 'microsoft.elastic' = 'Monitor'; 'microsoft.footprintmonitoring' = 'Monitor'
        'microsoft.healthmodel' = 'Monitor'; 'microsoft.impact' = 'Monitor'; 'microsoft.insights' = 'Monitor'; 'microsoft.monitor' = 'Monitor'
        'microsoft.operationalinsights' = 'Monitor'; 'microsoft.operationsmanagement' = 'Monitor'
        'microsoft.powerplatformmonitoringhub' = 'Monitor'; 'microsoft.resourcehealth' = 'Monitor'; 'microsoft.resourcenotifications' = 'Monitor'
        'microsoft.scom' = 'Monitor'

        # Networking
        'github.network' = 'Networking'; 'nginx.nginxplus' = 'Networking'; 'microsoft.cdn' = 'Networking'; 'microsoft.classicnetwork' = 'Networking'
        'microsoft.connectedcache' = 'Networking'; 'microsoft.delegatednetwork' = 'Networking'; 'microsoft.dns' = 'Networking'
        'microsoft.hybridnetwork' = 'Networking'; 'microsoft.managednetworkfabric' = 'Networking'; 'microsoft.mobilepacketcore' = 'Networking'
        'microsoft.network' = 'Networking'; 'microsoft.networkcloud' = 'Networking'; 'microsoft.networkfunction' = 'Networking'
        'microsoft.networkresourceprovider' = 'Networking'; 'microsoft.nexusidentity' = 'Networking'; 'microsoft.operatorvoicemail' = 'Networking'
        'microsoft.peering' = 'Networking'; 'microsoft.programmableconnectivity' = 'Networking'; 'microsoft.servicenetworking' = 'Networking'

        # Security
        'paloaltonetworks.cloudngfw' = 'Security'; 'microsoft.appcomplianceautomation' = 'Security'; 'microsoft.appsecurity' = 'Security'
        'microsoft.attestation' = 'Security'; 'microsoft.codesigning' = 'Security'; 'microsoft.confidentialledger' = 'Security'
        'microsoft.customerlockbox' = 'Security'; 'microsoft.dynamics365fraudprotection' = 'Security'
        'microsoft.hardwaresecuritymodules' = 'Security'; 'microsoft.keyvault' = 'Security'; 'microsoft.networksecurity' = 'Security'
        'microsoft.pki' = 'Security'; 'microsoft.privacy' = 'Security'; 'microsoft.security' = 'Security'
        'microsoft.securitybaseplatform' = 'Security'; 'microsoft.securitycopilot' = 'Security'; 'microsoft.securitydetonation' = 'Security'
        'microsoft.securitydevops' = 'Security'; 'microsoft.securityinsights' = 'Security'; 'microsoft.securityplatform' = 'Security'
        'microsoft.sentinelplatformservices' = 'Security'; 'microsoft.systemintegritymonitoring' = 'Security'
        'microsoft.zerotrustsegmentation' = 'Security'

        # Storage
        'commvault.contentstore' = 'Storage'; 'dell.storage' = 'Storage'; 'purestorage.block' = 'Storage'; 'qumulo.qaas' = 'Storage'
        'qumulo.storage' = 'Storage'; 'microsoft.baremetalstorageinfrastructure' = 'Storage'; 'microsoft.classicstorage' = 'Storage'
        'microsoft.clusterstor' = 'Storage'; 'microsoft.containerstorage' = 'Storage'; 'microsoft.datalakestore' = 'Storage'
        'microsoft.edgeorder' = 'Storage'; 'microsoft.edgeorderpartner' = 'Storage'; 'microsoft.elasticsan' = 'Storage'
        'microsoft.fileshares' = 'Storage'; 'microsoft.hybriddata' = 'Storage'; 'microsoft.netapp' = 'Storage'; 'microsoft.objectstore' = 'Storage'
        'microsoft.storage' = 'Storage'; 'microsoft.storageactions' = 'Storage'; 'microsoft.storagecache' = 'Storage'
        'microsoft.storagediscovery' = 'Storage'; 'microsoft.storageinsights' = 'Storage'; 'microsoft.storagemover' = 'Storage'
        'microsoft.storagepool' = 'Storage'; 'microsoft.storagesync' = 'Storage'; 'microsoft.storagetasks' = 'Storage'
        'microsoft.storsimple' = 'Storage'

        # Web & Mobile
        'sendgrid.email' = 'Web'; 'microsoft.appplatform' = 'Web'; 'microsoft.certificateregistration' = 'Web'; 'microsoft.communication' = 'Web'
        'microsoft.domainregistration' = 'Web'; 'microsoft.fluidrelay' = 'Web'; 'microsoft.gaming' = 'Web'; 'microsoft.notificationhubs' = 'Web'
        'microsoft.playfab' = 'Web'; 'microsoft.signalrservice' = 'Web'; 'microsoft.web' = 'Web'; 'microsoft.webiq' = 'Web'
        'microsoft.windowspushnotificationservices' = 'Web'
    }
}

---
description: AST-based classification of all 174 inventory collectors — how many are pure data-shaping and what makes the rest not that. Delivers AB#5658 under Feature AB#5656, Epic AB#5638.
---

# Collector audit — AB#5658

> **Status:** Complete 2026-07-25. First deliverable of the declarative-collector rebuild
> (Feature **AB#5656**, Epic **AB#5638**) — done before any schema was designed, per the
> feature's own instruction.

## 1. Method

Every collector under `manifests/collectors/` was parsed with the PowerShell AST
(`[System.Management.Automation.Language.Parser]::ParseFile`) — never by regex over the source
text — using
[`scripts/Invoke-CollectorAudit.ps1`](https://github.com/thisismydemo/azure-scout/blob/main/scripts/Invoke-CollectorAudit.ps1). Discovery reuses
`src/pipeline/Get-ScoutCollector.ps1`, the single discovery implementation the deterministic-
pipeline work (AB#5649) established, rather than re-walking the filesystem a second way.

For each of the 174 collectors the script structurally extracts:

- the Azure resource type(s) its Processing branch filters `$Resources` by (`$_.TYPE -eq '...'`
  inside a `$Resources | Where-Object {...}` pipeline)
- the row schema: the field names of the near-universal `$obj = @{ 'Key' = ...; ... }` hashtable
  literal — **all 174 files use exactly this convention** — plus the ordered Excel export
  column list from the `$Exc.Add('Column')` calls in the Reporting branch
- whether it correlates against `$Sub` (subscription-name lookup) and/or
  `$Retirements`/`$Unsupported` (retirement cross-reference)
- whether it filters `$Resources` by **more than one** resource type and then genuinely
  correlates between those sets — either inside the per-row loop, or by unioning several
  filtered sets into a combined collection before looping over that
- whether it calls a cmdlet that reaches Azure/Graph **itself** (`Get-Az*`, `Invoke-Az*`,
  `Invoke-RestMethod`, `Invoke-WebRequest`, `Get-Msol*`, `Get-Mg*`, `Invoke-Mg*`) instead of
  shaping the `$Resources` array it was handed

The machine-readable result is
[`tests/fixtures/collector-audit.json`](https://github.com/thisismydemo/azure-scout/blob/main/tests/fixtures/collector-audit.json), one record
per collector. Re-run the audit at any time with:

```powershell
./scripts/Invoke-CollectorAudit.ps1
```

### What counts as a standard primitive, not an escape hatch

Two patterns appear in almost every file and are treated as **declarative building blocks the
schema must support directly**, not as evidence a collector needs an escape hatch:

| Primitive | Present in | What it does |
|---|---|---|
| `$Sub` correlation | 150 / 174 | `$sub1 = $SUB \| Where-Object { $_.id -eq $1.subscriptionId }` — subscription id → name lookup |
| Retirement/unsupported cross-reference | 88 / 174 | Looks up `$1.id` against `$Retirements`, then `$Unsupported` by `ServiceID`, and folds one-or-many retiring features/dates into a single display string |
| Tag expansion | effectively universal | One output row per tag on the resource (or one row with empty tag columns when there are none), gated on `$InTag` for whether the two Tag columns are exported at all |

A collector is classified an **escape hatch** only when it does something a per-field
expression language over a single filtered resource set cannot express.

The external-access classifier uses `CommandAst` names rather than a broad text or prefix match.
It explicitly recognises `Search-AzGraph` and `New-Object -Com`, while excluding the in-process
`Get-AZSCSafeProperty`, `Get-AZSCIdSegment`, and `Get-AZSCCollectedValue` helpers. Focused tests pin
both failure directions so a future classifier cannot silently move pure shaping into the escape
set or miss a non-`Get`/`Invoke` external dependency.

## 2. Headline numbers

| | Count |
|---|---|
| Total collectors | 174 |
| Standard contract (the `param($SCPath, $Sub, ...)` shape) | 174 |
| **Pure shaping** | **126 (72%)** |
| **Needs an escape hatch** | **48 (28%)** |

Escape-hatch reasons (a collector can have more than one):

| Reason | Count | What it looks like |
|---|---|---|
| Cross-resource join | 20 | Filters `$Resources` by more than one type and correlates between the sets — either inside the per-row loop (`Compute/AVD.ps1` joins hostpools → sessionhosts → VMs) or by unioning several filtered sets before looping over the union (`Compute/AVDAzureLocal.ps1` combines Arc machines + HCI VM instances + a synthesized session-host set) |
| External access | 31 | Calls `Get-Az*`/`Invoke-AzRestMethod`/`Search-AzGraph`/etc. or constructs a COM object rather than shaping the `$Resources` it was handed — e.g. `AI/MLModels.ps1` calls `Invoke-AzRestMethod` per workspace, `Management/AllSubscriptions.ps1` calls `Search-AzGraph`, and `Monitor/Outages.ps1` constructs `HTMLFile` through COM |
| No `$Resources` filter at all | 10 | Builds its row set entirely from live cmdlet output (all 10 overlap with "live cmdlet call" above) — `Management/PolicyDefinitions.ps1`, all four `Security/Defender*.ps1`, etc. |

Per-category breakdown:

| Category | Total | Pure | Escape |
|---|---|---|---|
| AI | 27 | 19 | 8 |
| Analytics | 6 | 5 | 1 |
| Compute | 14 | 8 | 6 |
| Containers | 6 | 4 | 2 |
| Databases | 13 | **13** | **0** |
| Hybrid | 16 | 14 | 2 |
| Identity | 16 | **16** | **0** |
| Integration | 2 | 2 | 0 |
| IoT | 1 | 1 | 0 |
| Management | 19 | 11 | 8 |
| Monitor | 24 | 17 | 7 |
| Networking | 21 | 13 | 8 |
| Security | 5 | 1 | 4 |
| Storage | 2 | 1 | 1 |
| Web | 2 | 1 | 1 |

`Databases` is 100% pure shaping — every field is a direct projection or a small conditional
expression over a single filtered resource type, with no joins and no live calls. That, plus a
useful spread of expression complexity (conditional nulls, unit conversions, string splits,
elastic-pool cross-references *within the same resource*), is why it is the category converted
end-to-end as the schema's proof (AB#5659/AB#5660) rather than a smaller or more trivial one.
`Security` is nearly the opposite case: 4 of its 5 collectors are Defender API wrappers with no
`$Resources` filter at all.

Averaged over the 174 Standard-contract collectors: **18.8** processing fields and **17.4**
exported Excel columns per collector (export is almost always processing-fields-minus-`ID`, since
the internal correlation key is dropped before the sheet is written). The largest is
`Compute/VirtualMachine.ps1` at 59 fields — it joins five other resource types (NICs, VM
extensions, disks, VNets, and two synthetic `AZSC/VM/*` correlation tables) plus a live
`Invoke-AzRestMethod` call, and is comfortably the most complex single collector in the estate.

## 3. Full table

Class: **Pure** = pure shaping. **Escape** = needs an escape hatch, with the specific
construct(s) that force it (`CrossResourceJoin`, `LiveCmdletCall`, `NoResourcesFilter`,
`UnimplementedContract` — see §1 and §4). Fields/Cols are `ProcessingFieldCount` /
`ExportColumnCount` from the JSON fixture.

| Category | Collector | Class | Fields | Cols | Escape-hatch reason |
|---|---|---|---|---|---|
| AI | AIFoundryHubs | Pure | 17 | 16 |  |
| AI | AIFoundryProjects | Pure | 18 | 16 |  |
| AI | AppliedAIServices | Pure | 16 | 15 |  |
| AI | AzureAI | Pure | 19 | 18 |  |
| AI | BotServices | Pure | 18 | 15 |  |
| AI | ComputerVision | Pure | 19 | 18 |  |
| AI | ContentModerator | Pure | 19 | 18 |  |
| AI | ContentSafety | Pure | 19 | 18 |  |
| AI | CustomVision | Pure | 20 | 19 |  |
| AI | FaceAPI | Pure | 19 | 18 |  |
| AI | FormRecognizer | Pure | 19 | 18 |  |
| AI | HealthInsights | Pure | 20 | 19 |  |
| AI | ImmersiveReader | Pure | 19 | 18 |  |
| AI | MachineLearning | Pure | 24 | 23 |  |
| AI | MLComputes | Escape | 15 | 13 | LiveCmdletCall |
| AI | MLDatasets | Escape | 12 | 10 | LiveCmdletCall |
| AI | MLDatastores | Escape | 13 | 11 | LiveCmdletCall |
| AI | MLEndpoints | Escape | 13 | 11 | LiveCmdletCall |
| AI | MLModels | Escape | 11 | 9 | LiveCmdletCall |
| AI | MLPipelines | Escape | 15 | 13 | LiveCmdletCall |
| AI | OpenAIAccounts | Pure | 16 | 15 |  |
| AI | OpenAIDeployments | Escape | 15 | 13 | LiveCmdletCall |
| AI | SearchIndexes | Escape | 14 | 11 | LiveCmdletCall |
| AI | SearchServices | Pure | 21 | 20 |  |
| AI | SpeechService | Pure | 19 | 18 |  |
| AI | TextAnalytics | Pure | 20 | 19 |  |
| AI | Translator | Pure | 19 | 18 |  |
| Analytics | Databricks | Pure | 22 | 21 |  |
| Analytics | DataExplorerCluster | Pure | 26 | 25 |  |
| Analytics | EvtHub | Pure | 21 | 20 |  |
| Analytics | Purview | Pure | 21 | 20 |  |
| Analytics | Streamanalytics | Escape | 33 | 32 | CrossResourceJoin |
| Analytics | Synapse | Pure | 20 | 19 |  |
| Compute | AvailabilitySets | Pure | 14 | 13 |  |
| Compute | AVD | Escape | 27 | 26 | CrossResourceJoin |
| Compute | AVDApplicationGroups | Pure | 14 | 13 |  |
| Compute | AVDApplications | Escape | 15 | 12 | LiveCmdletCall |
| Compute | AVDAzureLocal | Escape | 18 | 16 | CrossResourceJoin |
| Compute | AVDScalingPlans | Pure | 18 | 16 |  |
| Compute | AVDSessionHosts | Pure | 19 | 17 |  |
| Compute | AVDWorkspaces | Pure | 15 | 14 |  |
| Compute | CloudServices | Pure | 13 | 12 |  |
| Compute | VirtualMachine | Escape | 59 | 58 | CrossResourceJoin; LiveCmdletCall |
| Compute | VirtualMachineScaleSet | Escape | 37 | 36 | CrossResourceJoin |
| Compute | VMDisk | Pure | 27 | 26 |  |
| Compute | VMOperationalData | Escape | 29 | 28 | CrossResourceJoin; LiveCmdletCall |
| Compute | VMWare | Pure | 26 | 25 |  |
| Containers | AKS | Escape | 57 | 56 | CrossResourceJoin |
| Containers | ARO | Pure | 30 | 29 |  |
| Containers | ContainerApp | Pure | 25 | 24 |  |
| Containers | ContainerAppEnv | Escape | 19 | 18 | CrossResourceJoin |
| Containers | ContainerGroups | Pure | 22 | 21 |  |
| Containers | ContainerRegistries | Pure | 20 | 18 |  |
| Databases | CosmosDB | Pure | 27 | 26 |  |
| Databases | MariaDB | Pure | 29 | 28 |  |
| Databases | MySQL | Pure | 29 | 28 |  |
| Databases | MySQLflexible | Pure | 28 | 27 |  |
| Databases | POSTGRE | Pure | 29 | 28 |  |
| Databases | POSTGREFlexible | Pure | 29 | 28 |  |
| Databases | RedisCache | Pure | 26 | 25 |  |
| Databases | SQLDB | Pure | 24 | 22 |  |
| Databases | SQLMI | Pure | 21 | 20 |  |
| Databases | SQLMIDB | Pure | 13 | 12 |  |
| Databases | SQLPOOL | Pure | 19 | 17 |  |
| Databases | SQLSERVER | Pure | 19 | 18 |  |
| Databases | SQLVM | Pure | 15 | 14 |  |
| Hybrid | ArcDataControllers | Pure | 14 | 13 |  |
| Hybrid | ArcExtensions | Pure | 22 | 21 |  |
| Hybrid | ArcGateways | Pure | 15 | 14 |  |
| Hybrid | ArcKubernetes | Pure | 21 | 20 |  |
| Hybrid | ArcResourceBridge | Pure | 17 | 16 |  |
| Hybrid | ArcServerOperationalData | Escape | 28 | 27 | CrossResourceJoin; LiveCmdletCall |
| Hybrid | ARCServers | Escape | 43 | 41 | LiveCmdletCall |
| Hybrid | ArcSites | Pure | 14 | 13 |  |
| Hybrid | ArcSQLManagedInstances | Pure | 19 | 17 |  |
| Hybrid | ArcSQLServers | Pure | 19 | 17 |  |
| Hybrid | Clusters | Pure | 23 | 21 |  |
| Hybrid | GalleryImages | Pure | 18 | 17 |  |
| Hybrid | LogicalNetworks | Pure | 19 | 18 |  |
| Hybrid | MarketplaceGalleryImages | Pure | 20 | 19 |  |
| Hybrid | StorageContainers | Pure | 15 | 14 |  |
| Hybrid | VirtualMachines | Pure | 24 | 23 |  |
| Identity | AdminUnits | Pure | 8 | 6 |  |
| Identity | AppRegistrations | Pure | 11 | 9 |  |
| Identity | ConditionalAccess | Pure | 12 | 10 |  |
| Identity | CrossTenantAccess | Pure | 9 | 7 |  |
| Identity | DirectoryRoles | Pure | 6 | 4 |  |
| Identity | Domains | Pure | 9 | 7 |  |
| Identity | Groups | Pure | 12 | 10 |  |
| Identity | Licensing | Pure | 11 | 9 |  |
| Identity | ManagedIdentities | Pure | 7 | 5 |  |
| Identity | ManagedIds | Pure | 9 | 7 |  |
| Identity | NamedLocations | Pure | 10 | 8 |  |
| Identity | PIMAssignments | Pure | 9 | 7 |  |
| Identity | RiskyUsers | Pure | 11 | 9 |  |
| Identity | SecurityPolicies | Pure | 13 | 11 |  |
| Identity | ServicePrincipals | Pure | 11 | 9 |  |
| Identity | Users | Pure | 14 | 12 |  |
| Integration | APIM | Pure | 24 | 23 |  |
| Integration | ServiceBUS | Pure | 16 | 15 |  |
| IoT | IOTHubs | Pure | 20 | 19 |  |
| Management | AdvisorScore | Pure | 11 | 9 |  |
| Management | AllSubscriptions | Escape | 13 | 12 | LiveCmdletCall |
| Management | AutomationAccounts | Escape | 18 | 17 | CrossResourceJoin |
| Management | Backup | Escape | 29 | 28 | CrossResourceJoin |
| Management | CustomRoleDefinitions | Escape | 15 | 14 | LiveCmdletCall; NoResourcesFilter |
| Management | DevOpsAgentPools | Pure | 12 | 11 |  |
| Management | DevOpsPipelines | Pure | 11 | 10 |  |
| Management | DevOpsProjects | Pure | 10 | 9 |  |
| Management | DevOpsRepositories | Pure | 9 | 8 |  |
| Management | DevOpsServiceConnections | Pure | 14 | 13 |  |
| Management | LighthouseDelegations | Pure | 14 | 13 |  |
| Management | MaintenanceConfigurations | Pure | 23 | 22 |  |
| Management | ManagementGroups | Escape | 11 | 11 | LiveCmdletCall; NoResourcesFilter |
| Management | PolicyComplianceStates | Escape | 18 | 18 | LiveCmdletCall; NoResourcesFilter |
| Management | PolicyDefinitions | Escape | 13 | 12 | LiveCmdletCall; NoResourcesFilter |
| Management | PolicySetDefinitions | Escape | 14 | 13 | LiveCmdletCall; NoResourcesFilter |
| Management | RecoveryVault | Pure | 14 | 13 |  |
| Management | ReservationRecom | Pure | 16 | 14 |  |
| Management | SupportTickets | Pure | 17 | 15 |  |
| Monitor | ActionGroups | Pure | 18 | 17 |  |
| Monitor | ActivityLogAlertRules | Pure | 17 | 14 |  |
| Monitor | AppInsights | Pure | 22 | 19 |  |
| Monitor | AppInsightsAvailabilityTests | Pure | 18 | 13 |  |
| Monitor | AppInsightsContinuousExport | Escape | 15 | 12 | LiveCmdletCall |
| Monitor | AppInsightsProactiveDetection | Escape | 12 | 10 | LiveCmdletCall |
| Monitor | AppInsightsWebTests | Pure | 20 | 17 |  |
| Monitor | AppInsightsWorkItems | Escape | 10 | 8 | LiveCmdletCall |
| Monitor | AutoscaleSettings | Pure | 20 | 16 |  |
| Monitor | DataCollectionEndpoints | Pure | 16 | 15 |  |
| Monitor | DataCollectionRules | Pure | 15 | 14 |  |
| Monitor | LAWorkspaceLinkedServices | Escape | 12 | 8 | LiveCmdletCall |
| Monitor | LAWorkspaceSavedSearches | Escape | 11 | 8 | LiveCmdletCall |
| Monitor | LAWorkspaceSolutions | Pure | 14 | 10 |  |
| Monitor | MetricAlertRules | Pure | 19 | 18 |  |
| Monitor | MonitorMetricsIngestion | Pure | 16 | 13 |  |
| Monitor | MonitorPrivateLinkScopes | Pure | 14 | 11 |  |
| Monitor | MonitorWorkbooks | Pure | 15 | 11 |  |
| Monitor | Outages | Escape | 16 | 14 | LiveCmdletCall |
| Monitor | ResourceDiagnosticSettings | Pure | 16 | 13 |  |
| Monitor | ScheduledQueryRules | Pure | 19 | 18 |  |
| Monitor | SmartDetectorAlertRules | Pure | 16 | 13 |  |
| Monitor | SubscriptionDiagnosticSettings | Escape | 11 | 10 | LiveCmdletCall; NoResourcesFilter |
| Monitor | Workspaces | Pure | 16 | 15 |  |
| Networking | ApplicationGateways | Escape | 24 | 23 | CrossResourceJoin |
| Networking | AzureFirewall | Escape | 32 | 31 | CrossResourceJoin |
| Networking | BastionHosts | Pure | 15 | 14 |  |
| Networking | Connections | Pure | 29 | 28 |  |
| Networking | ExpressRoute | Pure | 19 | 18 |  |
| Networking | Frontdoor | Pure | 20 | 18 |  |
| Networking | LoadBalancer | Pure | 19 | 18 |  |
| Networking | NATGateway | Pure | 16 | 15 |  |
| Networking | NetworkInterface | Escape | 27 | 26 | CrossResourceJoin |
| Networking | NetworkSecurityGroup | Escape | 25 | 24 | CrossResourceJoin |
| Networking | NetworkWatchers | Escape | 15 | 14 | CrossResourceJoin |
| Networking | PrivateDNS | Escape | 14 | 13 | CrossResourceJoin |
| Networking | PrivateEndpoint | Escape | 18 | 17 | CrossResourceJoin |
| Networking | PublicDNS | Pure | 14 | 13 |  |
| Networking | PublicIP | Pure | 18 | 17 |  |
| Networking | RouteTables | Pure | 17 | 16 |  |
| Networking | TrafficManager | Pure | 14 | 13 |  |
| Networking | VirtualNetwork | Pure | 23 | 22 |  |
| Networking | VirtualNetworkGateways | Pure | 33 | 32 |  |
| Networking | VirtualWAN | Escape | 25 | 24 | CrossResourceJoin |
| Networking | vNETPeering | Pure | 19 | 18 |  |
| Security | DefenderAlerts | Escape | 16 | 15 | LiveCmdletCall; NoResourcesFilter |
| Security | DefenderAssessments | Escape | 16 | 15 | LiveCmdletCall; NoResourcesFilter |
| Security | DefenderPricing | Escape | 12 | 11 | LiveCmdletCall; NoResourcesFilter |
| Security | DefenderSecureScore | Escape | 12 | 11 | LiveCmdletCall; NoResourcesFilter |
| Security | Vault | Pure | 22 | 21 |  |
| Storage | NetApp | Pure | 26 | 25 |  |
| Storage | StorageAccounts | Escape | 41 | 40 | LiveCmdletCall |
| Web | APPServicePlan | Escape | 21 | 20 | CrossResourceJoin |
| Web | APPServices | Pure | 37 | 36 |  |

## 4. Removed dead registration-contract collectors

`Identity/IdentityProviders.ps1` and `Identity/SecurityDefaults.ps1` were removed during the
v3 rebuild. They depended on a registration API that was only mocked by tests and was never
implemented by the module, so neither could produce a row in a shipped run. The processing and
reporting special cases were removed with them. The Entra extraction capability remains separate
from this retired inventory-collector contract.

## 5. What this means for the schema (AB#5657)

- The **majority declarative surface** the schema must cover, in order of how often it appears:
  a single resource-type filter, a row-per-match with a fixed set of named fields (mostly direct
  `$data.<property>` projections, some unit conversions and string formatting), the `$Sub`
  lookup, the retirement cross-reference, the per-tag row expansion gated on `$InTag`, and the
  ordered Excel export column list with its worksheet name and conditional-formatting rules.
- The **escape hatch** must cover, cleanly, the 46 real cases (excluding the 2 recommended for
  deletion): multi-resource-type joins/unions and calls to live Azure/Graph cmdlets. Both need
  the full `$Resources`/`$Sub`/`$Retirements`/`$Unsupported` context a Standard collector already
  receives — the escape hatch is not a smaller sandbox, it is a named script block that gets the
  same inputs a hand-written collector always had.
- The proof of the schema converts **`Databases`** (13 collectors, 100% pure shaping, 13–29
  fields each) end-to-end, per AB#5659/AB#5660.

# WAF — enumerated source for the Well-Architected service guides

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `waf.serviceguides.yaml` scores an estate against the "Configuration recommendations" that
Microsoft publishes in each Azure Well-Architected Framework
[service guide](https://learn.microsoft.com/azure/well-architected/service-guides/). This page enumerates the recommendations Scout turns into a
rule. `src/assess/rules/waf.serviceguides.yaml` is written against this page only, and every rule
cites an item number from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Well-Architected Framework perspective on Azure services](https://learn.microsoft.com/azure/well-architected/service-guides/) (20 service guides read; Microsoft publishes no assessment questions for them) |
| Framework version | Azure Well-Architected Framework service guides on Microsoft Learn, current; guide pages last updated between 2025-02 and 2026-11 |
| Extraction date | 2026-11-25 |
| Verification method | Each guide page below was fetched in full on 2026-11-25 (the Azure Kubernetes Service and App Service guides with the Microsoft Learn MCP `microsoft_docs_fetch` tool, the rest from the Microsoft Learn markdown endpoint, which serves the same page), and its Configuration recommendations tables, workload design checklists and Azure policies sections were read. Every field an automated item reads was checked against the collect contract in `src/collect/Invoke-Collect.ps1` and the KQL that projects it. |

## The one thing this enumeration is NOT

**It is not a list Microsoft numbers.** The guides carry unnumbered recommendation tables, and
Microsoft publishes no assessment for them. The items below are **Scout's** reading of those
tables, and the `WAF-SVC-*` IDs are Scout's. Where one recommendation is split across several
settings, each setting is its own item; where a recommendation is a process (rehearse a failover,
review a policy), it is a manual item.

Two of the guides are not in the index page's list but are published and are covered: Azure
Container Apps and Azure Virtual WAN. The Virtual Machines guide covers virtual machines and scale
sets together, so scale-set items carry their own `WAF-SVC-VMSS` prefix. The guides for Blob
Storage, Cosmos DB, MySQL, PostgreSQL, SQL, Managed Redis, Databricks, Event Hubs, Machine
Learning, Azure Local, Log Analytics, Service Fabric and HorizonDB are not enumerated here; several
are already scored by their own rule files.

## Reading the tables

- **Scout ✅** means a collected field answers the item, and the rule lists the resources that break
  it. **Scout ❌ Manual** means no collected field answers it; where there is some related evidence
  it is attached to the question.
- Automated items are **gated**: they run only when the guide's resource type exists, so an estate
  without it reports the item Not assessed. Manual items are gated the same way.
- Zone items are limited to the regions in Scout's zone-eligible list. A resource in a region
  without availability zones is not failed for lacking them.
- Recommendations that conflict across pillars (a Premium tier for reliability against Basic for
  cost, scale to zero against replica counts) are scored on the stricter reliability or security
  reading at low or medium severity, and the remediation says when a lower setting is legitimate.

Guides enumerated:

- **Azure Kubernetes Service** — [azure-kubernetes-service](https://learn.microsoft.com/azure/well-architected/service-guides/azure-kubernetes-service)
- **Azure App Service (Web Apps)** — [app-service-web-apps](https://learn.microsoft.com/azure/well-architected/service-guides/app-service-web-apps)
- **Azure Functions** — [azure-functions](https://learn.microsoft.com/azure/well-architected/service-guides/azure-functions)
- **Azure Container Apps** — [azure-container-apps](https://learn.microsoft.com/azure/well-architected/service-guides/azure-container-apps)
- **Azure API Management** — [azure-api-management](https://learn.microsoft.com/azure/well-architected/service-guides/azure-api-management)
- **Azure Service Bus** — [azure-service-bus](https://learn.microsoft.com/azure/well-architected/service-guides/azure-service-bus)
- **Azure Event Grid** — [azure-event-grid](https://learn.microsoft.com/azure/well-architected/service-guides/azure-event-grid)
- **Azure Firewall** — [azure-firewall](https://learn.microsoft.com/azure/well-architected/service-guides/azure-firewall)
- **Azure Application Gateway** — [azure-application-gateway](https://learn.microsoft.com/azure/well-architected/service-guides/azure-application-gateway)
- **Azure Load Balancer** — [azure-load-balancer](https://learn.microsoft.com/azure/well-architected/service-guides/azure-load-balancer)
- **Azure Virtual Network** — [virtual-network](https://learn.microsoft.com/azure/well-architected/service-guides/virtual-network)
- **Azure Virtual Machines** — [virtual-machines](https://learn.microsoft.com/azure/well-architected/service-guides/virtual-machines)
- **Azure Virtual Machine Scale Sets** — [virtual-machines](https://learn.microsoft.com/azure/well-architected/service-guides/virtual-machines)
- **Azure Disk Storage** — [azure-disk-storage](https://learn.microsoft.com/azure/well-architected/service-guides/azure-disk-storage)
- **Azure Monitor Application Insights** — [application-insights](https://learn.microsoft.com/azure/well-architected/service-guides/application-insights)
- **Azure Front Door** — [azure-front-door](https://learn.microsoft.com/azure/well-architected/service-guides/azure-front-door)
- **Azure Traffic Manager** — [azure-traffic-manager](https://learn.microsoft.com/azure/well-architected/service-guides/azure-traffic-manager)
- **Azure Virtual WAN** — [azure-virtual-wan](https://learn.microsoft.com/azure/well-architected/service-guides/azure-virtual-wan)
- **Azure ExpressRoute** — [azure-expressroute](https://learn.microsoft.com/azure/well-architected/service-guides/azure-expressroute)
- **Azure Files** — [azure-files](https://learn.microsoft.com/azure/well-architected/service-guides/azure-files)
- **Azure NetApp Files** — [azure-netapp-files](https://learn.microsoft.com/azure/well-architected/service-guides/azure-netapp-files)

## The enumeration — 214 items across 21 service sections

### Azure Kubernetes Service (WAF-SVC-AKS) — 14 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-kubernetes-service>. 11 automated, 3 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-AKS-01 | Clusters use the Standard or Premium tier, which carries the uptime SLA | Reliability | ✅ `tier` |
| WAF-SVC-AKS-02 | Every node pool is spread across availability zones | Reliability | ✅ `allPoolsZoned`, in zone regions |
| WAF-SVC-AKS-03 | Clusters authenticate users through Microsoft Entra ID | Security | ✅ `aadIntegrated` |
| WAF-SVC-AKS-04 | Local accounts are disabled so every access goes through Microsoft Entra ID | Security | ✅ `disableLocalAccounts` |
| WAF-SVC-AKS-05 | Kubernetes authorization uses Azure RBAC | Security | ✅ `azureRbac` |
| WAF-SVC-AKS-06 | Public clusters limit the API server to authorized IP ranges | Security | ✅ `privateCluster`, `authorizedIpRangeCount` |
| WAF-SVC-AKS-07 | Workloads use Microsoft Entra Workload ID | Security | ✅ `workloadIdentity` |
| WAF-SVC-AKS-08 | Microsoft Defender for Containers is enabled | Security | ✅ `defenderEnabled` |
| WAF-SVC-AKS-09 | A network policy secures traffic between pods | Security | ✅ `networkPolicyEnabled` |
| WAF-SVC-AKS-10 | Automatic cluster upgrades are enabled | Operational excellence | ✅ `upgradeChannel` |
| WAF-SVC-AKS-11 | The cluster autoscaler scales every node pool | Cost optimization | ✅ `allPoolsAutoscale` |
| WAF-SVC-AKS-12 | Clusters that need strong API segmentation are private, and egress passes through a firewall, NAT gateway or proxy | Security | ❌ Manual — evidence attached |
| WAF-SVC-AKS-13 | Azure Policy and deployment safeguards enforce pod and cluster standards | Security | ❌ Manual — no collected field |
| WAF-SVC-AKS-14 | Cluster state and application data are backed up, and maintenance is scheduled | Reliability | ❌ Manual — evidence attached |

### Azure App Service (Web Apps) (WAF-SVC-APP) — 17 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/app-service-web-apps>. 14 automated, 3 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-APP-01 | App Service plans use the Premium v3 tier or above | Reliability | ✅ `tier` |
| WAF-SVC-APP-02 | Plans on a zone-capable tier are zone redundant | Reliability | ✅ `zoneRedundant`, in zone regions |
| WAF-SVC-APP-03 | Plans run more than one instance | Reliability | ✅ `instanceCount` |
| WAF-SVC-APP-04 | Plans on a tier that supports it have an enabled autoscale setting | Performance efficiency | ✅ `appServicePlans` to enabled `autoscaleSettings` |
| WAF-SVC-APP-05 | Web apps have a managed identity | Security | ✅ `identityType` |
| WAF-SVC-APP-06 | Web apps accept HTTPS only | Security | ✅ `httpsOnly` |
| WAF-SVC-APP-07 | Web apps require TLS 1.2 or higher | Security | ✅ `minTls` |
| WAF-SVC-APP-08 | Web apps block public network access | Security | ✅ `publicNetworkAccess` |
| WAF-SVC-APP-09 | Web apps are integrated with a virtual network | Security | ✅ `vnetIntegrated` |
| WAF-SVC-APP-10 | Web apps use a custom domain | Security | ✅ `customDomainBound` |
| WAF-SVC-APP-11 | Microsoft Defender for App Service is enabled | Security | ✅ Defender plan `AppServices` |
| WAF-SVC-APP-12 | Web apps send diagnostic logs to a destination | Operational excellence | ✅ diagnostic-settings coverage of `microsoft.web/sites` |
| WAF-SVC-APP-13 | Health check, auto-heal and Always On are configured | Reliability | ✅ `webAppConfig` `healthCheckPathSet` and `alwaysOn`, web apps only (a function app has no Always On); auto-heal is not collected |
| WAF-SVC-APP-14 | Basic authentication, FTP and remote debugging are disabled, and secrets use Key Vault references | Security | ✅ `webAppBasicAuth` `ftpBasicAuthAllowed` and `scmBasicAuthAllowed`, `webAppConfig` `ftpsState` (AllAllowed is a finding) and `remoteDebuggingEnabled`; covers web and function apps, a policy that was not returned is not scored; Key Vault references are not collected |
| WAF-SVC-APP-15 | Built-in authentication or Microsoft Entra ID authentication protects the app, with restrictive CORS | Security | ❌ Manual — no collected field |
| WAF-SVC-APP-16 | Releases go through deployment slots and a pipeline | Operational excellence | ❌ Manual — no collected field |
| WAF-SVC-APP-17 | Lower environments use Free or Basic plans, and steady workloads use reservations | Cost optimization | ❌ Manual — evidence attached |

### Azure Functions (WAF-SVC-FUNC) — 7 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-functions>. 4 automated, 3 manual.

The Functions guide builds on the App Service guide; function apps are the web apps whose `kind` contains functionapp.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-FUNC-01 | Function apps have a managed identity | Security | ✅ `identityType` |
| WAF-SVC-FUNC-02 | Function apps accept HTTPS only | Security | ✅ `httpsOnly` |
| WAF-SVC-FUNC-03 | Function apps block public network access | Security | ✅ `publicNetworkAccess` |
| WAF-SVC-FUNC-04 | Function apps are integrated with a virtual network | Security | ✅ `vnetIntegrated` |
| WAF-SVC-FUNC-05 | Secrets come from Key Vault and the app requires Microsoft Entra ID authentication | Security | ❌ Manual — no collected field |
| WAF-SVC-FUNC-06 | Retries, Durable Functions and availability zones are used where the workload needs them | Reliability | ❌ Manual — evidence attached |
| WAF-SVC-FUNC-07 | Function apps send telemetry to Application Insights and deploy through CI/CD with slots | Operational excellence | ❌ Manual — evidence attached |

### Azure Container Apps (WAF-SVC-ACA) — 11 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-container-apps>. 6 automated, 5 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-ACA-01 | Environments are zone redundant | Reliability | ✅ `zoneRedundant`, in zone regions |
| WAF-SVC-ACA-02 | Apps with ingress keep at least three replicas | Reliability | ✅ `externalIngress`, `minReplicas` |
| WAF-SVC-ACA-03 | Apps accept HTTPS only | Security | ✅ `allowInsecure` |
| WAF-SVC-ACA-04 | Apps have a managed identity | Security | ✅ `identityType` |
| WAF-SVC-ACA-05 | Environments are injected into a virtual network | Security | ✅ `vnetIntegrated` |
| WAF-SVC-ACA-06 | Environments block public network access | Security | ✅ `internal`, `publicNetworkAccess` |
| WAF-SVC-ACA-07 | Apps that must not be public use internal ingress, and a WAF fronts the ones that are | Security | ❌ Manual — evidence attached |
| WAF-SVC-ACA-08 | Secrets use Key Vault, registry pulls use Microsoft Entra ID, and egress is controlled | Security | ❌ Manual — no collected field |
| WAF-SVC-ACA-09 | Health probes, resource limits and resiliency policies are configured | Reliability | ❌ Manual — no collected field |
| WAF-SVC-ACA-10 | Scale rules match the workload | Performance efficiency | ❌ Manual — no collected field |
| WAF-SVC-ACA-11 | Logs and traces go to Log Analytics, Application Insights or an OpenTelemetry agent | Operational excellence | ❌ Manual — no collected field |

### Azure API Management (WAF-SVC-APIM) — 12 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-api-management>. 8 automated, 4 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-APIM-01 | Premium instances are zone redundant | Reliability | ✅ `zoneCount` |
| WAF-SVC-APIM-02 | Premium instances run at least two units | Reliability | ✅ `capacity` |
| WAF-SVC-APIM-03 | Premium instances use a multiregion topology | Reliability | ✅ `additionalRegionCount` |
| WAF-SVC-APIM-04 | Instances on a tier that supports it have an enabled autoscale setting | Reliability | ✅ `apiManagement` to enabled `autoscaleSettings` |
| WAF-SVC-APIM-05 | The gateway is not open to the internet without network controls | Security | ✅ `publicNetworkAccess`, `virtualNetworkType` |
| WAF-SVC-APIM-06 | Instances have a managed identity | Security | ✅ `identityType` |
| WAF-SVC-APIM-07 | Microsoft Defender for APIs is enabled | Security | ✅ Defender plan `Api` |
| WAF-SVC-APIM-08 | Instances send resource logs to a destination | Operational excellence | ✅ diagnostic-settings coverage of `microsoft.apimanagement/service` |
| WAF-SVC-APIM-09 | The narrowest TLS versions, protocols and ciphers are set, and the developer portal and direct management API are off | Security | ❌ Manual — no collected field |
| WAF-SVC-APIM-10 | APIs authenticate with OAuth 2.0, secrets use Key Vault named values, and a WAF fronts internet-exposed gateways | Security | ❌ Manual — no collected field |
| WAF-SVC-APIM-11 | Backup, restore and a disaster recovery playbook exist, and unrelated APIs are isolated | Reliability | ❌ Manual — no collected field |
| WAF-SVC-APIM-12 | The tier is the least expensive that meets the workload, and lower environments use non-production tiers | Cost optimization | ❌ Manual — evidence attached |

### Azure Service Bus (WAF-SVC-SB) — 13 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-service-bus>. 9 automated, 4 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-SB-01 | Namespaces use the Premium tier | Reliability | ✅ `tier` |
| WAF-SVC-SB-02 | Namespaces are zone redundant in regions that have zones | Reliability | ✅ `zoneRedundant`, in zone regions |
| WAF-SVC-SB-03 | Premium namespaces replicate to a second region | Reliability | ✅ `geoReplicaCount` |
| WAF-SVC-SB-04 | Shared access key authentication is disabled | Security | ✅ `disableLocalAuth` |
| WAF-SVC-SB-05 | Namespaces require TLS 1.2 | Security | ✅ `minimumTlsVersion` |
| WAF-SVC-SB-06 | Premium namespaces block public network access | Security | ✅ `publicAccess` |
| WAF-SVC-SB-07 | Premium namespaces have a private endpoint | Security | ✅ `serviceBusNamespaces` to `privateEndpoints` |
| WAF-SVC-SB-08 | Premium namespaces encrypt with a customer-managed key | Security | ✅ `cmkKeySource` |
| WAF-SVC-SB-09 | Namespaces send security and operational logs to a destination | Operational excellence | ✅ diagnostic-settings coverage of `microsoft.servicebus/namespaces` |
| WAF-SVC-SB-10 | Geo-replication or geo-disaster recovery has a rehearsed regional recovery runbook | Reliability | ❌ Manual — no collected field |
| WAF-SVC-SB-11 | Consumers use PeekLock, duplicate detection and dead-lettering, and alerts watch queue depth and throttling | Reliability | ❌ Manual — evidence attached |
| WAF-SVC-SB-12 | Access uses least-privilege Azure RBAC, IP firewall rules, and Key Vault for any remaining keys | Security | ❌ Manual — no collected field |
| WAF-SVC-SB-13 | Premium autoscale, batching, prefetch and partitioning are tuned by load test | Performance efficiency | ❌ Manual — no collected field |

### Azure Event Grid (WAF-SVC-EG) — 10 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-event-grid>. 6 automated, 4 manual.

The guide index links the Event Grid guide as event-grid/reliability; the guide itself is service-guides/azure-event-grid.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-EG-01 | Topics and domains disable key-based authentication | Security | ✅ `disableLocalAuth` |
| WAF-SVC-EG-02 | Public access is disabled or limited by an IP allow list | Security | ✅ `publicNetworkAccess`, `inboundIpRuleCount` |
| WAF-SVC-EG-03 | Resources require TLS 1.2 or higher | Security | ✅ `minimumTlsVersion` |
| WAF-SVC-EG-04 | Resources have a managed identity for delivery | Security | ✅ `identityType` |
| WAF-SVC-EG-05 | Resources have a private endpoint | Security | ✅ `eventGrid` to `privateEndpoints` |
| WAF-SVC-EG-06 | Resources send diagnostic logs to a destination | Operational excellence | ✅ diagnostic-settings coverage of `microsoft.eventgrid/*` |
| WAF-SVC-EG-07 | Retries, dead-lettering and cross-geo failover are configured | Reliability | ❌ Manual — no collected field |
| WAF-SVC-EG-08 | Delivery success, dead-letter volume and latency are alerted on | Reliability | ❌ Manual — evidence attached |
| WAF-SVC-EG-09 | Management is least-privilege RBAC with Conditional Access, and secrets are in Key Vault | Security | ❌ Manual — no collected field |
| WAF-SVC-EG-10 | The Event Grid tier and event filters match usage | Cost optimization | ❌ Manual — evidence attached |

### Azure Firewall (WAF-SVC-FW) — 11 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-firewall>. 6 automated, 5 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-FW-01 | Firewalls are deployed across multiple availability zones | Reliability | ✅ `zoneCount` |
| WAF-SVC-FW-02 | Firewalls use a firewall policy, not classic rules | Security | ✅ `hasPolicy` |
| WAF-SVC-FW-03 | Firewall policies run threat intelligence in Alert and deny mode | Security | ✅ `firewallPolicies.threatIntelMode` |
| WAF-SVC-FW-04 | Firewalls without a policy run threat intelligence in Alert and deny mode | Security | ✅ `threatIntelMode` |
| WAF-SVC-FW-05 | Firewalls protecting sensitive workloads use the Premium tier | Security | ✅ `tier` |
| WAF-SVC-FW-06 | IDPS, TLS inspection and DNS proxy are enabled on the policy | Security | ❌ Manual — evidence attached |
| WAF-SVC-FW-07 | Traffic is forced through the firewall by user-defined routes or routing intent | Security | ❌ Manual — evidence attached |
| WAF-SVC-FW-08 | Resource Health, throughput, SNAT and health-state alerts exist | Operational excellence | ❌ Manual — evidence attached |
| WAF-SVC-FW-09 | Customer-controlled maintenance is configured | Operational excellence | ❌ Manual — evidence attached |
| WAF-SVC-FW-10 | Policy analytics, IP groups, enough public IPs for SNAT and prescaling are in use | Performance efficiency | ❌ Manual — no collected field |
| WAF-SVC-FW-11 | Firewalls send logs to a destination | Operational excellence | ✅ diagnostic-settings coverage of `microsoft.network/azurefirewalls` |

### Azure Application Gateway (WAF-SVC-AGW) — 13 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-application-gateway>. 9 automated, 4 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-AGW-01 | Gateways use the v2 SKU | Reliability | ✅ `tier` |
| WAF-SVC-AGW-02 | v2 gateways are zone aware | Reliability | ✅ `zoneCount`, in zone regions |
| WAF-SVC-AGW-03 | Gateways define custom health probes | Reliability | ✅ `probeCount` |
| WAF-SVC-AGW-04 | Web application firewall is enabled | Security | ✅ `wafEnabled` |
| WAF-SVC-AGW-05 | WAF policies on Application Gateway run in Prevention mode | Security | ✅ `wafPolicies.mode` |
| WAF-SVC-AGW-06 | Gateways set a current TLS policy | Security | ✅ `sslPolicyType`, `sslPolicyName`, `sslMinProtocol` |
| WAF-SVC-AGW-07 | v2 gateways autoscale | Performance efficiency | ✅ `autoscaleMax` |
| WAF-SVC-AGW-08 | Autoscale maximum is set to the maximum possible (125) | Performance efficiency | ✅ `autoscaleMax` |
| WAF-SVC-AGW-09 | Gateways and WAF send diagnostic logs to a destination | Operational excellence | ✅ diagnostic-settings coverage of `microsoft.network/applicationgateways` |
| WAF-SVC-AGW-10 | Certificates are in Key Vault, end-to-end TLS is used, and the WAF is tuned with rate limiting | Security | ❌ Manual — no collected field |
| WAF-SVC-AGW-11 | No user-defined route sits on the gateway subnet, and idle timeout fits the application | Reliability | ❌ Manual — evidence attached |
| WAF-SVC-AGW-12 | Alerts cover capacity units, unhealthy hosts and 4xx/5xx responses | Operational excellence | ❌ Manual — evidence attached |
| WAF-SVC-AGW-13 | Minimum instance count and a /24 subnet are sized from observed load | Performance efficiency | ❌ Manual — no collected field |

### Azure Load Balancer (WAF-SVC-LB) — 9 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-load-balancer>. 5 automated, 4 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-LB-01 | Load balancers use the Standard SKU | Reliability | ✅ `sku` |
| WAF-SVC-LB-02 | Load balancers have at least one load-balancing rule | Reliability | ✅ `ruleCount` |
| WAF-SVC-LB-03 | Load balancers define health probes | Reliability | ✅ `probeCount` |
| WAF-SVC-LB-04 | Internal load balancer frontends are zone redundant | Reliability | ✅ `minFrontendZoneCount` |
| WAF-SVC-LB-05 | Public load balancers are protected by DDoS Protection and back ends are not reachable directly from the internet | Security | ❌ Manual — evidence attached |
| WAF-SVC-LB-06 | Load balancers send resource logs to a destination | Operational excellence | ✅ diagnostic-settings coverage of `microsoft.network/loadbalancers` |
| WAF-SVC-LB-07 | Multidimensional metric alerts, Azure Monitor Insights and Admin state are used | Operational excellence | ❌ Manual — evidence attached |
| WAF-SVC-LB-08 | The global tier, session persistence and probe-down behavior fit the workload | Performance efficiency | ❌ Manual — no collected field |
| WAF-SVC-LB-09 | Rules are consolidated and unused load balancers are removed | Cost optimization | ❌ Manual — evidence attached |

### Azure Virtual Network (WAF-SVC-VNET) — 13 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/virtual-network>. 10 automated, 3 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-VNET-01 | Public IP addresses use the Standard SKU | Reliability | ✅ `skuName` |
| WAF-SVC-VNET-02 | Standard public IP addresses are zone redundant in regions that have zones | Reliability | ✅ `zoneCount` |
| WAF-SVC-VNET-03 | No subnet is close to running out of addresses | Reliability | ✅ `ipUtilizationPct` |
| WAF-SVC-VNET-04 | Virtual network encryption is enabled | Security | ✅ `encryptionEnabled` |
| WAF-SVC-VNET-05 | Azure DDoS Protection covers virtual networks | Security | ✅ `ddosEnabled` |
| WAF-SVC-VNET-06 | No network security group rule allows inbound traffic from any source | Security | ✅ `nsgPublicInbound` |
| WAF-SVC-VNET-07 | Private endpoints are used for Azure services | Security | ✅ `privateEndpoints` |
| WAF-SVC-VNET-08 | Every virtual network has an enabled flow log | Operational excellence | ✅ `virtualNetworks` to enabled `flowLogs` |
| WAF-SVC-VNET-09 | Flow logs use Traffic Analytics | Operational excellence | ✅ `trafficAnalytics` |
| WAF-SVC-VNET-10 | Azure Virtual Network Manager manages connectivity centrally | Operational excellence | ✅ `networkManagers` |
| WAF-SVC-VNET-11 | Segments are guarded by NSGs and application security groups, with Virtual Network Verifier used before production | Security | ❌ Manual — no collected field |
| WAF-SVC-VNET-12 | Unused public IP addresses are removed | Cost optimization | ❌ Manual — evidence attached |
| WAF-SVC-VNET-13 | Connection Monitor measures latency and loss between key endpoints | Performance efficiency | ❌ Manual — evidence attached |

### Azure Virtual Machines (WAF-SVC-VM) — 13 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/virtual-machines>. 9 automated, 4 manual.

The guide covers Virtual Machines and Virtual Machine Scale Sets; scale-set items carry the WAF-SVC-VMSS prefix.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-VM-01 | Virtual machines in zone regions are deployed in an availability zone | Reliability | ✅ `zoneEligible`, `zoneRedundant` |
| WAF-SVC-VM-02 | Virtual machines have a backup protected item | Reliability | ✅ `virtualMachines` to `backupProtectedItems` |
| WAF-SVC-VM-03 | Virtual machines use Trusted Launch or Confidential VMs | Security | ✅ `securityType` |
| WAF-SVC-VM-04 | Virtual machines use encryption at host | Security | ✅ `encryptionAtHost` |
| WAF-SVC-VM-05 | Virtual machines have a managed identity | Security | ✅ `identityType` |
| WAF-SVC-VM-06 | Microsoft Defender for Servers is enabled | Security | ✅ Defender plan `VirtualMachines` |
| WAF-SVC-VM-07 | Operating system updates are applied automatically | Operational excellence | ✅ `patchMode` |
| WAF-SVC-VM-08 | Boot diagnostics are enabled | Operational excellence | ✅ `bootDiagnostics` |
| WAF-SVC-VM-09 | Windows Server machines claim Azure Hybrid Benefit | Cost optimization | ✅ `osType`, `licenseType` |
| WAF-SVC-VM-10 | No machine has a public IP address bound directly, and every network interface has an NSG | Security | ❌ Manual — evidence attached |
| WAF-SVC-VM-11 | Always-on machines are locked, health endpoints are emitted, and capacity reservations cover critical workloads | Reliability | ❌ Manual — evidence attached |
| WAF-SVC-VM-12 | The Azure Monitor agent, VM insights and data collection rules cover the machines | Operational excellence | ❌ Manual — evidence attached |
| WAF-SVC-VM-13 | Sizes, accelerated networking and proximity placement fit the workload | Performance efficiency | ❌ Manual — no collected field |

### Azure Virtual Machine Scale Sets (WAF-SVC-VMSS) — 7 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/virtual-machines>. 6 automated, 1 manual.

Scale sets in AKS node resource groups (MC_*) are skipped; the AKS guide governs them.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-VMSS-01 | Scale sets use Flexible orchestration | Reliability | ✅ `orchestrationMode` |
| WAF-SVC-VMSS-02 | Scale sets repair unhealthy instances automatically | Reliability | ✅ `automaticRepairs` |
| WAF-SVC-VMSS-03 | Scale sets span at least two availability zones | Reliability | ✅ `zoneCount`, in zone regions |
| WAF-SVC-VMSS-04 | Scale sets use encryption at host | Security | ✅ `encryptionAtHost` |
| WAF-SVC-VMSS-05 | Uniform scale sets do not use a manual upgrade policy | Operational excellence | ✅ `upgradeMode` |
| WAF-SVC-VMSS-06 | Scale sets have an enabled autoscale setting | Performance efficiency | ✅ `virtualMachineScaleSets` to enabled `autoscaleSettings` |
| WAF-SVC-VMSS-07 | Standby pools, overprovisioning, MaxSurge and zone balancing are used where they fit | Reliability | ❌ Manual — evidence attached |

### Azure Disk Storage (WAF-SVC-DISK) — 9 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-disk-storage>. 5 automated, 4 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-DISK-01 | Attached LRS disks in zone regions are zonal | Reliability | ✅ `zoneCount`, `sku` |
| WAF-SVC-DISK-02 | Attached disks are not Standard HDD | Reliability | ✅ `sku` |
| WAF-SVC-DISK-03 | Virtual machines use managed disks | Reliability | ✅ `unmanagedOsDisk` |
| WAF-SVC-DISK-04 | Disks block public network access | Security | ✅ `publicNetworkAccess` |
| WAF-SVC-DISK-05 | Disks use a customer-managed key where policy requires it | Security | ✅ `encryptionType` |
| WAF-SVC-DISK-06 | Resource locks protect disks, and RBAC and short-lived SAS limit access | Security | ❌ Manual — evidence attached |
| WAF-SVC-DISK-07 | Disks are protected by Azure Backup, Site Recovery or restore points | Reliability | ❌ Manual — evidence attached |
| WAF-SVC-DISK-08 | Disk type and size match performance needs, and throttling is monitored | Performance efficiency | ❌ Manual — no collected field |
| WAF-SVC-DISK-09 | Disk types are chosen on cost, and reserved capacity covers Premium SSD | Cost optimization | ❌ Manual — evidence attached |

### Azure Monitor Application Insights (WAF-SVC-APPI) — 7 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/application-insights>. 3 automated, 4 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-APPI-01 | Components are workspace-based | Reliability | ✅ `workspaceBased` |
| WAF-SVC-APPI-02 | Components require Microsoft Entra authentication for ingestion | Security | ✅ `disableLocalAuth` |
| WAF-SVC-APPI-03 | Components block public ingestion and query | Security | ✅ `publicNetworkAccessForIngestion`, `publicNetworkAccessForQuery` |
| WAF-SVC-APPI-04 | One component per workload per environment, in the same region as its workspace | Reliability | ❌ Manual — evidence attached |
| WAF-SVC-APPI-05 | Microsoft Entra authentication is used for the query API, and personal data is not collected | Security | ❌ Manual — no collected field |
| WAF-SVC-APPI-06 | A daily cap, sampling and telemetry filters control volume | Cost optimization | ❌ Manual — no collected field |
| WAF-SVC-APPI-07 | Auto-instrumentation or the Azure Monitor OpenTelemetry distro is used with connection strings | Operational excellence | ❌ Manual — no collected field |

### Azure Front Door (WAF-SVC-AFD) — 7 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-front-door>. 3 automated, 4 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-AFD-01 | Front Door profiles use the Premium tier | Security | ✅ `sku` |
| WAF-SVC-AFD-02 | A Front Door WAF policy runs in Prevention mode | Security | ✅ `wafPolicies.mode` |
| WAF-SVC-AFD-03 | Profiles send logs and metrics to a destination | Operational excellence | ✅ diagnostic-settings coverage of `microsoft.cdn/profiles` |
| WAF-SVC-AFD-04 | Origin groups have redundant origins with health probes, and request timeouts and session affinity are deliberate | Reliability | ❌ Manual — no collected field |
| WAF-SVC-AFD-05 | Origins are reached over Private Link, TLS 1.2 is the minimum, and managed certificates are used | Security | ❌ Manual — no collected field |
| WAF-SVC-AFD-06 | Caching and compression are enabled for cacheable content | Performance efficiency | ❌ Manual — no collected field |
| WAF-SVC-AFD-07 | Alerts and built-in analytics reports are reviewed | Operational excellence | ❌ Manual — evidence attached |

### Azure Traffic Manager (WAF-SVC-TM) — 6 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-traffic-manager>. 3 automated, 3 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-TM-01 | Profiles have more than one endpoint | Reliability | ✅ `endpointCount` |
| WAF-SVC-TM-02 | Profile health probes report the profile online | Reliability | ✅ `monitorStatus` |
| WAF-SVC-TM-03 | Profiles send diagnostic logs to a destination | Operational excellence | ✅ diagnostic-settings coverage of `microsoft.network/trafficmanagerprofiles` |
| WAF-SVC-TM-04 | DNS TTL is below 60 seconds, AlwaysServe is off, and probe interval and tolerated failures are set deliberately | Reliability | ❌ Manual — evidence attached |
| WAF-SVC-TM-05 | Application gateways front HTTP endpoints, and apex domains use alias records | Reliability | ❌ Manual — no collected field |
| WAF-SVC-TM-06 | Routing method fits the deployment, using performance routing for multi-region endpoints | Performance efficiency | ❌ Manual — evidence attached |

### Azure Virtual WAN (WAF-SVC-VWAN) — 9 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-virtual-wan>. 3 automated, 6 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-VWAN-01 | Virtual WANs use the Standard SKU | Reliability | ✅ `wanType` |
| WAF-SVC-VWAN-02 | A secured virtual hub runs Azure Firewall | Security | ✅ `azureFirewalls` with sku AZFW_Hub |
| WAF-SVC-VWAN-03 | Hub gateways send diagnostic logs to a destination | Operational excellence | ✅ diagnostic-settings coverage of hub gateway types |
| WAF-SVC-VWAN-04 | Virtual hubs exist in at least two regions, with zone-redundant, active-active gateways | Reliability | ❌ Manual — evidence attached |
| WAF-SVC-VWAN-05 | Site-to-site VPN backs up ExpressRoute, and routing preference is set deliberately | Reliability | ❌ Manual — no collected field |
| WAF-SVC-VWAN-06 | Spokes use custom route tables, NSGs and private endpoints, and point-to-site uses Microsoft Entra ID with Conditional Access | Security | ❌ Manual — no collected field |
| WAF-SVC-VWAN-07 | Site-to-site connections use GCMAES256 IPsec policies | Security | ❌ Manual — evidence attached |
| WAF-SVC-VWAN-08 | Routing infrastructure units and gateway scale units are sized from throughput | Performance efficiency | ❌ Manual — no collected field |
| WAF-SVC-VWAN-09 | Alerts, Insights, Connection Monitor and maintenance windows are configured | Operational excellence | ❌ Manual — evidence attached |

### Azure ExpressRoute (WAF-SVC-ER) — 9 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-expressroute>. 4 automated, 5 manual.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-ER-01 | More than one ExpressRoute circuit exists | Reliability | ✅ `expressRouteCircuits` |
| WAF-SVC-ER-02 | ExpressRoute gateways are zone redundant | Reliability | ✅ `vpnGateways` sku |
| WAF-SVC-ER-03 | A site-to-site VPN gateway can back up ExpressRoute | Reliability | ✅ `vpnGateways` of type Vpn |
| WAF-SVC-ER-04 | No circuit is left unprovisioned | Cost optimization | ✅ `serviceProviderProvisioningState` |
| WAF-SVC-ER-05 | Both connections of each circuit run active-active, with site resiliency across peering locations | Reliability | ❌ Manual — evidence attached |
| WAF-SVC-ER-06 | The circuit SKU fits geographic reach, and Global Reach joins on-premises sites | Reliability | ❌ Manual — evidence attached |
| WAF-SVC-ER-07 | MACsec, IPsec and MD5 protect traffic where required | Security | ❌ Manual — no collected field |
| WAF-SVC-ER-08 | Circuit, port and gateway metrics have alerts, and Service Health and Connection Monitor are configured | Operational excellence | ❌ Manual — evidence attached |
| WAF-SVC-ER-09 | Circuit bandwidth, gateway SKU, FastPath and scalable gateways match throughput needs | Performance efficiency | ❌ Manual — no collected field |

### Azure Files (WAF-SVC-FILES) — 9 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-files>. 6 automated, 3 manual.

Scout cannot see which storage accounts hold file shares, so the account-level items apply to every account that can (StorageV2, FileStorage, Storage).

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-FILES-01 | Storage accounts use zone- or geo-redundant storage | Reliability | ✅ `sku` |
| WAF-SVC-FILES-02 | Storage accounts require TLS 1.2 or higher | Security | ✅ `minTls` |
| WAF-SVC-FILES-03 | Secure transfer is required | Security | ✅ `httpsOnly` |
| WAF-SVC-FILES-04 | Public network access is disabled or limited by a deny-by-default firewall | Security | ✅ `publicNetworkAccess`, `networkDefaultDeny` |
| WAF-SVC-FILES-05 | Soft delete, snapshots and Azure Backup protect shares | Reliability | ✅ `fileServiceProperties` `shareDeleteRetentionEnabled`; snapshots and backup are not read |
| WAF-SVC-FILES-06 | Identity-based authentication uses Kerberos with AES-256, SMB 3.1.1 with AES-256-GCM, and keys are in Key Vault | Security | ✅ `fileServiceProperties` `smbVersions` and `smbChannelEncryption` (null allows every version and algorithm, which is a finding); Kerberos ticket encryption and key custody are not read |
| WAF-SVC-FILES-07 | A Resource Manager lock protects the storage account | Security | ❌ Manual — evidence attached |
| WAF-SVC-FILES-08 | SMB Multichannel, metadata caching and nconnect are used for SSD shares, and throttling is monitored | Performance efficiency | ❌ Manual — no collected field |
| WAF-SVC-FILES-09 | Access tiers, provisioned capacity and reservations match usage | Cost optimization | ❌ Manual — evidence attached |

### Azure NetApp Files (WAF-SVC-ANF) — 8 items

Guide: <https://learn.microsoft.com/azure/well-architected/service-guides/azure-netapp-files>. 0 automated, 8 manual.

The assessment collects volume name, state and quota only, so every item here is a question; volumes are attached as evidence.

| # | Item | Pillar | Scout |
|---|---|---|---|
| WAF-SVC-ANF-01 | Snapshots, backup and cross-region or cross-zone replication protect volumes | Reliability | ❌ Manual — evidence attached |
| WAF-SVC-ANF-02 | The delegated subnet is sized for growth and uses standard network features | Reliability | ❌ Manual — evidence attached |
| WAF-SVC-ANF-03 | Network access is limited by NSGs, export policies and protocol-level access controls | Security | ❌ Manual — evidence attached |
| WAF-SVC-ANF-04 | Data is encrypted in transit and at rest, with customer-managed or double encryption where required | Security | ❌ Manual — evidence attached |
| WAF-SVC-ANF-05 | File access logs feed monitoring, and RBAC and Azure Policy restrict insecure volumes | Security | ❌ Manual — evidence attached |
| WAF-SVC-ANF-06 | Service level, volume size and QoS match performance needs | Performance efficiency | ❌ Manual — evidence attached |
| WAF-SVC-ANF-07 | Cool access, reservations, and consolidated capacity pools lower the cost | Cost optimization | ❌ Manual — evidence attached |
| WAF-SVC-ANF-08 | Volume performance and health are monitored, and deployments are automated | Operational excellence | ❌ Manual — evidence attached |

## Summary

| Service guide | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Azure Kubernetes Service | 14 | 11 | 3 |
| Azure App Service (Web Apps) | 17 | 14 | 3 |
| Azure Functions | 7 | 4 | 3 |
| Azure Container Apps | 11 | 6 | 5 |
| Azure API Management | 12 | 8 | 4 |
| Azure Service Bus | 13 | 9 | 4 |
| Azure Event Grid | 10 | 6 | 4 |
| Azure Firewall | 11 | 6 | 5 |
| Azure Application Gateway | 13 | 9 | 4 |
| Azure Load Balancer | 9 | 5 | 4 |
| Azure Virtual Network | 13 | 10 | 3 |
| Azure Virtual Machines | 13 | 9 | 4 |
| Azure Virtual Machine Scale Sets | 7 | 6 | 1 |
| Azure Disk Storage | 9 | 5 | 4 |
| Azure Monitor Application Insights | 7 | 3 | 4 |
| Azure Front Door | 7 | 3 | 4 |
| Azure Traffic Manager | 6 | 3 | 3 |
| Azure Virtual WAN | 9 | 3 | 6 |
| Azure ExpressRoute | 9 | 4 | 5 |
| Azure Files | 9 | 6 | 3 |
| Azure NetApp Files | 8 | 0 | 8 |
| **Total** | **214** | **130** | **84** |

## What these rules read

The rules read the fields the assessment collection gained in AB#9300 phase 4, such as AKS
`disableLocalAccounts`, `upgradeChannel` and `authorizedIpRangeCount`; web app and Container Apps
exposure fields; API Management `zoneCount` and `capacity`; Service Bus, Event Grid and storage TLS
and local-authentication settings; Firewall, Application Gateway and Load Balancer zone, tier and
probe fields; virtual network `encryptionEnabled`, `publicIPAddresses` and `flowLogs`; and virtual
machine, scale set and disk security fields. Only a boolean or a count is collected for anything
sensitive: no key, certificate, secret value, IP address list or workspace id is read.

Four items read the per-resource ARM settings added in AB#9300 phase 4, batch 2, each from a dataset with a
sibling `<name>Measured` flag: App Service configuration (`webAppConfig`) and basic-authentication policies
(`webAppBasicAuth`) for WAF-SVC-APP-13 and APP-14, and the Azure Files service properties
(`fileServiceProperties`) for WAF-SVC-FILES-05 and FILES-06. The rule is gated on that flag, so a run that never
read the setting reports the item Not assessed rather than passed. A site, account or policy whose read failed has
no row and is not scored. Only a boolean, a count or a protocol string is collected: no app setting, connection
string or credential is read.

Virtual network flow logs are matched to virtual networks by lower-cased resource id. A flow log
whose target is a subnet or a network interface is not matched, and NSG flow logs (which Microsoft
is retiring) are not counted as virtual network flow logs.

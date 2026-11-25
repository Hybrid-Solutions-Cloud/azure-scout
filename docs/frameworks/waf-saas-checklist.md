# WAF -- enumerated source for the Azure Well-Architected SaaS workload assessment

**Enumerated 2026-11-25. Verification method and limits are stated below -- read them before quoting
any coverage number from this page.**

Scout's `waf.saas.yaml` scores the review in Microsoft's
[Azure Well-Architected SaaS workload](https://learn.microsoft.com/en-us/assessments/d349c8c3-fe9c-4829-afdd-a5228e72a570/)
assessment, which independent software vendors use to check a SaaS workload against the Well-Architected
Framework. `src/assess/rules/waf.saas.yaml` is written against this page only, and every rule cites an item
number from the tables below. Most items are organisational, so they are **manual** questions answered with
`-AssessmentAnswers`; a few are **automated** from collected Azure data.

## Source

| Field | Value |
|---|---|
| Assessment | [Azure Well-Architected SaaS workload](https://learn.microsoft.com/en-us/assessments/d349c8c3-fe9c-4829-afdd-a5228e72a570/) (question text not published) |
| Framework version | Azure Well-Architected SaaS workload guidance on Microsoft Learn, current as of the extraction date (no published version number) |
| Extraction date | 2026-11-25 |
| Verification method | Each source page below was fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. Every property an automated item reads was checked against the collect.json contract in `src/collect/Invoke-Collect.ps1`. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The assessment's questions are not published. The items below are
**Scout-derived**: Scout's reading of the design considerations and design recommendations in each SaaS
design-area article, restated as questions. The `SAAS-*` IDs are Scout's own. A Scout score is a measure of how
many of Scout's items are met; it is not the score the Microsoft assessment would give.

Sources:

- [ASM] [Assessment review tool for SaaS workloads on Azure](https://learn.microsoft.com/azure/well-architected/saas/assessment)
- [BCM] [Billing and cost management for SaaS workloads](https://learn.microsoft.com/azure/well-architected/saas/billing-cost-management)
- [GOV] [Governance for SaaS workloads](https://learn.microsoft.com/azure/well-architected/saas/governance)
- [RO] [Resource organization for SaaS workloads](https://learn.microsoft.com/azure/well-architected/saas/resource-organization)
- [IAM] [Identity and access management for SaaS workloads](https://learn.microsoft.com/azure/well-architected/saas/identity-access)
- [CMP] [Compute for SaaS workloads](https://learn.microsoft.com/azure/well-architected/saas/compute)
- [NET] [Networking for SaaS workloads](https://learn.microsoft.com/azure/well-architected/saas/networking)
- [DAT] [Data for SaaS workloads](https://learn.microsoft.com/azure/well-architected/saas/data)
- [DEV] [DevOps practices for SaaS workloads](https://learn.microsoft.com/azure/well-architected/saas/devops)
- [INC] [Incident management for SaaS workloads](https://learn.microsoft.com/azure/well-architected/saas/incident-management)
- [AIS] [Build an AI Strategy for your SaaS Business](https://learn.microsoft.com/azure/well-architected/saas/ai-strategy)

Automated items are **gated**: they run only when the resources they judge exist, so an estate without
them reports those items Not assessed rather than passed or failed. Manual items are answered with
`-AssessmentAnswers` (see [Questionnaire Answers](../assessment/questionnaire-answers.md)); where collected
Azure data bears on the question it is attached to the item as evidence.

## The enumeration -- 108 items across 10 design areas

### Billing and cost management (BC) -- 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| SAAS-BC-01 | Billing meters are meaningful to customers | Manual | BCM |
| SAAS-BC-02 | Billing tiers and SKUs are defined systematically, not per customer | Manual | BCM |
| SAAS-BC-03 | Billing is aligned with cost of goods sold | Manual | BCM |
| SAAS-BC-04 | A cost model covers marginal cost per customer and scale points | Manual | BCM |
| SAAS-BC-05 | Budgets guard against overspend | Automated -- `governance.budgets` | BCM |
| SAAS-BC-06 | Cost is attributable to customers through tags or customer-specific resource groups | Manual -- `tags` attached as evidence | BCM |
| SAAS-BC-07 | Azure billing constructs are used to lower cost of goods sold | Manual -- `finops.reservations` attached as evidence | BCM |
| SAAS-BC-08 | Unused resources are removed and utilisation is reviewed with Azure Advisor | Manual -- `costCleanup.orphanedDisks` attached as evidence | BCM |
| SAAS-BC-09 | Service quotas and limits are understood before scale points are reached | Manual | BCM, RO |
| SAAS-BC-10 | Azure Marketplace publishing has been considered | Manual | BCM, RO |

### Governance and compliance (GV) -- 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| SAAS-GV-01 | A naming convention and tagging strategy identify workload, environment and customer | Manual -- `tags` attached as evidence | GOV |
| SAAS-GV-02 | Azure Policy assignments enforce standards | Automated -- `governance.policyAssignments` | GOV |
| SAAS-GV-03 | Resource locks protect critical resources | Automated -- `governance.resourceLocks` | GOV |
| SAAS-GV-04 | Defender for Cloud assesses compliance against a security baseline (Defender CSPM) | Automated -- `security.defenderPlans` | GOV |
| SAAS-GV-05 | Access is least privilege, with privileged assignments and subscription owners limited | Manual | GOV |
| SAAS-GV-06 | Roles are assigned to groups rather than to individual users | Manual -- `governance.roleAssignments` attached as evidence | GOV |
| SAAS-GV-07 | A security baseline is adopted early in the design | Manual | GOV |
| SAAS-GV-08 | The Microsoft Entra tenant strategy is deliberate | Manual | GOV |
| SAAS-GV-09 | Customer compliance obligations are identified and evidenced | Manual | GOV, NET |
| SAAS-GV-10 | Cost Management and cost alerts are enabled | Manual -- `finops.anomalies` attached as evidence | GOV, BCM |

### Resource organization (RO) -- 7 items

| # | Item | Scout | Source |
|---|---|---|---|
| SAAS-RO-01 | Regions are chosen for availability zones, service availability and data residency | Manual | RO |
| SAAS-RO-02 | The number of regions is the minimum that meets requirements | Manual | RO |
| SAAS-RO-03 | The split between shared and per-customer resources is decided and documented | Manual | RO |
| SAAS-RO-04 | Pre-production does not use shared production resources | Manual | RO |
| SAAS-RO-05 | The Deployment Stamps pattern is considered for scale and isolation | Manual | RO, CMP |
| SAAS-RO-06 | Resource lifetimes and lifecycles are defined | Manual -- `tags` attached as evidence | RO |
| SAAS-RO-07 | The landing zone follows ISV guidance | Manual | RO |

### Identity and access management (ID) -- 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| SAAS-ID-01 | The tenancy and deployment model drive the identity design | Manual | IAM |
| SAAS-ID-02 | Each user has one account, with access granted per tenant | Manual | IAM |
| SAAS-ID-03 | Identity requirements and a provider capability matrix are documented | Manual | IAM |
| SAAS-ID-04 | An identity-as-a-service provider is used, not a self-built one | Manual | IAM |
| SAAS-ID-05 | Federated sign-in is planned, with onboarding automated and priced | Manual | IAM |
| SAAS-ID-06 | Cross-tenant data access is blocked unless explicitly permitted | Manual | IAM |
| SAAS-ID-07 | The authorization model and the store for authorization data are chosen deliberately | Manual | IAM |
| SAAS-ID-08 | Customers manage permissions for their own users | Manual | IAM |
| SAAS-ID-09 | Workloads authenticate with managed identities, not stored credentials | Manual -- `domains.identity.managedIdentities` attached as evidence | IAM, DAT |
| SAAS-ID-10 | Data residency for identity data is planned | Manual | IAM |

### Compute (CP) -- 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| SAAS-CP-01 | The compute platform fits requirements and starts with the least complex option the team knows | Manual | CMP |
| SAAS-CP-02 | Compute needs are modelled and load tested | Manual | CMP |
| SAAS-CP-03 | Tenant isolation is enforced in the compute platform and in the application | Manual | CMP |
| SAAS-CP-04 | Resource consumption is monitored per customer to catch noisy neighbours | Manual | CMP |
| SAAS-CP-05 | Autoscale settings are enabled | Automated -- `monitor.autoscaleSettings` | CMP |
| SAAS-CP-06 | Workloads scale horizontally and are stateless where possible | Manual | CMP |
| SAAS-CP-07 | A scaling threshold for deploying a new stamp is defined | Manual | CMP |
| SAAS-CP-08 | Virtual machines are deployed across availability zones where the region has them | Automated -- `compute.virtualMachines` | CMP |
| SAAS-CP-09 | AKS node pools span availability zones | Automated -- `domains.containers.aksClusters` | CMP |
| SAAS-CP-10 | Reliability targets are defined and failure modes are tested | Manual | CMP |

### Networking (NW) -- 10 items

| # | Item | Scout | Source |
|---|---|---|---|
| SAAS-NW-01 | The network topology matches the tenancy model | Manual | NET |
| SAAS-NW-02 | A catalogue of internet-exposed endpoints exists, with protection decided for each | Manual -- `networking.nsgPublicInbound` attached as evidence | NET |
| SAAS-NW-03 | Web front ends sit behind a reverse proxy with a web application firewall | Automated -- `networking.applicationGateways` | NET |
| SAAS-NW-04 | Internet-facing endpoints are protected against DDoS attacks | Manual -- `security.ddosProtectionPlans` attached as evidence | NET |
| SAAS-NW-05 | Storage accounts deny network access by default | Automated -- `domains.storage.storageAccounts` | NET, DAT |
| SAAS-NW-06 | Internal traffic uses private connectivity | Manual -- `networking.privateEndpoints` attached as evidence | NET |
| SAAS-NW-07 | Outbound traffic is controlled and SNAT capacity is planned | Manual -- `networking.natGateways` attached as evidence | NET |
| SAAS-NW-08 | Cross-network connectivity prefers private paths and IP ranges are planned | Manual | NET |
| SAAS-NW-09 | Customer-hosted deployments use Azure Managed Applications | Manual -- `management.managedApplications` attached as evidence | NET, DEV |
| SAAS-NW-10 | Public access is disabled by default on Azure resources | Manual -- `domains.storage.storageAccounts` attached as evidence | NET |

### Data (DT) -- 14 items

| # | Item | Scout | Source |
|---|---|---|---|
| SAAS-DT-01 | Transactional and analytical data stores are separate | Manual | DAT |
| SAAS-DT-02 | The number of data store types is minimised and managed services are preferred | Manual | DAT |
| SAAS-DT-03 | Database segmentation per customer is decided | Manual | DAT |
| SAAS-DT-04 | Data stores are deployed in the same region as the application | Manual | DAT |
| SAAS-DT-05 | Customer-defined data uses a standard design, not per-customer schema changes | Manual | DAT |
| SAAS-DT-06 | Capacity is modelled per customer size | Manual | DAT |
| SAAS-DT-07 | Reliability targets for data are quantified and zone-redundant stores are used | Manual -- `domains.databases.sqlDatabases` attached as evidence | DAT |
| SAAS-DT-08 | Backups are kept in a geo-redundant form and recovery is tested | Manual | DAT |
| SAAS-DT-09 | SQL servers have public network access disabled | Automated -- `domains.databases.sqlServers` | DAT |
| SAAS-DT-10 | Cosmos DB accounts have public network access disabled | Automated -- `domains.databases.cosmosDbAccounts` | DAT |
| SAAS-DT-11 | Cosmos DB accounts do not rely on account keys | Automated -- `domains.databases.cosmosDbAccounts` | DAT |
| SAAS-DT-12 | A data retention strategy is planned and enforced | Manual | DAT |
| SAAS-DT-13 | Requests on shared data stores are scoped to a single tenant | Manual | DAT |
| SAAS-DT-14 | Customers do not get direct access to production data stores | Manual | DAT |

### Deployment (DevOps) practices (DO) -- 12 items

| # | Item | Scout | Source |
|---|---|---|---|
| SAAS-DO-01 | Each customer lifecycle event is documented and automated where practical | Manual | DEV |
| SAAS-DO-02 | Infrastructure is deployed as code | Manual -- `management.deployments` attached as evidence | DEV |
| SAAS-DO-03 | Core infrastructure is separated from customer-level infrastructure | Manual | DEV |
| SAAS-DO-04 | Customers are mapped to the infrastructure that serves them | Manual -- `tags` attached as evidence | DEV |
| SAAS-DO-05 | Updates roll out progressively using safe deployment practices | Manual | DEV |
| SAAS-DO-06 | Configuration is treated as code and deployed with the same rigor | Manual | DEV |
| SAAS-DO-07 | A version and change-management policy is communicated to customers | Manual | DEV |
| SAAS-DO-08 | The product is not customised per customer | Manual | DEV |
| SAAS-DO-09 | A rollback plan exists for failed deployments | Manual | DEV |
| SAAS-DO-10 | Testing runs at several stages | Manual | DEV |
| SAAS-DO-11 | Customers are told about upcoming and completed deployments | Manual | DEV |
| SAAS-DO-12 | Established DevOps tooling is used instead of custom tooling | Manual | DEV |

### Incident management (IM) -- 13 items

| # | Item | Scout | Source |
|---|---|---|---|
| SAAS-IM-01 | The organisation accepts 24x7 live-site responsibility with a staffed on-call rotation | Manual | INC |
| SAAS-IM-02 | A frontline support team handles cases and escalates to engineering | Manual | INC |
| SAAS-IM-03 | Incident tooling covers monitoring, escalation and controlled production change | Manual -- `monitor.actionGroups` attached as evidence | INC |
| SAAS-IM-04 | Azure Monitor action groups are enabled | Automated -- `monitor.actionGroups` | INC |
| SAAS-IM-05 | Severity levels and an escalation path are defined | Manual | INC |
| SAAS-IM-06 | Architecture, owners and key contacts are documented for triage | Manual | INC |
| SAAS-IM-07 | Responders can reach logs and make controlled production changes | Manual -- `management.logAnalyticsWorkspaces` attached as evidence | INC |
| SAAS-IM-08 | A commercial status page and a communications manager keep customers informed | Manual | INC |
| SAAS-IM-09 | Recovery is prioritised over diagnosis during an incident | Manual | INC |
| SAAS-IM-10 | Internal post-incident reviews track remediation with clear accountability | Manual | INC |
| SAAS-IM-11 | Customer-facing post-incident reviews are published | Manual | INC |
| SAAS-IM-12 | A mission-critical support plan exists with platform vendors | Manual | INC |
| SAAS-IM-13 | Alert rules cover availability and performance of the service | Manual -- `monitor.metricAlertRules` attached as evidence | INC |

### AI strategy for SaaS (AI) -- 12 items

| # | Item | Scout | Source |
|---|---|---|---|
| SAAS-AI-01 | AI strategy is set at leadership level with a clear vision and principles | Manual | AIS |
| SAAS-AI-02 | A named owner or working group is accountable for AI initiatives | Manual | AIS |
| SAAS-AI-03 | A shared inventory of AI use cases separates foundational, conversational, agentic and multi-agent uses | Manual -- `domains.ai.cognitiveAccounts` attached as evidence | AIS |
| SAAS-AI-04 | The AI strategy is communicated and teams are trained in AI | Manual | AIS |
| SAAS-AI-05 | AI initiatives map to measurable business outcomes | Manual | AIS |
| SAAS-AI-06 | Humans stay in the loop for critical judgments | Manual | AIS |
| SAAS-AI-07 | AI governance defines the model lifecycle | Manual | AIS |
| SAAS-AI-08 | Build, buy or customise is decided for each AI capability | Manual -- `domains.ai.mlWorkspaces` attached as evidence | AIS |
| SAAS-AI-09 | GenAIOps practices are part of DevOps and CI/CD | Manual | AIS |
| SAAS-AI-10 | Responsible AI principles are embedded in foundational practices | Manual | AIS |
| SAAS-AI-11 | Shared models are not trained on raw customer data without explicit permission | Manual | AIS |
| SAAS-AI-12 | The product can be used by AI agents through APIs | Manual | AIS |

## Summary

| Area | Items | Automated | Manual |
|---|---|---|---|
| Billing and cost management | 10 | 1 | 9 |
| Governance and compliance | 10 | 3 | 7 |
| Resource organization | 7 | 0 | 7 |
| Identity and access management | 10 | 0 | 10 |
| Compute | 10 | 3 | 7 |
| Networking | 10 | 2 | 8 |
| Data | 14 | 3 | 11 |
| Deployment (DevOps) practices | 12 | 0 | 12 |
| Incident management | 13 | 1 | 12 |
| AI strategy for SaaS | 12 | 0 | 12 |
| **Total** | **108** | **13** | **95** |

The AI strategy items come from the SaaS "AI strategy" article; the resource organization items from the
"Resource organization" article, which the assessment page lists among the design areas. Design methodology and
design principles pages are not enumerated: they describe how to apply the design areas rather than adding
checks of their own.

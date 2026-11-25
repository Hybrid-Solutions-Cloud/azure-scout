# Sustainability Manager Well-Architected — enumerated source for the Microsoft Sustainability Manager Well-Architected assessment

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `msm.wellarchitected.yaml` reviews an implementation of Microsoft's sustainability application against the
Well-Architected for Industry guidance. It is Scout's counterpart to the
[Microsoft Sustainability Manager | Well-Architected Assessment](https://learn.microsoft.com/en-us/assessments/333d9326-e34c-40e1-88d9-8342afceec36/),
which Microsoft Learn now lists as the Microsoft Dynamics 365 Sustainability Assessment.
`src/assess/rules/msm.wellarchitected.yaml` is written against this page only, and every rule cites an item number
from the tables below. Every item is a **manual** question answered with `-AssessmentAnswers`, because Scout does
not read Dataverse or Power Platform data.

## Source

| Field | Value |
|---|---|
| Assessment | [Microsoft Sustainability Manager | Well-Architected Assessment](https://learn.microsoft.com/en-us/assessments/333d9326-e34c-40e1-88d9-8342afceec36/) (question text not published; Learn lists it as the Microsoft Dynamics 365 Sustainability Assessment) |
| Framework version | Well-Architected for Dynamics 365 Sustainability and Well-Architected for Industry on Microsoft Learn, current as of the extraction date; no published version number |
| Extraction date | 2026-11-25 |
| Verification method | Pages marked `fetched` in the source list were fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25. Pages marked `search excerpt` were read through `microsoft_docs_search` excerpts on the same day, not in full. The Dataverse, Power Platform and Azure interfaces named in the last section were checked against Learn reference pages the same day. No Dataverse environment was read. |

## Product status

Checked against Microsoft Learn on 2026-11-25.

- **Renamed, not retired.** Microsoft Sustainability Manager has been rebranded as **Dynamics 365 Sustainability**.
  Every page in the Well-Architected set carries the note that this is a new product name only, with functionality,
  capabilities, licensing and service offerings unchanged. Learn's Well-Architected for Industry overview lists this
  same assessment as the "Microsoft Dynamics 365 Sustainability Assessment". Scout keeps the `MSM-` prefix and the
  assessment name from the catalog title, and says "Dynamics 365 Sustainability" where it cites current guidance.
- **Umbrella name.** Current reference-architecture pages say Microsoft for Sustainability where older pages
  (and the Learn training module) say Microsoft Cloud for Sustainability.
- **Preview capabilities.** The guidance marks some Scope 3 categories, the water and waste data models, Teams
  collaboration and data approval management as preview. MSM-CF-08 and MSM-DI-07 ask whether production depends on them.
- **Replacement guidance.** The Well-Architected for Dynamics 365 Sustainability pages (design principles, design
  and deployment and monitoring checklists, best practices) are the current source; the groups below follow them.

## The one thing this enumeration is NOT

**The questions are Scout-derived, not Microsoft's.** The assessment's question text is not published, so the items
below are Scout's reading of the guidance listed above. The `MSM-*` IDs, and the assignment of an item to a group,
are Scout's own.

**Scout does not read this product's data yet.** Dynamics 365 Sustainability runs on Dataverse and the Power
Platform. Scout reads Azure (Resource Graph and ARM) and one Microsoft Entra policy; it does not read Dataverse
settings, Power Platform environments or Microsoft Entra Conditional Access, and the collect.json contract in
`src/collect/Invoke-Collect.ps1` holds none of that. So every rule is `manual: true` with `query: null`: it is
exported as a question by `Export-ScoutAssessmentQuestion`, answered with `-AssessmentAnswers` (see
[Questionnaire Answers](../assessment/questionnaire-answers.md)), and stays Manual and out of the score until
answered. Azure resources that sit around the solution (Synapse, storage, gateways, Application Insights) are
covered by Scout's Azure assessments, not by this one.

Sources:

- [WAI] [Overview of Well-Architected for Industry (lists the Dynamics 365 Sustainability assessment)](https://learn.microsoft.com/industry/well-architected/overview) -- fetched
- [OV] [Overview of Dynamics 365 Sustainability (formerly Microsoft Sustainability Manager)](https://learn.microsoft.com/dynamics365/sustainability/well-architected/d365-sustainability-overview) -- fetched
- [DP] [Design principles for Dynamics 365 Sustainability](https://learn.microsoft.com/dynamics365/sustainability/well-architected/cloud-sustainability-design-principles) -- fetched
- [ARCHS] [Reference architecture for Dynamics 365 Sustainability](https://learn.microsoft.com/dynamics365/sustainability/well-architected/d365-sustainability-architecture) -- fetched
- [DCON] [Design considerations for Dynamics 365 Sustainability](https://learn.microsoft.com/dynamics365/sustainability/well-architected/design-consideration) -- fetched
- [DBP] [Design best practices for Dynamics 365 Sustainability](https://learn.microsoft.com/dynamics365/sustainability/well-architected/design-bestpractice) -- fetched
- [DCL] [Design checklist for Dynamics 365 Sustainability](https://learn.microsoft.com/dynamics365/sustainability/well-architected/design-checklist) -- fetched
- [DEP] [Deployment considerations for Dynamics 365 Sustainability](https://learn.microsoft.com/dynamics365/sustainability/well-architected/deploy-consideration) -- fetched
- [DEPB] [Deployment best practices for Dynamics 365 Sustainability](https://learn.microsoft.com/dynamics365/sustainability/well-architected/deploy-bestpractice) -- fetched
- [MON] [Monitoring considerations for Dynamics 365 Sustainability](https://learn.microsoft.com/dynamics365/sustainability/well-architected/monitor-consideration) -- fetched
- [MONB] [Monitoring best practices for Dynamics 365 Sustainability](https://learn.microsoft.com/dynamics365/sustainability/well-architected/monitor-bestpractice) -- fetched
- [HS] [Implement hierarchical security in Dynamics 365 Sustainability](https://learn.microsoft.com/dynamics365/sustainability/well-architected/sustainability-hierarchical-security) -- search excerpt
- [REFA] [Overview of Microsoft for Sustainability reference architectures](https://learn.microsoft.com/dynamics365/sustainability/well-architected/sustainability-architecture-overview) -- search excerpt
- [COMP] [Compliance in Microsoft for Sustainability](https://learn.microsoft.com/dynamics365/sustainability/compliance-overview) -- search excerpt
- [CAF] [Sustainability considerations in your cloud strategy (Cloud Adoption Framework)](https://learn.microsoft.com/azure/cloud-adoption-framework/strategy/inform/sustainability) -- search excerpt

Every item is **manual**: it is exported as a question and scored only when answered with `-AssessmentAnswers`
(see [Questionnaire Answers](../assessment/questionnaire-answers.md)).

## The enumeration — 47 items across 9 groups

### Configure the solution (MSM-CF) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| MSM-CF-01 | Organisation data (business units, facilities, reporting years) is configured before activity data is imported | Manual | DCL, DBP |
| MSM-CF-02 | Reference data is configured before activity data, to the regulations, conversions and granularity required | Manual | DCL, DBP |
| MSM-CF-03 | The first rollout covers one scenario or emission scope end to end before widening | Manual | DBP |
| MSM-CF-04 | Units and unit conversions are specified and checked against the activity and model units | Manual | DCL, DBP |
| MSM-CF-05 | Emission factors and factor mappings are complete, and the factor libraries are kept current | Manual | DCL, DBP, DCON |
| MSM-CF-06 | Calculation models are tested on small data sets, and calculation jobs stay under the record limit | Manual | DCL, DBP |
| MSM-CF-07 | The calculation methodology is decided and documented, using copies of the built-in models where changes are needed | Manual | DP, DCON |
| MSM-CF-08 | Preview capabilities (some Scope 3 categories, water and waste data models, Teams collaboration) are not relied on in production | Manual | DCON |

### Data ingestion and integration (MSM-DI) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| MSM-DI-01 | A data ingestion strategy is set per source (Excel template, Power Query, partner connector, pipeline or manual) | Manual | DP, ARCHS |
| MSM-DI-02 | Native Power Query connectors are preferred to custom connectors | Manual | DP, ARCHS |
| MSM-DI-03 | Data connections use service accounts, not the account of the person who built them | Manual | DCL, DBP, DCON |
| MSM-DI-04 | Data refresh is scheduled for every connection at the frequency the reporting needs | Manual | DBP, DCON |
| MSM-DI-05 | Import hygiene is followed: latest templates, transformation checklist, validated auto-mapping | Manual | DCL, DCON |
| MSM-DI-06 | Only the activity data needed for calculations is ingested | Manual | DP |
| MSM-DI-07 | Import errors are reviewed and fixed, and data approval staging is used where needed (preview) | Manual | ARCHS |
| MSM-DI-08 | The on-premises data gateway is clustered for availability, and its recovery keys and environments are managed | Manual | DBP, DCON |

### Extend the solution (MSM-EX) — 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| MSM-EX-01 | Extensions include only the components they change, and default solution components are cloned, not overridden | Manual | DBP, DCON |
| MSM-EX-02 | Custom dimensions are considered before the data model is extended | Manual | DBP, DCON |
| MSM-EX-03 | The Power Apps solution checker is run regularly on customisations | Manual | DCL, DBP |
| MSM-EX-04 | Extensions use supported techniques, are tested at volume and are deployed through ALM automation | Manual | DCL |

### Security, identity and access (MSM-SE) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| MSM-SE-01 | Least privilege: built-in roles are copied per business unit and custom roles are copied from existing roles | Manual | DP, DCL, DBP |
| MSM-SE-02 | Business units, Entra groups and an environment security group segment access | Manual | DCL, DEPB, HS |
| MSM-SE-03 | Administrator access to the environments is limited through a Privileged Identity Management group | Manual -- PIM eligibility is not in collect.json | DCL |
| MSM-SE-04 | Conditional Access with multifactor authentication applies to users of the application | Manual -- Conditional Access policies are not in collect.json | ARCHS |
| MSM-SE-05 | Defender for Cloud protects the related resources, and Sentinel is considered for signals | Manual | DCL, DBP |
| MSM-SE-06 | Purview classifies the Dataverse and Power BI data used by the solution | Manual | DBP, MONB |
| MSM-SE-07 | The limits of dashboard and insights access control are understood and handled | Manual | DCON, HS |
| MSM-SE-08 | Exports to external analytical stores are secured and given only to people who need them | Manual | DCL |

### Deployment, monitoring and operations (MSM-OB) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| MSM-OB-01 | Dataverse auditing is turned on in every environment | Manual | MON, MONB |
| MSM-OB-02 | Dataverse diagnostics go to Application Insights and Log Analytics, with alerts for admins and owners | Manual | MONB |
| MSM-OB-03 | Power Platform analytics are exported to a data lake or Application Insights and kept as long as policy requires | Manual | MON, MONB |
| MSM-OB-04 | Deployments are planned: sample data is off for test and production, and time is reserved for installs | Manual | DEP |
| MSM-OB-05 | Azure Synapse Link for Dataverse is deployed in the right tenant and region with change tracking enabled | Manual | DEP |

### Privacy, compliance and regulatory fit (MSM-PC) — 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| MSM-PC-01 | Regulatory and disclosure requirements are identified for each country where the organisation operates | Manual | DBP, REFA |
| MSM-PC-02 | Product availability, countries or regions and languages match the tenant | Manual | DCON |
| MSM-PC-03 | Compliance offerings and privacy terms were reviewed against the organisation requirements | Manual | DCL, COMP |
| MSM-PC-04 | Data residency needs for transactional data are defined and drive the retention design | Manual | DBP |

### Reporting and analytics (MSM-RP) — 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| MSM-RP-01 | Reporting years and periods match the organisation reporting requirements before data is imported | Manual | DCL |
| MSM-RP-02 | The default reports and embedded intelligence are used before custom reports are built | Manual | DCL, ARCHS |
| MSM-RP-03 | The data estate is mapped and an analytics strategy covers current and future reporting needs | Manual | DCL |
| MSM-RP-04 | Custom reports read exported data (Synapse or Data Lake), not the managed data lake | Manual | DCON, ARCHS |

### Reliability, cost and performance (MSM-PI) — 4 items

| # | Item | Scout | Source |
|---|---|---|---|
| MSM-PI-01 | The Azure reliability design checklist is applied to the Azure parts of the solution | Manual | DCON |
| MSM-PI-02 | The Dataverse entitlement is tracked, and extra capacity is planned and approved | Manual | DCON, DBP |
| MSM-PI-03 | Historical data is archived to cheaper long-term storage within the retention policy | Manual | DCON, DBP |
| MSM-PI-04 | Ingestion design respects Power Query and Dataverse service protection limits and keeps sources in one cloud and region | Manual | DCON, DBP |

### Emissions from IT operations (MSM-IT) — 2 items

| # | Item | Scout | Source |
|---|---|---|---|
| MSM-IT-01 | Emissions from IT operations are measured with the Emissions Impact Dashboard and Azure carbon optimization | Manual | REFA, CAF |
| MSM-IT-02 | Emissions from IT operations feed the organisation sustainability reporting | Manual | REFA, CAF |

## Summary

| Group | Items | Automated | Manual |
|---|---|---|---|
| Configure the solution | 8 | 0 | 8 |
| Data ingestion and integration | 8 | 0 | 8 |
| Extend the solution | 4 | 0 | 4 |
| Security, identity and access | 8 | 0 | 8 |
| Deployment, monitoring and operations | 5 | 0 | 5 |
| Privacy, compliance and regulatory fit | 4 | 0 | 4 |
| Reporting and analytics | 4 | 0 | 4 |
| Reliability, cost and performance | 4 | 0 | 4 |
| Emissions from IT operations | 2 | 0 | 2 |
| **Total** | **47** | **0** | **47** |

## What an automated version would need

Everything below needs an app registration or service principal with read-only access to the environment, a new
collect section, and a gate on each rule so an environment that was not read reports Not assessed instead of Pass.

| Items | What would be read | Interface and permission |
|---|---|---|
| MSM-OB-01 | Whether auditing is on and its retention | Dataverse Web API `GET [org URI]/api/data/v9.2/organizations?$select=isauditenabled,auditretentionperiodv2,isuseraccessauditenabled,useraccessauditinginterval`; any user can read the configuration, changing it needs System Administrator or System Customizer |
| MSM-OB-01 | Which tables are audited | Dataverse Web API `GET .../EntityDefinitions?$select=LogicalName,IsAuditEnabled&$filter=IsAuditEnabled/Value eq true and IsPrivate eq false` |
| MSM-OB-02, OB-03 | Data export packages to Application Insights and Data Lake | Power Platform admin center data export (needs a managed environment and a premium Dataverse licence); no read API was confirmed in this pass |
| MSM-SE-01, SE-02 | Security roles, business units and teams | Dataverse Web API tables `role`, `businessunit`, `team` (not researched in this pass) |
| MSM-SE-03, SE-04 | Conditional Access and PIM for the sustainability users and admins | Microsoft Graph v1.0 `GET /identity/conditionalAccess/policies`; `Policy.Read.All`. PIM eligibility is a separate Graph API not researched in this pass. |
| MSM-SE-05, OB-02 | Defender for Cloud plans, Application Insights export target | Azure Resource Graph and ARM, which Scout already reads |
| MSM-IT-01, IT-02 | Azure emissions | Azure carbon optimization and the Emissions Impact Dashboard (not researched in this pass) |

Items about method, data quality, reporting design and organisation (most of MSM-CF, MSM-DI, MSM-EX, MSM-PC and
MSM-RP) have no API behind them and stay manual in any version.

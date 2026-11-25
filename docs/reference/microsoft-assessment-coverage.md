---
description: Every assessment in Microsoft's assessment catalog, and the Scout assessment that runs it.
---

# Microsoft Assessment Coverage

Microsoft publishes its self-assessments at
[learn.microsoft.com/assessments](https://learn.microsoft.com/assessments/browse/). This page maps each one to the
Scout assessment that runs it. It was checked against the catalog on 2026-11-25.

Two things are true of almost all of them:

- **Microsoft publishes no question text.** The assessments are interactive questionnaires
  behind sign-in. Scout's items are its own reading of the guidance each assessment is built on,
  and each framework page says so.
- **Many questions are about how an organisation works**, not how a resource is configured.
  Scout answers what Azure data can answer, attaches the evidence it has, and takes the rest as
  [questionnaire answers](../assessment/questionnaire-answers.md).

## Azure assessments

| Microsoft assessment | Scout assessment | Notes |
|---|---|---|
| Azure Well-Architected Review | `WAF: Reliability`, `WAF: Security`, `WAF: Cost Optimization`, `WAF: Operational Excellence`, `WAF: Performance Efficiency`, `CAF: Azure Landing Zone` | Core review, by pillar |
| Azure Well-Architected Framework Maturity Model Assessment | `WAF: Maturity Model` | |
| Well-Architected service guides (guidance, not in the catalog) | `WAF: Service Guides` | Configuration recommendations of 20 service guides |
| Azure Landing Zone Review | `CAF: Azure Landing Zone` and the eight `CAF:` design areas | |
| Azure Local \| Well-Architected Review | `WAF: Azure Local` | |
| Azure Well-Architected AI workload | `Assess: AI Workload` | All ten design areas |
| Azure Well-Architected Azure Virtual Desktop workload | `Workload: AVD` (AVD in Azure), `Assess: AVD Workload` (AVD on Azure Local) | |
| Azure Well-Architected Azure VMware Solution workload | `Workload: AVS` | |
| Azure VMware Solution Landing Zone Assessment Review | `Workload: AVS Landing Zone` | |
| Azure Well-Architected Oracle on Azure IaaS workload | `Workload: Oracle on Azure IaaS` | Automated checks cover VMs from Oracle Marketplace images |
| Azure Well-Architected SaaS workload | `Workload: SaaS` | |
| SAP on Azure \| Well-Architected Review | `Workload: SAP on Azure` | Automated checks cover SAP registered with Azure Center for SAP solutions |
| Mission Critical \| Well-Architected Review | `WAF: Mission Critical` | |
| Sustainability \| Well-Architected Review | `WAF: Sustainability` | |
| Go-Live \| Well-Architected Review | `WAF: Go-Live` | Microsoft publishes only a landing page; Scout's is its own production-readiness review |
| Azure Machine Learning | `WAF: Azure Machine Learning` | |
| Azure AI Search (Well-Architected) | `WAF: Azure AI Search` | |
| Analytics (Well-Architected) | `WAF: Analytics` | |
| Data Services (Well-Architected) | `WAF: Data Services` | |
| Cloud Adoption Security Assessment (CASA) | `Microsoft: CASA` | |
| DevOps Capability Assessment | `Microsoft: DevOps Capability` | |
| FinOps Review (New) | `Microsoft: FinOps Review` | FinOps Framework 2026 |
| AI Readiness Assessment | `Microsoft: AI Readiness` | |
| Technical Assessment for Generative AI in Azure | `Microsoft: Generative AI Technical` | |
| GenAIOps Maturity Model Assessment | `Microsoft: GenAIOps Maturity` | |
| Platform Engineering Technical Assessment | `Microsoft: Platform Engineering` | |
| Analytics Journey Tracker | `Microsoft: Analytics Journey Tracker` | |
| App and Data Modernization Readiness Tool | `Microsoft: App and Data Modernization` | |
| Well-Architected Reliability Assessment (WARA tooling, not in the catalog) | `Microsoft: Well-Architected Reliability Assessment` | Backed by the Azure Proactive Resiliency Library |
| Azure Advisor (not in the catalog) | `Microsoft: Azure Advisor` | |
| Regulatory compliance in Azure Policy (not in the catalog) | `Assess: Compliance` | Every assigned initiative: MCSB, CIS, ISO 27001, NIST, PCI DSS and more |

## Retired by Microsoft

Microsoft deletes these in January 2027. Scout keeps the capability, re-based on the guidance
each was built on, and the old names still work.

| Microsoft assessment | Scout assessment |
|---|---|
| Strategic Migration Assessment and Readiness Tool (SMART) | `CAF: Migrate readiness` (CAF Plan + CAF Migrate) |
| Cloud Governance | `CAF: Govern` (CAF Govern) |
| Cloud Journey Tracker, Cloud Adoption Strategy Evaluator, Developer Velocity Assessment | Not carried forward: Microsoft retired them without a replacement methodology |

## Not yet in Scout

These Microsoft assessments are for products other than Azure, so they need data sources Scout
does not read yet (the Power Platform admin API and Microsoft Graph):

- Power Platform Well-Architected
- Power Platform Solution Assessment
- Power Platform Adoption Assessment
- Microsoft Sustainability Manager \| Well-Architected Assessment
- Microsoft Cloud for Financial Services \| Well-Architected for Industry
- Windows 11 Pro Migration Readiness Assessment
- Data Security for Copilot for Microsoft 365

The catalog's partner journeys (Microsoft Partner and industry readiness guides) and learner
skill self-assessments are training material, not assessments of an environment, so Scout does
not run them.

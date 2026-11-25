# WAF — enumerated source for the Azure Machine Learning technology review

**Enumerated 2026-11-25. Verification method and limits are stated below — read them before quoting
any coverage number from this page.**

Scout's `waf.machinelearning.yaml` scores the Azure Machine Learning review. This page enumerates the Azure Well-Architected Framework Azure Machine Learning service guide, item by item, and the rule file is written against this page only; every rule cites an item number from the tables below.

## Source

| Field | Value |
|---|---|
| Assessment | [Azure Machine Learning — Well-Architected Review](https://learn.microsoft.com/en-us/assessments/eec33ce4-4ef0-4bd2-9f69-1956e50465d4/) (question text not published) |
| Framework version | Azure Well-Architected Framework Azure Machine Learning service guide, current at extraction |
| Extraction date | 2026-11-25 |
| Verification method | The service guide was fetched in full with the Microsoft Learn MCP `microsoft_docs_fetch` tool on 2026-11-25; every design-checklist bullet and configuration-recommendation row was read. The ARM properties the automated items read were checked against the collection queries in `src/collect/Invoke-Collect.ps1`; the workspace property names were not re-verified against the ARM template reference in this pass. |

## The one thing this enumeration is NOT

**It is not Microsoft's question list.** The assessment's questions are not published. The items below are **Scout's** reading of the service guide and the `WAF-ML-*` ids are Scout's. The guide's technology scope is Machine Learning, compute clusters and compute instances; it does not address connected resources such as data stores or Key Vault, so those are only evidence here.

Sources (the code after each item names the page and section; -C is a workload design checklist bullet, -R a configuration recommendations row):

- [MLG] [Architecture best practices for Azure Machine Learning](https://learn.microsoft.com/azure/well-architected/service-guides/azure-machine-learning), sections Reliability, Security, Cost Optimization, Operational Excellence, Performance Efficiency

The workspace dataset also carries `hbiWorkspace` (high business impact) and `v1LegacyMode`; neither answers an item in the guide, so they are evidence only. Items about compute clusters, compute instances, online endpoints and registries are manual: those are child resources of the workspace that the assessment collection does not read. The report that accompanies this page lists the projections that would automate them.

## The enumeration — 44 items

### Reliability (WAF-ML-RE) — 9 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ML-RE-01 | Models are deployed to environments that support availability zones | ❌ Manual — the hosts models run on (AKS, managed online endpoints) are not collected; workspaces attached | MLG-RE-C |
| WAF-ML-RE-02 | Compute for training and inferencing is sized to the workload | ❌ Manual — capacity-planning judgement | MLG-RE-C |
| WAF-ML-RE-03 | Exploratory workspaces are separate from production workspaces | ❌ Manual — workspace purpose is not an ARM property; workspaces attached | MLG-RE-C |
| WAF-ML-RE-04 | Managed online endpoints use a blue-green or traffic-split release | ❌ Manual — endpoint deployments are child resources, not collected | MLG-RE-C |
| WAF-ML-RE-05 | Compute type (clusters, instances, external inference hosts) is chosen from reliability needs and SLAs | ❌ Manual — architecture judgement | MLG-RE-C |
| WAF-ML-RE-06 | Long training runs checkpoint so they can resume after interruption | ❌ Manual — training code, not ARM | MLG-RE-C, MLG-RE-R |
| WAF-ML-RE-07 | A recovery strategy covers the workspace and its dependencies (Key Vault, Storage, Container Registry) | ❌ Manual — recovery plans are not collected; workspaces attached | MLG-RE-C |
| WAF-ML-RE-08 | A multi-region deployment is considered for models that must survive a regional outage | ❌ Manual — workspaces attached with their region | MLG-RE-R |
| WAF-ML-RE-09 | Compute clusters used for batch inferencing use the Dedicated VM tier | ❌ Manual — compute clusters are child resources, not collected | MLG-RE-R |

### Security (WAF-ML-SE) — 15 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ML-SE-01 | The Azure security baseline for Machine Learning is applied and monitored | ❌ Manual — baseline compliance is not an ARM property | MLG-SE-R |
| WAF-ML-SE-02 | Workspaces use managed virtual network isolation | ✅ workspace managed-network isolation mode | MLG-SE-C, MLG-SE-R |
| WAF-ML-SE-03 | Workspace public network access is disabled | ✅ workspace publicNetworkAccess | MLG-SE-C, MLG-SE-R |
| WAF-ML-SE-04 | Each workspace is reachable through a private endpoint | ✅ workspace to private endpoint join | MLG-SE-R |
| WAF-ML-SE-05 | Managed outbound access is set to Allow only approved outbound | ✅ managedNetwork.isolationMode is AllowOnlyApprovedOutbound | MLG-SE-C, MLG-SE-R |
| WAF-ML-SE-06 | Dependent services (Storage, Key Vault, Container Registry) use private endpoints with public access disabled | ❌ Manual — the workspace-to-dependency link is not collected; storage accounts with no default-deny firewall attached | MLG-SE-R |
| WAF-ML-SE-07 | Workspaces authenticate to other services with managed identities | ✅ workspace identity type | MLG-SE-R |
| WAF-ML-SE-08 | Local authentication is disabled on compute clusters and instances | ❌ Manual — compute resources are child resources, not collected | MLG-SE-R |
| WAF-ML-SE-09 | The public SSH port is closed on compute clusters (remoteLoginPortPublicAccess = Disabled) | ❌ Manual — compute resources are child resources, not collected | MLG-SE-R |
| WAF-ML-SE-10 | Compute gets no public IP address (enableNodePublicIp = false) | ❌ Manual — compute resources are child resources, not collected | MLG-SE-R |
| WAF-ML-SE-11 | Compute instances are recreated to pick up the latest operating system image | ❌ Manual — image age is not collected | MLG-SE-R |
| WAF-ML-SE-12 | Workspace access uses Microsoft Entra groups and least-privilege RBAC, per use case | ❌ Manual — role assignments attached; scope-to-workspace review is judgement | MLG-SE-C, MLG-SE-R |
| WAF-ML-SE-13 | Model catalog deployments, container registries and Python packages are restricted to approved sources | ❌ Manual — registry and package policy is workspace configuration, not collected | MLG-SE-C, MLG-SE-R |
| WAF-ML-SE-14 | Data at rest uses customer-managed keys where required | ❌ Manual — customer-managed keys are requirement-driven; the workspaces whose encryption status is not Enabled are attached as evidence (Foundry project workspaces inherit their hub's and are skipped) | MLG-SE-C, MLG-SE-R |
| WAF-ML-SE-15 | Data exfiltration prevention limits egress to approved storage accounts | ❌ Manual — network policy, not collected | MLG-SE-R |

### Cost optimization (WAF-ML-CO) — 7 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ML-CO-01 | Compute SKU family (CPU, GPU, memory-optimised) is matched to the workload and the choice is documented | ❌ Manual — architecture judgement | MLG-CO-C, MLG-CO-R |
| WAF-ML-CO-02 | Compute clusters autoscale to a minimum of zero nodes with a deliberate idle time | ❌ Manual — compute clusters are child resources, not collected | MLG-CO-R |
| WAF-ML-CO-03 | Compute instances shut down when idle or on a schedule | ❌ Manual — compute instances are child resources, not collected | MLG-CO-C, MLG-CO-R |
| WAF-ML-CO-04 | Training runs have termination policies | ❌ Manual — job definition, not ARM | MLG-CO-R |
| WAF-ML-CO-05 | Low-priority VMs are used for batch work that tolerates interruption, and training is tested for parallelisation | ❌ Manual — architecture judgement | MLG-CO-C, MLG-CO-R |
| WAF-ML-CO-06 | Reserved VM Instances cover steady, predictable usage | ❌ Manual — reservations attached | MLG-CO-C, MLG-CO-R |
| WAF-ML-CO-07 | Policies and quotas bound compute, and CPU and GPU utilisation is monitored | ❌ Manual — quota and utilisation are not collected | MLG-CO-C |

### Operational excellence (WAF-ML-OE) — 8 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ML-OE-01 | The number of workspaces is kept to what separation requirements need | ❌ Manual — workspaces attached for counting | MLG-OE-R |
| WAF-ML-OE-02 | Model catalogs and registries store, version and share machine learning assets | ❌ Manual — registry contents are not collected | MLG-OE-C, MLG-OE-R |
| WAF-ML-OE-03 | MLOps pipelines automate data preparation, training and scoring | ❌ Manual — pipeline practice, not ARM | MLG-OE-C |
| WAF-ML-OE-04 | Workspaces, compute and environments are deployed with infrastructure as code | ❌ Manual — deployment method is not an ARM property | MLG-OE-C |
| WAF-ML-OE-05 | Deployed model performance and data drift are monitored | ❌ Manual — model-monitor configuration is not collected | MLG-OE-C, MLG-OE-R |
| WAF-ML-OE-06 | Online endpoints send telemetry to Application Insights | ❌ Manual — Application Insights components attached (link to endpoints is not collected) | MLG-OE-C, MLG-OE-R |
| WAF-ML-OE-07 | Resource logs are collected for Machine Learning workspaces | ✅ diagnostic-settings coverage for the Machine Learning workspace type (a setting present, not which categories) | MLG-OE-R |
| WAF-ML-OE-08 | Curated environments are used where available | ❌ Manual — environment choice, not collected | MLG-OE-C, MLG-OE-R |

### Performance efficiency (WAF-ML-PE) — 5 items

| # | Item | Scout | Source |
|---|---|---|---|
| WAF-ML-PE-01 | Acceptable training time and retrain frequency are defined | ❌ Manual — target-setting, not ARM | MLG-PE-C |
| WAF-ML-PE-02 | Performance targets (response time, requests per second, error rate, uptime) are defined for deployed models | ❌ Manual — target-setting, not ARM | MLG-PE-C |
| WAF-ML-PE-03 | Compute clusters, not instances, are used where autoscaling is needed for training | ❌ Manual — compute resources are child resources, not collected | MLG-PE-C, MLG-PE-R |
| WAF-ML-PE-04 | Deployment environments autoscale to demand | ❌ Manual — autoscale settings attached (link to endpoints is not collected) | MLG-PE-C, MLG-PE-R |
| WAF-ML-PE-05 | Deployed model and endpoint infrastructure are monitored against baselines | ❌ Manual — monitoring configuration, not collected | MLG-PE-C, MLG-PE-R |

## Summary

| Pillar | Items | Automated (✅) | Manual (❌) |
|---|---|---|---|
| Reliability | 9 | 0 | 9 |
| Security | 15 | 5 | 10 |
| Cost optimization | 7 | 0 | 7 |
| Operational excellence | 8 | 1 | 7 |
| Performance efficiency | 5 | 0 | 5 |
| **Total** | **44** | **6** | **38** |

Every automated item is gated on its resources (or its diagnostic-coverage rows) existing, so an estate
without them reports the item Not assessed. The rules live in `src/assess/rules/waf.machinelearning.yaml`.

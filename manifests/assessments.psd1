#
# Azure Scout — assessment module registry
#
# Every assessment declares:
#   Description  human summary
#   Category     the Scout -Category it scopes discovery to ('*' = all)
#   Collect      collect categories to gather
#   Ingest       third-party collectors to fold into collect.json
#   Rules        rule-file glob patterns (caf.<domain> / waf.<domain>)
#   Frameworks   the CAF areas / WAF pillars this assessment maps to
#   Tags         classification tags
#   Benchmark    optional benchmark reference
#   Reporters    default output renderers
#
# Adding an assessment = adding an entry here plus a rule file. No core change.
# See docs/design/assessment-registry.md for the full catalogue (AB#5057).
#
@{
    # ---- cross-category roll-ups ----
    'CAF: Azure Landing Zone' = @{
        Description = 'CAF/WAF landing zone audit (all areas)'
        Category    = '*'
        # Rules = caf.*, waf.* pulls in every rule file (all 8 CAF areas + all 5 WAF
        # pillars, including the per-domain rule files from Epic AB#5056), so Collect
        # must gather every category too, not the 5-category subset this used to list
        # — now that -Categories actually filters which ARG queries Invoke-Collect
        # runs, an incomplete list here would silently starve Storage/Databases/Web/
        # Containers/Analytics/AI/Integration/Hybrid/IoT/Compute/Cost rules of data.
        Collect     = @('*')
        Ingest      = @('Governance', 'AdvisorScores')
        # 'xr.*' pulls in the cross-resource rules (AB#6835). A landing-zone audit that could not
        # say which VMs have no backup was answering a narrower question than its name claims.
        #
        # AB#6890. The WAF pillars are ENUMERATED, not globbed. `waf.*` swept in every rule file
        # whose name happens to start with waf -- which by now includes the WORKLOAD assessments
        # (waf.ai, waf.avd, waf.azurelocal.*). A run selecting LandingZone and Cloud Governance
        # was therefore scoring AI-workload, AVD and Azure Local rules it was never asked for, and
        # the evidence workbook grew a visible tab for each of them: 34 areas where the audit
        # covers 14. That is the same dangling-glob class that silently cost `Assess: Storage` its
        # WAF rules, just pointing the other way.
        #
        # WAF defines FIVE pillars. If a sixth ever appears, it is added here deliberately;
        # a new waf.<workload>.yaml must never join a landing-zone audit by filename alone.
        # tests/Assessment.LandingZoneScope.Tests.ps1 gates exactly that.
        # The EIGHT CAF landing-zone design areas, named. `caf.*` had the same defect as `waf.*`:
        # it swept in caf.iot, caf.avslandingzone, caf.ai, caf.storage and the rest, every one of
        # which is owned by its own assessment further down this file. A landing-zone audit is the
        # eight design areas, not "every rule file whose name starts with caf".
        Rules       = @(
            'caf.billing'
            'caf.identity'
            'caf.network'
            'caf.resourceorg'
            'caf.security'
            'caf.management'
            'caf.governance'
            'caf.platformauto'
            'waf.cost'
            'waf.operational'
            'waf.performance'
            'waf.reliability'
            'waf.security'
            'xr.*'
        )
        Frameworks  = @('CAF: all 8 design areas', 'WAF: all 5 pillars', 'XR: Cross-resource posture')
        Tags        = @('caf', 'waf', 'landing-zone', 'cross-resource')
        Benchmark   = 'alz-reference.json'
        Reporters   = @('PowerBi', 'Html', 'Pptx', 'React')
    }
    # 'Estate' (full digital-estate inventory, Rules = @()) was removed entirely by AB#6845/#6795.
    # It scored nothing -- a menu entry that runs and returns nothing reads as "no findings", the
    # same false negative the provably-broken collectors were retired for (AB#6763 already hid it
    # from the wizard on exactly that evidence). Inventory is a different product from an
    # assessment: run it with `Invoke-AzureScout` (no `-Assessment`), which every code path in
    # this repo already treats as the non-assessment mode. Nothing here replaces that capability;
    # this only removes the assessment-registry entry that duplicated and mis-scoped it.

    # ---- per-category assessments (Epic AB#5056) ----
    #
    # The `Assess: ` prefix is AB#6762, and it is a stopgap with a known end date.
    #
    # These fifteen entries carried the same names as Scout's fifteen INVENTORY categories --
    # Compute, Storage, Networking and so on. One filters what is collected; the other filters
    # what is scored. Same words, different meaning, and once the wizard menu was fixed to show
    # the registry at all (AB#6754) they would have appeared side by side in one list.
    #
    # Renaming treats the symptom. The end state is retirement: when Release 3 splits LandingZone
    # into per-WAF-pillar and per-CAF-design-area assessments, an operator wanting Compute
    # findings picks the pillars, not a category filter over the same rule set. The prefix buys
    # a legible menu until then.
    #
    # Legacy names still work. Resolve-ScoutAssessmentName maps `Compute` to `Assess: Compute`
    # and warns, so scripted `-Assessment Compute` callers are not broken by a cosmetic change.
    'Assess: Management' = @{
        Description = 'Governance, policy, cost, backup, automation, update manager'
        Category    = 'Management'; Collect = @('Management', 'Compute'); Ingest = @('Governance', 'AdvisorScores')
        Rules = @('caf.governance', 'caf.management', 'caf.billing'); Frameworks = @('CAF: Governance', 'CAF: Management', 'CAF: Billing', 'WAF: Operational', 'WAF: Cost')
        Tags = @('caf', 'governance', 'management'); Reporters = @('Html', 'Excel')
    }
    'Assess: Monitor' = @{
        Description = 'Monitoring, alerting, diagnostics coverage'
        Category    = 'Monitor'; Collect = @('Monitor', 'Compute'); Ingest = @()
        Rules = @('caf.management', 'waf.operational'); Frameworks = @('CAF: Management & monitoring', 'WAF: Operational excellence')
        Tags = @('waf', 'monitor'); Reporters = @('Html', 'Excel')
    }
    'Assess: Networking' = @{
        Description = 'Network topology, firewall, DDoS, exposure, private link'
        Category    = 'Networking'; Collect = @('Networking'); Ingest = @()
        Rules = @('caf.network'); Frameworks = @('CAF: Network topology & connectivity', 'WAF: Security')
        Tags = @('caf', 'networking'); Reporters = @('Html', 'Excel')
    }
    'Assess: Identity' = @{
        Description = 'Identity & access — PIM, Conditional Access, RBAC'
        Category    = 'Identity'; Collect = @('Identity', 'Security'); Ingest = @('Governance')
        Rules = @('caf.identity'); Frameworks = @('CAF: Identity & access management', 'WAF: Security')
        Tags = @('caf', 'identity'); Reporters = @('Html', 'Excel')
    }
    'Assess: Security' = @{
        Description = 'Defender, Key Vault, secure score, exposure'
        Category    = 'Security'; Collect = @('Security'); Ingest = @('AdvisorScores')
        Rules = @('caf.security', 'waf.security'); Frameworks = @('CAF: Security', 'WAF: Security')
        Tags = @('caf', 'waf', 'security'); Reporters = @('Html', 'Excel')
    }
    'Assess: Compute' = @{
        Description = 'VM resilience, zones, backup, right-size, orphans'
        Category    = 'Compute'; Collect = @('Compute', 'Storage'); Ingest = @('AdvisorScores')
        Rules = @('waf.reliability', 'waf.cost', 'waf.performance'); Frameworks = @('WAF: Reliability', 'WAF: Cost', 'WAF: Performance efficiency')
        Tags = @('waf', 'compute'); Reporters = @('Html', 'Excel')
    }
    'Assess: Storage' = @{
        Description = 'Storage public access, TLS, encryption, redundancy'
        Category    = 'Storage'; Collect = @('Storage'); Ingest = @()
        # 'waf.storage' was removed here, not replaced: waf.storage.yaml was deleted in the
        # AB#6746 restructure and its five rules redistributed into the real pillar files
        # (waf.reliability / waf.security / waf.cost), which are their own assessments. The
        # dangling glob matched nothing and silently contributed zero rules while the
        # Frameworks line still advertised WAF coverage. Build-AssessmentCatalog.ps1 -Check
        # now fails on a dangling pattern so this cannot recur.
        Rules = @('caf.storage'); Frameworks = @('CAF: Security')
        Tags = @('caf', 'waf', 'storage'); Reporters = @('Html', 'Excel')
    }
    'Assess: Databases' = @{
        Description = 'SQL/DB private access, TDE, zone redundancy'
        Category    = 'Databases'; Collect = @('Databases'); Ingest = @()
        Rules = @('caf.databases'); Frameworks = @('CAF: Security', 'WAF: Reliability')
        Tags = @('caf', 'databases'); Reporters = @('Html', 'Excel')
    }
    'Assess: Containers' = @{
        Description = 'AKS private clusters, RBAC, registry hardening'
        Category    = 'Containers'; Collect = @('Containers'); Ingest = @()
        Rules = @('caf.containers'); Frameworks = @('CAF: Security', 'WAF: Reliability')
        Tags = @('caf', 'containers'); Reporters = @('Html', 'Excel')
    }
    'Assess: Web' = @{
        Description = 'App Service HTTPS-only, TLS, managed identity'
        Category    = 'Web'; Collect = @('Web'); Ingest = @()
        Rules = @('caf.web'); Frameworks = @('CAF: Security', 'WAF: Security')
        Tags = @('caf', 'web'); Reporters = @('Html', 'Excel')
    }
    'Assess: Analytics' = @{
        Description = 'Analytics data governance and network isolation'
        Category    = 'Analytics'; Collect = @('Analytics'); Ingest = @()
        Rules = @('caf.analytics'); Frameworks = @('CAF: Governance', 'WAF: Security')
        Tags = @('caf', 'analytics'); Reporters = @('Html', 'Excel')
    }
    'Assess: AI' = @{
        Description = 'AI/Cognitive private access and responsible-AI posture'
        Category    = 'AI'; Collect = @('AI'); Ingest = @()
        Rules = @('caf.ai'); Frameworks = @('CAF: Governance', 'WAF: Security')
        Tags = @('caf', 'ai'); Reporters = @('Html', 'Excel')
    }
    'Assess: Integration' = @{
        Description = 'Messaging redundancy and APIM network isolation'
        Category    = 'Integration'; Collect = @('Integration'); Ingest = @()
        Rules = @('caf.integration'); Frameworks = @('CAF: Network topology & connectivity', 'WAF: Reliability')
        Tags = @('caf', 'integration'); Reporters = @('Html', 'Excel')
    }
    'Assess: Hybrid' = @{
        Description = 'Arc onboarding, agent currency, Azure Local'
        Category    = 'Hybrid'; Collect = @('Hybrid'); Ingest = @()
        Rules = @('caf.hybrid'); Frameworks = @('CAF: Management & monitoring', 'WAF: Operational excellence')
        Tags = @('caf', 'hybrid'); Reporters = @('Html', 'Excel')
    }
    'Assess: IoT' = @{
        Description = 'IoT Hub/DPS network isolation and device auth'
        Category    = 'IoT'; Collect = @('IoT'); Ingest = @()
        Rules = @('caf.iot'); Frameworks = @('CAF: Security', 'WAF: Security')
        Tags = @('caf', 'iot'); Reporters = @('Html', 'Excel')
    }

    # ---- WAF workload-specific reviews (Feature AB#6748, Epic AB#6454) ----
    #
    # Neither of these is a WAF pillar or CAF design area -- both cut across several. See
    # src/assess/rules/waf.ai.yaml and waf.avd.yaml for why each declares its own `framework`
    # value (WAF-AI / WAF-AVD) rather than `WAF`, and docs/frameworks/waf-ai-workload-checklist.md
    # / waf-avd-workload-checklist.md for what each enumeration does and does not cover.
    'Assess: AI Workload' = @{
        Description = 'AI workload review (Well-Architected Framework AI workload guidance) -- all 10 AI design areas: 35 Microsoft-tabled items plus Scout-derived items for Data platform, Testing and evaluation, Workload personas and the AI architecture pattern (63 rules, mostly questionnaire items); see docs/frameworks/waf-ai-workload-checklist.md'
        # Analytics, Databases, Storage, Identity, Networking, Monitor: the DATA/PERSONA items read
        # Purview, data factories, Cosmos DB, storage, managed identities and role assignments.
        Category    = 'AI'; Collect = @('AI', 'Analytics', 'Databases', 'Storage', 'Identity', 'Networking', 'Monitor', 'Security'); Ingest = @('Governance')
        Rules = @('waf.ai'); Frameworks = @('WAF: AI workload')
        Tags = @('waf', 'ai', 'workload-review'); Reporters = @('Html', 'Excel')
    }
    'Assess: AVD Workload' = @{
        # AVD-on-Azure-Local scope only -- see docs/frameworks/waf-avd-workload-checklist.md
        # ("The gap this leaves") for what general (non-Azure-Local) AVD is NOT covered by this
        # entry.
        Description = 'AVD-on-Azure-Local workload review (Well-Architected Framework) -- 20 items across all 5 pillars; scoped to AVD deployed on Azure Local, not general Azure Virtual Desktop'
        Category    = 'Compute'; Collect = @('Compute', 'Storage', 'Hybrid', 'Management', 'Monitor'); Ingest = @()
        Rules = @('waf.avd'); Frameworks = @('WAF: AVD workload (Azure Local)')
        Tags = @('waf', 'avd', 'azure-local', 'workload-review'); Reporters = @('Html', 'Excel')
    }
    'Workload: AVD' = @{
        # AVD running in Azure -- the scope of Microsoft's "Azure Well-Architected Azure Virtual
        # Desktop workload" assessment (AB#9300). See docs/frameworks/waf-avd-azure-workload-checklist.md.
        Description = 'Azure Virtual Desktop workload review (AVD in Azure) -- 30 items across all 5 WAF pillars from Microsoft''s current AVD guidance; host pools, session hosts, scaling plans, workspaces, private endpoints and session-host VMs'
        Category    = 'Compute'; Collect = @('Compute', 'Networking', 'Security', 'Storage', 'Management', 'Monitor'); Ingest = @()
        Rules = @('waf.avd.azure'); Frameworks = @('WAF: AVD workload (Azure)')
        Tags = @('waf', 'avd', 'workload-review'); Reporters = @('Html', 'Excel')
    }

    # ---- Microsoft workload, technology and service reviews (AB#9300 phase 2) ----
    # Each is a Microsoft assessment Scout did not have. Microsoft publishes none of their question
    # text, so every item is Scout's reading of the named guidance (see each docs/frameworks page).
    # Automated items are gated on their resources, so an estate without them reports Not assessed.
    'Workload: SAP on Azure' = @{
        Description = 'SAP on Azure workload review -- 38 items across all 5 WAF pillars from Microsoft''s current SAP on Azure guidance; registered virtual instances, instance VMs, load balancers, backup, Azure Monitor for SAP solutions, disks and networking. SAP not registered with Azure Center for SAP solutions is answered through the questionnaire'
        Category    = 'Compute'; Collect = @('Compute', 'Networking', 'Storage', 'Security', 'Management', 'Monitor'); Ingest = @()
        Rules = @('waf.sap'); Frameworks = @('WAF: SAP on Azure workload')
        Tags = @('waf', 'sap', 'workload-review'); Reporters = @('Html', 'Excel')
    }
    'Workload: Oracle on Azure IaaS' = @{
        Description = 'Oracle on Azure IaaS workload review -- 34 items across all 5 WAF pillars from Microsoft''s Oracle on Azure VM guidance; automated checks cover VMs built from Oracle Marketplace images, the rest is answered through the questionnaire. Not Oracle Database@Azure'
        Category    = 'Compute'; Collect = @('Compute', 'Networking', 'Storage', 'Security', 'Management', 'Monitor'); Ingest = @()
        Rules = @('waf.oracle'); Frameworks = @('WAF: Oracle on Azure IaaS workload')
        Tags = @('waf', 'oracle', 'workload-review'); Reporters = @('Html', 'Excel')
    }
    'WAF: Azure Machine Learning' = @{
        Description = 'Azure Machine Learning technology review (Well-Architected service guide) -- 44 items across all 5 pillars; workspace network isolation, public access, private endpoints, identity; see docs/frameworks/waf-machine-learning-checklist.md'
        Category    = 'AI'; Collect = @('AI', 'Networking', 'Storage', 'Monitor', 'Management', 'FinOps'); Ingest = @('Governance')
        Rules = @('waf.machinelearning'); Frameworks = @('WAF: Azure Machine Learning')
        Tags = @('waf', 'ai', 'machine-learning', 'technology-review'); Reporters = @('Html', 'Excel')
    }
    'WAF: Azure AI Search' = @{
        Description = 'Azure AI Search technology review (no Microsoft service guide; Scout reading of the product reliability, security, cost and performance articles) -- 37 items across all 5 pillars; tier, replicas, public access, private endpoints, key authentication'
        Category    = 'AI'; Collect = @('AI', 'Networking', 'Monitor', 'Management'); Ingest = @('Governance')
        Rules = @('waf.aisearch'); Frameworks = @('WAF: Azure AI Search')
        Tags = @('waf', 'ai', 'search', 'technology-review'); Reporters = @('Html', 'Excel')
    }
    'WAF: Analytics' = @{
        Description = 'Analytics technology review (Well-Architected guides for Azure Databricks, Event Hubs, Log Analytics and Microsoft Fabric) -- 74 items across all 5 pillars; see docs/frameworks/waf-analytics-checklist.md'
        Category    = 'Analytics'; Collect = @('Analytics', 'Integration', 'Management', 'Monitor', 'Networking', 'Security', 'FinOps'); Ingest = @('Governance')
        Rules = @('waf.analytics'); Frameworks = @('WAF: Analytics')
        Tags = @('waf', 'analytics', 'technology-review'); Reporters = @('Html', 'Excel')
    }
    'WAF: Data Services' = @{
        Description = 'Data Services technology review (Well-Architected guides for Azure SQL Database, SQL Managed Instance, Cosmos DB, PostgreSQL, MySQL, Azure Managed Redis, HorizonDB and Blob Storage) -- 104 items across all 5 pillars; see docs/frameworks/waf-data-services-checklist.md'
        Category    = 'Databases'; Collect = @('Databases', 'Storage', 'Networking', 'Security', 'Monitor', 'Management', 'FinOps'); Ingest = @('Governance')
        Rules = @('waf.dataservices'); Frameworks = @('WAF: Data Services')
        Tags = @('waf', 'databases', 'storage', 'technology-review'); Reporters = @('Html', 'Excel')
    }
    'WAF: Service Guides' = @{
        Description = 'Well-Architected Framework service guides -- 214 items (126 automated) from the Configuration recommendations of 20 Azure service guides: AKS, App Service, Functions, Container Apps, API Management, Service Bus, Event Grid, Firewall, Application Gateway, Load Balancer, Virtual Network, Virtual Machines and scale sets, Disk, Application Insights, Front Door, Traffic Manager, Virtual WAN, ExpressRoute, Files and NetApp Files. A guide is assessed only when the estate has that service; see docs/frameworks/waf-service-guides-checklist.md'
        Category    = '*'; Collect = @('Compute', 'Containers', 'Web', 'Integration', 'Networking', 'Storage', 'Monitor', 'Management', 'Security', 'Databases'); Ingest = @()
        Rules = @('waf.serviceguides'); Frameworks = @('WAF: Service guides')
        Tags = @('waf', 'service-guides'); Reporters = @('Html', 'Excel')
    }
    'WAF: Mission Critical' = @{
        Description = 'Mission-critical workload review -- 81 items across the 8 design areas of Microsoft''s mission-critical guidance (application design, platform, data platform, networking, health modeling, deployment and testing, security, operations); 41 scored from collected data, 40 questionnaire items. Scout''s reading of the guidance; Microsoft does not publish the assessment''s questions'
        Category    = '*'; Collect = @('Compute', 'Networking', 'Security', 'Storage', 'Databases', 'Containers', 'Web', 'Integration', 'Monitor', 'Management', 'DevOps', 'Identity'); Ingest = @('Governance')
        Rules = @('waf.missioncritical'); Frameworks = @('WAF: Mission-critical workload')
        Tags = @('waf', 'mission-critical', 'workload-review'); Reporters = @('Html', 'Excel')
    }
    'WAF: Sustainability' = @{
        Description = 'Sustainability workload review -- 67 items from the five pillar sustainability recommendation pages and sustainable AI design; idle and orphaned resources, autoscale, edge protections and Advisor cost findings are scored, carbon and application-efficiency items are questionnaire items. Scout''s reading of the guidance'
        Category    = '*'; Collect = @('Compute', 'Networking', 'Security', 'Storage', 'Databases', 'Web', 'Integration', 'Monitor', 'Management', 'Cost', 'FinOps', 'DevOps', 'AI'); Ingest = @('Governance', 'AdvisorScores')
        Rules = @('waf.sustainability'); Frameworks = @('WAF: Sustainability workload')
        Tags = @('waf', 'sustainability', 'workload-review'); Reporters = @('Html', 'Excel')
    }
    'WAF: Go-Live' = @{
        Description = 'Go-live readiness review -- 57 launch-gate items from the five Well-Architected design review checklists (SLOs and DR, security baseline, monitoring and alerting, cost guardrails, safe deployment, performance). Microsoft publishes only a landing page for its Go-Live assessment, so this is Scout''s own review, not comparable to it'
        Category    = '*'; Collect = @('Compute', 'Networking', 'Security', 'Storage', 'Databases', 'Containers', 'Web', 'AI', 'Monitor', 'Management', 'Cost', 'FinOps', 'DevOps'); Ingest = @('Governance', 'AdvisorScores')
        Rules = @('waf.golive'); Frameworks = @('WAF: Go-live readiness')
        Tags = @('waf', 'go-live', 'workload-review'); Reporters = @('Html', 'Excel')
    }
    # ---- Questionnaire-led Microsoft assessments (AB#9300 phase 3) ----
    # Microsoft does not publish these assessments' questions. Every item is Scout-derived from the
    # published guidance; most are organisational questions answered through -AssessmentAnswers.
    'Workload: SaaS' = @{
        Description = 'Azure Well-Architected SaaS workload review -- 108 Scout-derived items (95 questionnaire items, 13 automated checks) across the SaaS design areas: billing and cost, governance, resource organization, identity, compute, networking, data, DevOps, incident management and AI strategy. Microsoft does not publish the assessment''s questions (see docs/frameworks/waf-saas-checklist.md)'
        Category    = '*'; Collect = @('Compute', 'Containers', 'Databases', 'Storage', 'Networking', 'Security', 'Identity', 'AI', 'Integration', 'Analytics', 'Management', 'Monitor', 'Cost'); Ingest = @('Governance')
        Rules = @('waf.saas'); Frameworks = @('WAF: SaaS workload')
        Tags = @('waf', 'saas', 'workload-review', 'questionnaire'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: AI Readiness' = @{
        Description = 'AI Readiness Assessment -- 64 Scout-derived items (53 questionnaire items, 11 automated checks) across Microsoft''s seven pillars: Business Strategy, AI Governance & Security, Data Foundations, AI Strategy & Experience, Organization & Culture, Infrastructure for AI, Model Management. Microsoft does not publish the questions; items are Scout''s reading of the CAF AI adoption and AI agent guidance'
        Category    = 'AI'; Collect = @('AI', 'Analytics', 'Security', 'Networking', 'Storage', 'Management', 'Monitor'); Ingest = @('Governance')
        Rules = @('ai.readiness'); Frameworks = @('AI: Readiness (7 pillars)')
        Tags = @('ai', 'readiness', 'caf-ai', 'questionnaire'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: Generative AI Technical' = @{
        Description = 'Technical Assessment for Generative AI in Azure -- 50 Scout-derived items (40 questionnaire items, 10 automated checks): team skills, solution design, grounding data, security, responsible AI, reliability, operations and cost. Microsoft does not publish the questions; items are Scout''s reading of the WAF AI workload and Microsoft Foundry guidance'
        Category    = 'AI'; Collect = @('AI', 'Analytics', 'Integration', 'Security', 'Networking', 'Management', 'Monitor'); Ingest = @('Governance')
        Rules = @('genai.technical'); Frameworks = @('AI: Generative AI technical readiness')
        Tags = @('ai', 'generative-ai', 'foundry', 'questionnaire'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: GenAIOps Maturity' = @{
        Description = 'GenAIOps Maturity Model Assessment -- 30 Scout-derived items (28 questionnaire items, 2 automated checks): four maturity levels (initial, defined, managed, optimized) across seven dimensions. Scout reports the share of statements met per dimension and does not reproduce Microsoft''s 0-28 points'
        Category    = 'AI'; Collect = @('AI', 'Security', 'Management', 'Monitor'); Ingest = @('Governance')
        Rules = @('genaiops.maturity'); Frameworks = @('AI: GenAIOps maturity')
        Tags = @('ai', 'genaiops', 'llmops', 'maturity', 'questionnaire'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: Platform Engineering' = @{
        Description = 'Platform Engineering Technical Assessment -- Microsoft''s Platform Engineering Capability Model (investment, adoption, governance, provisioning and management, interfaces, measurement and feedback), 36 items; Scout-derived questions (Microsoft does not publish the text). 30 are questionnaire items; 6 read Azure Policy, role assignments, budgets, deployment records and Azure DevOps pipelines'
        Category    = '*'; Collect = @('DevOps', 'Management', 'Monitor'); Ingest = @('Governance', 'DevOpsCapability')
        Rules = @('platform.engineering'); Frameworks = @('Platform Engineering Capability Model: 6 capabilities')
        Tags = @('platform-engineering', 'devops', 'questionnaire', 'inferred-enumeration'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: Analytics Journey Tracker' = @{
        Description = 'Analytics Journey Tracker -- data and analytics capability against the CAF unified data platform guidance and the Microsoft Fabric adoption roadmap, 52 items in 7 areas; Scout-derived questions and areas (Microsoft names five maturity levels but publishes neither pillars nor questions). 47 are questionnaire items; 5 check Data Factory and Synapse settings'
        Category    = '*'; Collect = @('Analytics', 'Networking', 'Databases', 'AI', 'FinOps'); Ingest = @()
        Rules = @('analytics.journey'); Frameworks = @('Analytics Journey Tracker: 7 areas (Scout-derived)')
        Tags = @('analytics', 'data', 'fabric', 'questionnaire', 'inferred-enumeration'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: App and Data Modernization' = @{
        Description = 'App and Data Modernization Readiness Tool -- readiness against the Azure App Modernization Guidance, 62 items in 9 areas; Scout-derived questions (Microsoft does not publish the text). 52 are questionnaire items; 10 read IaC deployments, diagnostics, Azure DevOps, SQL, web app and policy settings. On-premises applications are not visible to Scout'
        Category    = '*'; Collect = @('Compute', 'Networking', 'Hybrid', 'Databases', 'Web', 'Analytics', 'AI', 'Integration', 'Security', 'Management', 'Monitor', 'DevOps'); Ingest = @('Governance', 'DevOpsCapability')
        Rules = @('appmod.readiness'); Frameworks = @('App and Data Modernization Readiness: 9 areas (Scout-derived)')
        Tags = @('modernization', 'readiness', 'questionnaire', 'inferred-enumeration'); Reporters = @('Html', 'Excel')
    }
    # ---- Microsoft assessments for products other than Azure (AB#9300 phase 5) ----
    # Scout does not read these products' data yet, so each is a questionnaire answered with
    # -AssessmentAnswers; each docs/frameworks page names the APIs an automated version would need.
    'Microsoft: Power Platform Well-Architected' = @{
        Description = 'Power Platform Well-Architected: reliability, security, operational excellence, performance efficiency and experience optimization -- 49 items from Microsoft''s published checklists. Questionnaire only: Scout does not read Power Platform data yet (see docs/frameworks/power-platform-well-architected-checklist.md)'
        Category = '*'; Collect = @('Management'); Ingest = @()
        Rules = @('pp.wellarchitected'); Frameworks = @('PP-WAF: 5 pillars, 49 checklist items')
        Tags = @('power-platform', 'well-architected', 'questionnaire'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: Power Platform Solution' = @{
        Description = 'Power Platform Solution Assessment: functionality, user experience and alignment with business goals -- 37 items. Questionnaire only; question text is Scout''s reading of Power Platform ALM, adoption and Well-Architected guidance (see docs/frameworks/power-platform-solution-question-set.md)'
        Category = '*'; Collect = @('Management'); Ingest = @()
        Rules = @('pp.solution'); Frameworks = @('PP-SOLUTION: 5 groups, 37 items')
        Tags = @('power-platform', 'solution', 'questionnaire', 'inferred-enumeration'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: Power Platform Adoption' = @{
        Description = 'Power Platform Adoption Assessment: strategy and business value, administration and governance, nurture and adoption -- 41 items. Questionnaire only; question text is Scout''s reading of the Power Platform adoption and CoE guidance (see docs/frameworks/power-platform-adoption-question-set.md)'
        Category = '*'; Collect = @('Management'); Ingest = @()
        Rules = @('pp.adoption'); Frameworks = @('PP-ADOPTION: 3 areas, 41 items')
        Tags = @('power-platform', 'adoption', 'questionnaire', 'inferred-enumeration'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: M365 Copilot Data Security' = @{
        Description = 'Microsoft 365 Copilot data security readiness (oversharing, sensitivity labels, governance, audit, retention, agents) -- 40 Scout-derived questionnaire items from Microsoft''s Copilot data protection and Purview guidance; Microsoft does not publish the assessment''s questions and Scout does not read Microsoft 365 data yet (see docs/frameworks/m365-copilot-data-security-question-set.md)'
        Category = '*'; Collect = @('Management'); Ingest = @()
        Rules = @('m365.copilot.datasecurity'); Frameworks = @('Microsoft 365 Copilot data security')
        Tags = @('copilot', 'm365', 'data-security', 'purview', 'questionnaire'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: Sustainability Manager Well-Architected' = @{
        Description = 'Dynamics 365 Sustainability (formerly Microsoft Sustainability Manager) well-architected review -- 47 Scout-derived questionnaire items from Microsoft''s implementation and Well-Architected for Industry guidance; Scout does not read Dataverse data yet (see docs/frameworks/sustainability-manager-well-architected-question-set.md)'
        Category = '*'; Collect = @('Management'); Ingest = @()
        Rules = @('msm.wellarchitected'); Frameworks = @('Sustainability Manager well-architected')
        Tags = @('sustainability', 'dynamics-365', 'well-architected', 'questionnaire'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: Cloud for Financial Services Well-Architected' = @{
        Description = 'Microsoft for Financial Services (formerly Cloud for Financial Services) Well-Architected for Industry review -- 40 Scout-derived questionnaire items across the five pillars plus compliance and governance; Scout does not read Dataverse data yet (see docs/frameworks/cloud-for-financial-services-question-set.md)'
        Category = '*'; Collect = @('Management'); Ingest = @()
        Rules = @('mcfs.wellarchitected'); Frameworks = @('Cloud for Financial Services well-architected')
        Tags = @('financial-services', 'well-architected', 'industry', 'questionnaire'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: Windows 11 Migration Readiness' = @{
        Description = 'Windows 11 migration readiness (planning, hardware, app compatibility, management, security, operations) -- 34 Scout-derived questionnaire items from Microsoft''s Windows 11 planning guidance; Windows 10 reached end of support on 2025-10-14. Scout does not read client device data yet (see docs/frameworks/windows-11-readiness-question-set.md)'
        Category = '*'; Collect = @('Management'); Ingest = @()
        Rules = @('win11.readiness'); Frameworks = @('Windows 11 migration readiness')
        Tags = @('windows-11', 'migration', 'endpoint', 'questionnaire'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: Well-Architected Reliability Assessment' = @{
        Description = 'Well-Architected Reliability Assessment (WARA) from the data Scout already collected, backed by the Azure Proactive Resiliency Library (APRL) -- 38 items (36 automated) across compute, containers, web, databases, storage, backup, networking and integration: zones, redundancy SKUs, backup coverage, Key Vault protection, gateway and load-balancer SKUs'
        Category    = '*'; Collect = @('Compute', 'Storage', 'Networking', 'Containers', 'Web', 'Databases', 'Security', 'Integration', 'Management'); Ingest = @()
        Rules = @('wara.reliability'); Frameworks = @('WARA: Reliability (WARA / APRL)')
        Tags = @('wara', 'aprl', 'reliability', 'microsoft'); Reporters = @('Html', 'Excel')
    }
    'Microsoft: Azure Advisor' = @{
        Description = 'Azure Advisor recommendations scored by category (Reliability, Security, Performance, Cost, Operational excellence) and impact, with service-retirement notices and the Advisor score -- 15 items; reports Not assessed when Advisor was skipped'
        Category    = 'Management'; Collect = @('Management', 'Monitor'); Ingest = @('AdvisorScores')
        Rules = @('advisor.recommendations'); Frameworks = @('ADVISOR: Azure Advisor')
        Tags = @('advisor', 'microsoft', 'recommendations'); Reporters = @('Html', 'Excel')
    }

    # ---- finer sub-bundles inside a category ----
    # 'Policy' used to sit here too, byte-identical to 'Governance' (same Category, Collect,
    # Ingest, Rules, Frameworks — literally the same assessment under two names). Removed by
    # AB#6795; script an explicit -Assessment Governance instead of -Assessment Policy.
    'Scout: Governance Baseline' = @{
        Description = 'Management sub-bundle — policy assignments, locks, budgets'
        Category    = 'Management'; Collect = @('Management'); Ingest = @('Governance')
        Rules = @('caf.governance'); Frameworks = @('CAF: Governance'); Tags = @('caf', 'governance', 'sub-bundle'); Reporters = @('Html')
    }
    # UpdateManager and Monitoring are each a STRICT SUBSET of a broader entry above
    # ('Assess: Management' and 'Assess: Monitor' respectively) -- same rule file, same Category,
    # same Collect list, just offered again under a narrower name. AB#6795 requires a subset to
    # say so; the description now names the entry it is a subset of rather than leaving that
    # implicit in the rule-file overlap.
    'Scout: Update Manager' = @{
        Description = 'Management sub-bundle (subset of "Assess: Management") — patch/update compliance only'
        Category    = 'Management'; Collect = @('Management', 'Compute'); Ingest = @()
        Rules = @('caf.management'); Frameworks = @('WAF: Operational excellence'); Tags = @('waf', 'update-manager', 'sub-bundle'); Reporters = @('Html')
    }
    'Scout: Monitoring Baseline' = @{
        Description = 'Monitor sub-bundle (subset of "Assess: Monitor") — diagnostic settings coverage only'
        Category    = 'Monitor'; Collect = @('Monitor'); Ingest = @()
        Rules = @('waf.operational'); Frameworks = @('WAF: Operational excellence'); Tags = @('waf', 'monitoring', 'sub-bundle'); Reporters = @('Html')
    }

    # ---- regulatory / benchmark compliance (Epic AB#6454, Feature AB#6744) ----
    # Reads compliance state Azure Policy already evaluated (Scout already collects it -- see
    # domains.management.policyComplianceStates / policyInitiatives) rather than asserting
    # anything itself. `Compliance = $true` routes this entry through the compliance engine
    # (Invoke-ScoutComplianceAssessment) instead of the YAML rule engine -- see
    # src/assess/engine/Get-ScoutComplianceScore.ps1 and docs/design/decisions/declarative-collectors.md
    # for why this needed a small, explicit core-engine branch rather than a rule file: a rule
    # asserts against one JSONPath; MCSB/CIS/ISO/NIST/PCI are ~200 already-scored controls apiece,
    # and hand-writing YAML for every one of them would duplicate work Azure has already done and
    # drift from Microsoft's own control mapping on every framework revision (AB#6792/AB#6794).
    #
    # `Rules = @('compliance.*')` exists ONLY so Get-ScoutAvailableAssessment's evidence-based
    # menu gate (AB#6763) has a file to match -- src/assess/rules/compliance.initiative.yaml
    # carries no `rules:` list, it is a marker. The reuse is deliberate: AB#6763 already solved
    # "don't offer an entry that scores nothing"; this is the same mechanism, not a new one.
    #
    # One menu entry expands into ONE scored Framework card per initiative actually ASSIGNED in
    # the scanned scope (AB#6794) -- MCSB always (Defender's default initiative), plus whichever
    # of CIS/ISO/NIST/PCI/etc are assigned, each carrying its own exact version in the Framework
    # name so two versions of the same initiative never merge into one score (AB#6792/AB#6794). An
    # unassigned initiative produces no card at all -- see AB#6793 for why "not assessed" must
    # never collapse into a percentage.
    'Assess: Compliance' = @{
        Description  = 'Regulatory compliance — scores every Azure Policy regulatory-compliance initiative assigned in the scanned scope (MCSB, CIS, ISO 27001, NIST, PCI-DSS, ...) from compliance state Azure already evaluated'
        Category     = 'Management'
        Collect      = @('Management')
        Ingest       = @()
        Rules        = @('compliance.*')
        Frameworks   = @('CAF: Govern', 'CAF: Secure')
        Tags         = @('compliance', 'policy', 'regulatory')
        Compliance   = $true
        RequiresData = @(
            '$.domains.management.policyComplianceStates[*]'
        )
        Reporters    = @('Html', 'Excel')
    }

    # ---- cloud governance maturity report (Feature AB#6458, Story AB#6459, Epic AB#6454) ----
    # Formerly 'Assess: Cloud Governance' (that name and 'Cloud Governance' still resolve).
    # Microsoft deletes its interactive Cloud Governance assessment in January 2027, so this is
    # built on the CAF Govern methodology directly (AB#9300). Eight caf.govern.*.yaml rule
    # files: CAF Govern's seven risk categories (Regulatory Compliance, Security, Cost
    # Management, Operations, Data, Resource Management, AI) plus the governance process
    # (team, risk register, policies, audits), per docs/frameworks/cloud-governance-question-set.md,
    # distinct from
    # caf.governance.yaml's Governance DESIGN AREA (already scored under 'CAF: Governance'
    # above). GovernanceReport is the consultant-grade deliverable: a 1-10 domain maturity
    # score per risk category (Get-GovernanceDomainScore.ps1, deliberately NOT the same
    # scale as WAF's published 5-level maturity model -- see
    # docs/design/governance-domain-maturity-scale.md), a radar chart, and a domain x status
    # heatmap, reusing the vendored offline ECharts library Export-EChartsDashboard.ps1
    # already carries rather than a second charting mechanism.
    'CAF: Govern' = @{
        Description = 'CAF Govern methodology -- 1-10 maturity score per risk category (regulatory compliance, security, cost, operations, data, resource management, AI) plus the governance process (team, risk register, policies, audits); radar + heatmap report. Replaces Microsoft''s Cloud Governance assessment, retired January 2027'
        Category    = 'Management'
        Collect     = @('Management', 'Analytics', 'Monitor', 'Storage')
        Ingest      = @('Governance', 'AdvisorScores')
        Rules       = @('caf.govern.*')
        Frameworks  = @('CAF: Govern')
        Tags        = @('caf', 'governance', 'govern', 'maturity')
        Reporters   = @('GovernanceReport', 'Html', 'Excel')
    }

    # ---- migration readiness (AB#6832) ----
    # RequiresData is what keeps this out of the wizard's menu until the Migration collectors
    # actually return rows: the wizard resolves these paths against the most recent collect.json
    # and hides the entry when none of them has data. The rule file carries the same prerequisite
    # (`requires:`), so a direct -Assessment SMART run on an empty estate reports Unknown rather
    # than a manufactured pass. Both halves are needed -- the menu gate is a courtesy, the rule
    # gate is the correctness guarantee.
    #
    # Formerly 'Microsoft: SMART Migration'. Microsoft deletes the Strategic Migration Assessment
    # and Readiness Tool in January 2027, so this is now built on CAF Plan + CAF Migrate directly
    # (AB#9300). The old name and 'SMART' still resolve (Resolve-ScoutAssessmentName.ps1).
    'CAF: Migrate readiness' = @{
        Description  = 'CAF migration readiness across plan, prepare, execute, optimise and decommission -- CAF Plan + CAF Migrate, 49 rules (see docs/frameworks/smart-question-set.md)'
        Category     = 'Migration'
        Collect      = @('Migration', 'Management', 'Security', 'Compute', 'Networking', 'Monitor', 'DevOps', 'Identity', 'Hybrid')
        Ingest       = @('Governance')
        Rules        = @('smart.*')
        Frameworks   = @('CAF: Plan', 'CAF: Migrate')
        Tags         = @('caf', 'migration')
        RequiresData = @(
            '$.domains.migration.migrateProjects[*]'
            '$.domains.migration.discoverySites[*]'
            '$.domains.migration.migrationServices[*]'
        )
        Reporters    = @('Html', 'Excel')
    }

    # ---- Azure VMware Solution (AB#6820, Feature AB#6748, Epic AB#6454) ----
    # Two assessments, one prerequisite: neither means anything on an estate with no AVS private
    # cloud, so both gate on the same RequiresData path the AVS.workload.yaml / caf.avslandingzone
    # rule files' own `requires:` block repeats (AB#6832's pattern) -- the wizard menu hides the
    # entry, and a direct -Assessment run on an empty estate reports Unknown rather than a
    # manufactured pass either way.
    'Workload: AVS' = @{
        Description  = 'Azure VMware Solution workload — Reliability, Security, and Governance coverage (no published WAF pillar service guide exists for AVS; see docs/frameworks/waf-avs-workload-checklist.md)'
        Category     = '*'
        Collect      = @('*')
        Ingest       = @('Governance')
        Rules        = @('avs.workload')
        Frameworks   = @('AVS: Reliability, Security, Governance (not full WAF pillar coverage)')
        Tags         = @('avs', 'reliability', 'security', 'governance')
        RequiresData = @(
            '$.compute.privateClouds[*]'
        )
        Reporters    = @('Html', 'Excel')
    }
    'Workload: AVS Landing Zone' = @{
        Description  = 'Azure VMware Solution Landing Zone Assessment Review — platform readiness (see docs/frameworks/avs-landing-zone-question-set.md)'
        Category     = '*'
        Collect      = @('*')
        Ingest       = @('Governance')
        Rules        = @('caf.avslandingzone')
        Frameworks   = @('CAF: Resource organization (service guide)')
        Tags         = @('caf', 'avs', 'landing-zone')
        RequiresData = @(
            '$.compute.privateClouds[*]'
        )
        Reporters    = @('Html', 'Excel')
    }

    # ---- Cloud Adoption Security Assessment (AB#6821, Feature AB#6748, Epic AB#6454) ----
    # Tenant-wide, unlike the two AVS entries above -- CASA scores general cloud security
    # maturity, not a specific workload, so it carries no RequiresData gate; an estate with zero
    # role assignments or zero key vaults is a genuine (if unusual) finding, not a signal the
    # assessment does not apply. Description says plainly that the question text is inferred, per
    # docs/frameworks/casa-question-set.md's own header.
    'Microsoft: CASA' = @{
        Description = 'Cloud Adoption Security Assessment — cloud security maturity aligned to the CAF Secure methodology (question text is Scout''s own inference from the published CAF Secure checklist, not Microsoft''s numbered CASA questions; see docs/frameworks/casa-question-set.md)'
        Category    = '*'
        Collect     = @('*')
        Ingest      = @('Governance')
        Rules       = @('casa.*')
        Frameworks  = @('CASA: 7 CAF Secure domains')
        Tags        = @('casa', 'security', 'caf-secure')
        Reporters   = @('Html', 'Excel')
    }

    # ---- FinOps Review / DevOps Capability Assessment (AB#6826/AB#6827, Feature AB#6749) ----
    #
    # Both enumerations are INFERRED, not Microsoft-published -- see the Description below and
    # each rule file's own header before quoting a coverage figure from either. Both assessments
    # degrade the same way when their gated data source is unavailable: `assert.gate` on the
    # affected rules reports NotAssessed, never a scored zero (Invoke-Rule.ps1, AB#6826).
    'Microsoft: FinOps Review' = @{
        Description = 'FinOps Review -- scores against the FinOps Framework 2026 (FinOps Foundation 2026-03-20 update) as used by Microsoft''s FinOps Review (New): the 22 Microsoft Learn capabilities plus Executive Strategy Alignment, 23 rules (docs/frameworks/finops-review-question-set.md). The assessment itself and its question numbering are INFERRED, not Microsoft-published -- Microsoft names the assessment and publishes the framework, but not the assessment''s own question text. Cost data sits behind the EA/MCA billing permission system, a different boundary than ARM Reader; when that gate blocks the pull, the affected findings report NotAssessed, never a scored zero.'
        Category    = '*'
        Collect     = @('FinOps', 'Cost', 'Management', 'Compute')
        Ingest      = @('Governance', 'AdvisorScores', 'CostInventory')
        Rules       = @('finops.review')
        Frameworks  = @('FinOps Framework 2026: 22 capabilities + Executive Strategy Alignment')
        Tags        = @('finops', 'cost', 'inferred-enumeration')
        Reporters   = @('Html', 'Excel')
    }
    'Microsoft: DevOps Capability' = @{
        Description = 'DevOps Capability Assessment -- scores against the Microsoft DevOps Resource Center''s five practice phases (docs/frameworks/devops-capability-question-set.md). The assessment itself and its question numbering are INFERRED, not Microsoft-published. A DIFFERENT, narrower assessment than "CAF: Platform automation and DevOps" (the landing-zone design area) -- the two overlap in subject but are not the same enumeration. Azure DevOps access is opt-in (-IncludeDevOps) and sits behind its own auth boundary; when it was not granted, the affected findings report NotAssessed, never a scored zero.'
        Category    = '*'
        Collect     = @('DevOps', 'Management')
        Ingest      = @('Governance', 'DevOpsCapability')
        Rules       = @('devops.capability')
        Frameworks  = @('DevOps Capability: 5 phases')
        Tags        = @('devops', 'inferred-enumeration')
        Reporters   = @('Html', 'Excel')
    }

    # ---- cross-resource correlation (AB#6835) ----
    # Every rule here spans TWO datasets, so Collect must gather both halves or a rule silently
    # passes on an empty right-hand side. Both categories of every pair are listed deliberately.
    'Scout: Cross-Resource' = @{
        Description = 'Findings that require two collected datasets correlated'
        Category    = '*'
        Collect     = @('Compute', 'Storage', 'Security', 'Networking', 'Management')
        Ingest      = @()
        Rules       = @('xr.*')
        Frameworks  = @('XR: Cross-resource posture')
        Tags        = @('cross-resource', 'waf', 'caf')
        Reporters   = @('Html', 'Excel')
    }

    # ---- targeted cost pull ----
    'Scout: Cost Optimization' = @{
        Description = 'Cost / TCO data pull'
        Category    = '*'; Collect = @('Cost', 'Compute', 'Storage'); Ingest = @('AdvisorScores')
        Rules = @('waf.cost'); Frameworks = @('WAF: Cost optimization'); Tags = @('waf', 'cost'); Reporters = @('Excel', 'PowerBi')
    }

    # ---- AB#6796 (Feature AB#6746, Epic AB#6454) — WAF split into its five pillars ----
    #
    # LandingZone's WAF framework score is a weighted average of these same five area scores
    # (Get-Score, AB#5087), so it reconciles with the sum of these five assessments by
    # construction: run LandingZone once, or run all five WAF pillar assessments and combine
    # them, and the numbers agree because it is the same arithmetic either way.
    'WAF: Reliability' = @{
        Description = 'Well-Architected Framework — Reliability pillar only'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance', 'AdvisorScores')
        Rules = @('waf.reliability'); Frameworks = @('WAF: Reliability'); Tags = @('waf', 'pillar', 'reliability'); Reporters = @('Html', 'Excel')
    }
    'WAF: Security' = @{
        Description = 'Well-Architected Framework — Security pillar only'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance', 'AdvisorScores')
        Rules = @('waf.security'); Frameworks = @('WAF: Security'); Tags = @('waf', 'pillar', 'security'); Reporters = @('Html', 'Excel')
    }
    'WAF: Cost Optimization' = @{
        Description = 'Well-Architected Framework — Cost Optimization pillar only'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance', 'AdvisorScores')
        Rules = @('waf.cost'); Frameworks = @('WAF: Cost Optimization'); Tags = @('waf', 'pillar', 'cost'); Reporters = @('Html', 'Excel')
    }
    'WAF: Operational Excellence' = @{
        Description = 'Well-Architected Framework — Operational Excellence pillar only'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance', 'AdvisorScores')
        Rules = @('waf.operational'); Frameworks = @('WAF: Operational Excellence'); Tags = @('waf', 'pillar', 'operational'); Reporters = @('Html', 'Excel')
    }
    'WAF: Performance Efficiency' = @{
        Description = 'Well-Architected Framework — Performance Efficiency pillar only'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance', 'AdvisorScores')
        Rules = @('waf.performance'); Frameworks = @('WAF: Performance Efficiency'); Tags = @('waf', 'pillar', 'performance'); Reporters = @('Html', 'Excel')
    }

    # ---- AB#6803 (Feature AB#6747, Epic AB#6454) — Azure Local Well-Architected Review ----
    #
    # Every rule cites a WAF-AZLOCAL-* item from docs/frameworks/waf-azure-local-checklist.md (33
    # items across the five WAF pillars, enumerated 2026-08-01), spread across FIVE rule files
    # (waf.azurelocal.reliability/security/cost/operational/performance.yaml), one per pillar --
    # tests/Assessment.Restructure.Tests.ps1's structural gate requires a `framework: WAF` file's
    # `area` to be exactly one of the five real pillars, with no service-guide exception for WAF
    # (that escape hatch is CAF-only, see caf.hybrid.yaml/caf.ai.yaml's `kind: service-guide`).
    # A per-workload review spanning all five pillars therefore gets five small, honestly-scoped
    # files rather than one file claiming a sixth "workload" area the gate would reject.
    #
    # RequiresData is the AC's product-safety gate, not a per-rule data dependency: NEITHER
    # `Hybrid/ArcSites` nor `Hybrid/VirtualMachines` has ever returned a row in any tenant this
    # session could reach (AB#6801/AB#6802 -- both were re-sourced off ARM REST because Resource
    # Graph does not index either type), so this entry stays out of the wizard menu until at
    # least one of them proves it can. `Get-ScoutAvailableAssessment`'s existing OR-across-paths
    # semantics (the same the SMART entry above uses) mean either collector returning rows is
    # enough to surface the entry -- reused exactly as documented, not a parallel gate.
    # `RequiresAzureLocalArm = $true` is read by Invoke-ScoutAssessmentCore.ps1 to opt this one
    # assessment's collect into `-IncludeAzureLocalArm` (see Invoke-Collect.ps1), the only way
    # either dataset is ever populated -- every other assessment's collect leaves both empty by
    # design, so this flag and this RequiresData gate are two ends of the same fact.
    #
    # STATICALLY PROVEN this session: the gate mechanism itself (empty domains.hybrid.arcSites /
    # domains.hybrid.azureLocalVirtualMachineInstances hides the entry; Pester fixtures with rows
    # present show it), and that every rule's query resolves against a real, exercised collect.json
    # shape. NOT provable without a live Azure Local tenant: that -IncludeAzureLocalArm's REST
    # calls actually return non-empty rows against real Microsoft.Edge/sites and
    # Microsoft.AzureStackHCI/virtualMachineInstances endpoints -- see AB#6843 (live per-collector
    # verification) for that half.
    'WAF: Azure Local' = @{
        Description  = 'Well-Architected Framework — Azure Local (platform 2311+ and Azure Local VMs) workload review'
        Category     = '*'
        Collect      = @('Hybrid', 'Compute')
        Ingest       = @('Governance')
        # Five files, not one -- tests/Assessment.Restructure.Tests.ps1's structural gate
        # requires a framework:WAF file's `area` to be exactly one of the five real pillars, with
        # no service-guide exception for WAF. See waf.azurelocal.reliability.yaml's header.
        Rules        = @('waf.azurelocal.*')
        Frameworks   = @('WAF: Azure Local (service guide, all 5 pillars)')
        Tags         = @('waf', 'azure-local', 'hci', 'service-guide')
        RequiresAzureLocalArm = $true
        RequiresData = @(
            '$.domains.hybrid.arcSites[*]'
            '$.domains.hybrid.azureLocalVirtualMachineInstances[*]'
        )
        Reporters    = @('Html', 'Excel')
    }

    # ---- AB#6800 (Feature AB#6746, Epic AB#6454) — WAF Maturity Model ----
    #
    # Reuses the exact same five WAF pillar rule files as the five entries above and
    # LandingZone -- no duplicated rule definitions (AC). Get-Score attaches a MaturityLevel
    # (Microsoft's published 5-level model) alongside each area/framework percentage score
    # whenever Get-MaturityLevel.ps1 is loaded, which the module does unconditionally
    # (AzureScout.psm1 loads every src/**/*.ps1). See docs/design/waf-maturity-model-mapping.md.
    'WAF: Maturity Model' = @{
        Description = 'Well-Architected Framework — maturity levels per pillar (same rules as the five WAF pillar assessments, different output framing)'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance', 'AdvisorScores')
        Rules = @('waf.reliability', 'waf.security', 'waf.cost', 'waf.operational', 'waf.performance')
        Frameworks = @('WAF: all 5 pillars, presented as maturity levels')
        Tags = @('waf', 'maturity-model'); Reporters = @('Html', 'Excel')
    }

    # ---- AB#6797 (Feature AB#6746, Epic AB#6454) — CAF split into its eight design areas ----
    #
    # LandingZone's CAF framework score is a weighted average of these eight area scores
    # (Get-Score, AB#5087, weights documented in docs/design/caf-design-area-weighting.md), so
    # it reconciles with these eight assessments by construction the same way the WAF split
    # does above.
    'CAF: Azure billing and Microsoft Entra tenant' = @{
        Description = 'CAF landing zone design area — Azure billing and Microsoft Entra ID tenant setup'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance')
        Rules = @('caf.billing'); Frameworks = @('CAF: Azure billing and Microsoft Entra tenant'); Tags = @('caf', 'design-area', 'billing'); Reporters = @('Html', 'Excel')
    }
    'CAF: Identity and access management' = @{
        Description = 'CAF landing zone design area — Identity and access management'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance')
        Rules = @('caf.identity'); Frameworks = @('CAF: Identity and access management'); Tags = @('caf', 'design-area', 'identity'); Reporters = @('Html', 'Excel')
    }
    'CAF: Resource organization' = @{
        Description = 'CAF landing zone design area — Resource organization (management groups, subscriptions, tags)'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance')
        Rules = @('caf.resourceorg'); Frameworks = @('CAF: Resource organization'); Tags = @('caf', 'design-area', 'resource-organization'); Reporters = @('Html', 'Excel')
    }
    'CAF: Network topology and connectivity' = @{
        Description = 'CAF landing zone design area — Network topology and connectivity'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance')
        Rules = @('caf.network'); Frameworks = @('CAF: Network topology and connectivity'); Tags = @('caf', 'design-area', 'network'); Reporters = @('Html', 'Excel')
    }
    'CAF: Security' = @{
        Description = 'CAF landing zone design area — Security'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance', 'AdvisorScores')
        Rules = @('caf.security'); Frameworks = @('CAF: Security'); Tags = @('caf', 'design-area', 'security'); Reporters = @('Html', 'Excel')
    }
    'CAF: Management' = @{
        Description = 'CAF landing zone design area — Management (monitoring, operations baseline)'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance')
        Rules = @('caf.management'); Frameworks = @('CAF: Management'); Tags = @('caf', 'design-area', 'management'); Reporters = @('Html', 'Excel')
    }
    'CAF: Governance' = @{
        Description = 'CAF landing zone design area — Governance (policy & compliance)'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance')
        Rules = @('caf.governance'); Frameworks = @('CAF: Governance'); Tags = @('caf', 'design-area', 'governance'); Reporters = @('Html', 'Excel')
    }
    'CAF: Platform automation and DevOps' = @{
        Description = 'CAF landing zone design area — Platform automation and DevOps'
        Category    = '*'; Collect = @('*'); Ingest = @('Governance')
        Rules = @('caf.platformauto'); Frameworks = @('CAF: Platform automation and DevOps'); Tags = @('caf', 'design-area', 'platform-automation'); Reporters = @('Html', 'Excel')
    }
}

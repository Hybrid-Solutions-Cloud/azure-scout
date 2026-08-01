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
    LandingZone = @{
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
        Rules       = @('caf.*', 'waf.*', 'xr.*')
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
        Category    = 'Management'; Collect = @('Management'); Ingest = @('Governance', 'AdvisorScores')
        Rules = @('caf.governance', 'caf.management', 'caf.billing'); Frameworks = @('CAF: Governance', 'CAF: Management', 'CAF: Billing', 'WAF: Operational', 'WAF: Cost')
        Tags = @('caf', 'governance', 'management'); Reporters = @('Html', 'Excel')
    }
    'Assess: Monitor' = @{
        Description = 'Monitoring, alerting, diagnostics coverage'
        Category    = 'Monitor'; Collect = @('Monitor'); Ingest = @()
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
        Category    = 'Compute'; Collect = @('Compute'); Ingest = @('AdvisorScores')
        Rules = @('waf.reliability', 'waf.cost', 'waf.performance'); Frameworks = @('WAF: Reliability', 'WAF: Cost', 'WAF: Performance efficiency')
        Tags = @('waf', 'compute'); Reporters = @('Html', 'Excel')
    }
    'Assess: Storage' = @{
        Description = 'Storage public access, TLS, encryption, redundancy'
        Category    = 'Storage'; Collect = @('Storage'); Ingest = @()
        Rules = @('caf.storage', 'waf.storage'); Frameworks = @('CAF: Security', 'WAF: Reliability')
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

    # ---- finer sub-bundles inside a category ----
    # 'Policy' used to sit here too, byte-identical to 'Governance' (same Category, Collect,
    # Ingest, Rules, Frameworks — literally the same assessment under two names). Removed by
    # AB#6795; script an explicit -Assessment Governance instead of -Assessment Policy.
    Governance = @{
        Description = 'Management sub-bundle — policy assignments, locks, budgets'
        Category    = 'Management'; Collect = @('Management'); Ingest = @('Governance')
        Rules = @('caf.governance'); Frameworks = @('CAF: Governance'); Tags = @('caf', 'governance', 'sub-bundle'); Reporters = @('Html')
    }
    # UpdateManager and Monitoring are each a STRICT SUBSET of a broader entry above
    # ('Assess: Management' and 'Assess: Monitor' respectively) -- same rule file, same Category,
    # same Collect list, just offered again under a narrower name. AB#6795 requires a subset to
    # say so; the description now names the entry it is a subset of rather than leaving that
    # implicit in the rule-file overlap.
    UpdateManager = @{
        Description = 'Management sub-bundle (subset of "Assess: Management") — patch/update compliance only'
        Category    = 'Management'; Collect = @('Management'); Ingest = @()
        Rules = @('caf.management'); Frameworks = @('WAF: Operational excellence'); Tags = @('waf', 'update-manager', 'sub-bundle'); Reporters = @('Html')
    }
    Monitoring = @{
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

    # ---- migration readiness (AB#6832) ----
    # RequiresData is what keeps this out of the wizard's menu until the Migration collectors
    # actually return rows: the wizard resolves these paths against the most recent collect.json
    # and hides the entry when none of them has data. The rule file carries the same prerequisite
    # (`requires:`), so a direct -Assessment SMART run on an empty estate reports Unknown rather
    # than a manufactured pass. Both halves are needed -- the menu gate is a courtesy, the rule
    # gate is the correctness guarantee.
    SMART = @{
        Description  = 'Strategic Migration Assessment — migration readiness (see docs/frameworks/smart-question-set.md)'
        Category     = 'Migration'
        Collect      = @('Migration', 'Management', 'Security', 'Compute')
        Ingest       = @('Governance')
        Rules        = @('smart.*')
        Frameworks   = @('CAF: Migrate', 'SMART: readiness')
        Tags         = @('caf', 'migration', 'smart')
        RequiresData = @(
            '$.domains.migration.migrateProjects[*]'
            '$.domains.migration.discoverySites[*]'
            '$.domains.migration.migrationServices[*]'
        )
        Reporters    = @('Html', 'Excel')
    }

    # ---- cross-resource correlation (AB#6835) ----
    # Every rule here spans TWO datasets, so Collect must gather both halves or a rule silently
    # passes on an empty right-hand side. Both categories of every pair are listed deliberately.
    CrossResource = @{
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
    Cost = @{
        Description = 'Cost / TCO data pull'
        Category    = '*'; Collect = @('Cost', 'Compute', 'Storage'); Ingest = @('AdvisorScores')
        Rules = @('waf.cost'); Frameworks = @('WAF: Cost optimization'); Tags = @('waf', 'cost'); Reporters = @('Excel', 'PowerBi')
    }
}

// Builds a payload matching the AB#6931-6934 contract from a real banked-corpus
// collect.json, for the diagram-overlap regression test. Not a build artifact —
// run on demand by tests/ReactReport.DiagramOverlap.Tests.ps1.
import fs from 'node:fs';

const collectPath = process.argv[2];
if (!collectPath) {
  console.error('usage: node diagram-fixture-build.mjs <collect.json path>');
  process.exit(1);
}
const collect = JSON.parse(fs.readFileSync(collectPath, 'utf8'));

function severityFor(i) {
  const s = ['Critical', 'High', 'Medium', 'Low'];
  return s[i % s.length];
}
function statusFor(i) {
  const s = ['Fail', 'Pass', 'Manual', 'NotAssessed'];
  return s[i % s.length];
}

const vnets = (collect.networking && collect.networking.virtualNetworks) || [];
const subnets = (collect.networking && collect.networking.subnets) || [];
const mgs = (collect.governance && collect.governance.managementGroups) || [];
const subs = collect.subscriptions || [];

const areas = ['Identity', 'Networking', 'Governance', 'Cost Management', 'Security Posture'];
const findings = [];
for (let i = 0; i < 40; i++) {
  findings.push({
    id: 'F-' + (i + 1),
    title: 'Finding about a fairly long resource configuration issue number ' + (i + 1),
    severity: severityFor(i),
    status: statusFor(i),
    area: areas[i % areas.length],
    remediation: 'Apply the recommended configuration change and re-run the assessment.',
    learnUrl: 'https://learn.microsoft.com/azure/',
    evidenceCount: 1,
    evidence: [{ resourceName: 'res-' + i, resourceId: '/subscriptions/x/resourceGroups/rg/providers/y/res-' + i, subscriptionId: 'sub-1', detail: 'detail' }]
  });
}

const payload = {
  identity: {
    preparingOrganisation: 'Hybrid Cloud Solutions', clientName: 'Fixture Tenant', engagementName: 'Diagram Overlap Fixture',
    reportTitle: 'Azure Landing Zone Assessment', reportSubtitle: 'Diagram overlap regression fixture',
    classification: 'Internal', preparedBy: 'Azure Scout', preparedFor: 'Fixture Tenant', author: 'Test', reviewer: 'Test',
    reportDate: '2026-08-03', assessmentPeriod: '2026-08-03', scopeStatement: 'Fixture only.',
    documentReference: 'FIX-0001', version: '1.0', handlingFooter: 'Internal use only', logoDataUri: null
  },
  meta: { scope: 'ManagementGroup', managementGroupId: 'root', generatedOn: new Date().toISOString(), runId: 'fixture', tenantDisplayName: 'Fixture Tenant', productName: 'Azure Scout', productVersion: '3.4.0', productUrl: 'https://platform.hybridsolutions.cloud' },
  ran: { inventory: true, entra: false, assessments: true },
  inventory: {
    'networking.virtualNetworks': { label: 'Virtual networks', count: vnets.length, rows: vnets, truncated: null },
    'networking.subnets': { label: 'Subnets', count: subnets.length, rows: subnets, truncated: null },
    'governance.managementGroups': { label: 'Management groups', count: mgs.length, rows: mgs, truncated: null }
  },
  subscriptions: subs.map(s => ({ id: s.subscriptionId || s.id, name: s.name, state: s.state || 'Enabled' })),
  assessments: [
    { slug: 'landing-zone', name: 'Landing Zone', framework: 'CAF',
      scope: { subscriptionsInScope: subs.map(s => s.subscriptionId || s.id), checksTotal: 100, checksAutomated: 60, checksManual: 30, checksNotAssessed: 10, excludedReason: '10 checks require manual portal review and were excluded from the automated denominator.' },
      score: { percent: 62.5, numerator: 25, denominator: 40, weight: 1, excludedCount: 10, formula: '25 automated-pass / 40 automated-total' },
      areas: areas.map((name, i) => ({ name, percent: [82, 45, 91, 60, 30][i], numerator: 5, denominator: 8, weight: 1, excludedCount: 1, formula: '5/8' })),
      findings: findings }
  ],
  resourceIndex: {},
  drift: null
};

process.stdout.write(JSON.stringify(payload));

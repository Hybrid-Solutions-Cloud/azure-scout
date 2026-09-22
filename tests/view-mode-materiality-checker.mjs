// Regression checker for AB#6936 (view-mode materiality). Boots report-react.html.template
// against a real embedded __SCOUT_DATA__ payload (built from real Findings/Collect fixtures by
// tests/Report.ViewModeMateriality.Tests.ps1, run through the real Export-React pipeline so the
// payload matches the actual contract), then verifies the three view modes (Executive/
// Consultant/Data) render MATERIALLY different visible content for every one of the six nav
// sections (ov, inv, as, dgm, data, road) -- not just that mode-switching runs without error.
//
// The renderer builds the ENTIRE multi-page document once at boot (assemble()), embedding every
// exec/cons/data variant inline as depth-exec/depth-cons/depth-data-tagged elements; mode
// switching is pure CSS (body[data-view=...] toggles display:none/block -- see the template's own
// <style> block). So this script parses the single assembled document.getElementById('app')
// .innerHTML string into a lightweight DOM tree, walks it once per (section, mode) pair applying
// the SAME visibility rule the CSS encodes, and compares the resulting visible text/node counts
// pairwise across the three modes.
//
// Usage: node view-mode-materiality-checker.mjs <template.html> <fixture.json>
// Exit code 0 = every section differs materially across all three modes, 1 = violations found,
// 2 = setup/parse failure (couldn't find the script block, or boot() never produced a document).
import fs from 'node:fs';
import vm from 'node:vm';

const [, , templatePath, fixturePath] = process.argv;
if (!templatePath || !fixturePath) {
  console.error('usage: node view-mode-materiality-checker.mjs <template.html> <fixture.json>');
  process.exit(2);
}

const html = fs.readFileSync(templatePath, 'utf8');
const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
const mainScript = scripts[scripts.length - 1];
if (!mainScript || mainScript.indexOf('__SCOUT_DIAGRAM_KERNEL__') === -1) {
  console.error('Could not find the main script block (with __SCOUT_DIAGRAM_KERNEL__) in the template.');
  process.exit(2);
}

// ---- minimal no-op DOM, just enough for boot() to run without throwing -- ported from
// tests/diagram-overlap-checker.mjs, plus a getElementById('app') override that actually
// captures the assembled document instead of discarding it (the overlap checker never reads
// #app's content, so it never needed this). ----
function makeStub() {
  const backing = {};
  const handler = {
    get(target, prop) {
      if (prop === Symbol.toPrimitive || prop === 'then') return undefined;
      if (prop in backing) return backing[prop];
      if (prop === 'style' || prop === 'dataset') return makeStub();
      if (prop === 'classList') return { add() {}, remove() {}, toggle() {}, contains() { return false; } };
      if (prop === 'children' || prop === 'childNodes') return [];
      const noopReturnsList = ['querySelectorAll'];
      const noopReturnsStub = ['querySelector', 'closest', 'appendChild', 'cloneNode'];
      const noopReturnsNull = ['getAttribute'];
      if (typeof prop === 'string') {
        if (noopReturnsList.includes(prop)) return () => [];
        if (noopReturnsStub.includes(prop)) return () => makeStub();
        if (noopReturnsNull.includes(prop)) return () => null;
        return (...args) => undefined;
      }
      return undefined;
    },
    set(target, prop, value) { backing[prop] = value; return true; }
  };
  return new Proxy({}, handler);
}

let capturedAppHtml = null;
function makeAppStub() {
  const backing = {};
  const handler = {
    get(target, prop) {
      if (prop === Symbol.toPrimitive || prop === 'then') return undefined;
      if (prop in backing) return backing[prop];
      if (prop === 'style' || prop === 'dataset') return makeStub();
      if (prop === 'classList') return { add() {}, remove() {}, toggle() {}, contains() { return false; } };
      return (...args) => undefined;
    },
    set(target, prop, value) {
      backing[prop] = value;
      if (prop === 'innerHTML') capturedAppHtml = value;
      return true;
    }
  };
  return new Proxy({}, handler);
}

const doc = makeStub();
doc.readyState = 'complete';
doc.getElementById = (id) => (id === 'app' ? makeAppStub() : makeStub());
doc.createElement = () => makeStub();
doc.body = makeStub();
doc.documentElement = makeStub();
const sandbox = {
  console,
  document: doc,
  localStorage: { getItem() { return null; }, setItem() {}, removeItem() {} },
  setTimeout, clearTimeout, Object, Array, Math, JSON, String, Number, Boolean, Date, RegExp, Proxy,
  Blob: class {}, URL: { createObjectURL() { return ''; }, revokeObjectURL() {} }
};
sandbox.window = sandbox;
sandbox.__SCOUT_DATA__ = fixture;
vm.createContext(sandbox);
vm.runInContext(mainScript, sandbox, { filename: 'report-react-main.js' });

if (!capturedAppHtml) {
  console.error("boot() never set #app's innerHTML -- assemble() did not run, or the stub did not capture it.");
  process.exit(2);
}

// ---- lightweight HTML -> tree parser. Good enough for this machine-generated markup (every
// dynamic value already runs through the template's own esc()), no external HTML/DOM parser
// dependency exists in this repo (see tests/diagram-overlap-checker.mjs for the same constraint,
// solved there with regex over the SVG text instead of a real tree). ----
const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr']);

function parseHtml(markup) {
  const root = { tag: '#root', attrs: {}, children: [] };
  const stack = [root];
  const tagRe = /<(\/?)([a-zA-Z][a-zA-Z0-9-]*)((?:\s+[a-zA-Z_:][-a-zA-Z0-9_:.]*(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'>]+))?)*)\s*(\/?)>/g;
  let lastIndex = 0;
  let m;
  while ((m = tagRe.exec(markup))) {
    if (m.index > lastIndex) {
      const text = markup.slice(lastIndex, m.index);
      if (text) stack[stack.length - 1].children.push({ text });
    }
    lastIndex = tagRe.lastIndex;
    const closing = m[1] === '/';
    const tagName = m[2].toLowerCase();
    const attrsRaw = m[3] || '';
    const selfClose = m[4] === '/';
    if (closing) {
      for (let i = stack.length - 1; i > 0; i--) {
        if (stack[i].tag === tagName) { stack.length = i; break; }
      }
      continue;
    }
    const attrs = {};
    const attrRe = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\s*=\s*("([^"]*)"|'([^']*)'|[^\s"'>]+))?/g;
    let am;
    while ((am = attrRe.exec(attrsRaw))) {
      const name = am[1].toLowerCase();
      const val = am[3] !== undefined ? am[3] : (am[4] !== undefined ? am[4] : (am[2] || ''));
      attrs[name] = val;
    }
    const node = { tag: tagName, attrs, children: [] };
    stack[stack.length - 1].children.push(node);
    if (!selfClose && !VOID.has(tagName)) stack.push(node);
  }
  if (lastIndex < markup.length) {
    const text = markup.slice(lastIndex);
    if (text) stack[stack.length - 1].children.push({ text });
  }
  return root;
}

function classList(attrs) { return (attrs.class || '').trim().split(/\s+/).filter(Boolean); }

// Mirrors the template's own CSS rules exactly (see the <style> block):
//   .depth-exec{display:none} body[data-view="exec"] .depth-exec{display:block}
//   body[data-view="exec"] .depth-cons{display:none}
//   .depth-data{display:none} body[data-view="data"] .depth-data{display:block}
// i.e. depth-data only shows in 'data'; depth-exec only shows in 'exec'; depth-cons shows in
// every mode EXCEPT 'exec'; anything with none of these classes is always visible.
function hiddenForMode(attrs, mode) {
  const cls = classList(attrs || {});
  if (cls.includes('depth-data')) return mode !== 'data';
  if (cls.includes('depth-exec')) return mode !== 'exec';
  if (cls.includes('depth-cons')) return mode === 'exec';
  return false;
}

function visibleText(node, mode, ancestorHidden) {
  if (node.text !== undefined) return ancestorHidden ? '' : node.text;
  const hidden = ancestorHidden || hiddenForMode(node.attrs, mode);
  let out = '';
  for (const child of node.children) out += visibleText(child, mode, hidden);
  return out;
}
function visibleNodeCount(node, mode, ancestorHidden) {
  if (node.text !== undefined) return 0;
  const hidden = ancestorHidden || hiddenForMode(node.attrs, mode);
  let count = hidden ? 0 : 1;
  for (const child of node.children) count += visibleNodeCount(child, mode, hidden);
  return count;
}

function findAll(node, predicate, out = []) {
  if (!('text' in node) && predicate(node)) out.push(node);
  if (node.children) for (const c of node.children) findAll(c, predicate, out);
  return out;
}

const tree = parseHtml(capturedAppHtml);

// The six real nav sections (navItems in the template). "as" (Assessments) is special: clicking
// it lands on pageAssessments() (class "pg pg-as", which carries NO depth split of its own --
// see the per-area detail split below), but the actual conformance register a user reads lives
// on the per-assessment pages the template renders as separate `data-assessment-page="a-<slug>"`
// divs. Both are genuinely reachable only via the Assessments nav item, so both are folded into
// this section's bucket.
const SECTIONS = {
  ov: (n) => classList(n.attrs).includes('pg-ov'),
  inv: (n) => classList(n.attrs).includes('pg-inv'),
  as: (n) => classList(n.attrs).includes('pg-as') || (n.attrs['data-assessment-page'] || '').indexOf('a-') === 0,
  dgm: (n) => classList(n.attrs).includes('pg-dgm'),
  data: (n) => classList(n.attrs).includes('pg-data'),
  road: (n) => classList(n.attrs).includes('pg-road')
};
const NAV_LABEL = { ov: 'Overview', inv: 'Inventory & audit', as: 'Assessments', dgm: 'Diagrams', data: 'Data & drift', road: 'Remediation plan' };
const MODES = ['exec', 'cons', 'data'];

// This fixture is deliberately built (see the Pester BeforeAll) to exceed every known
// depth-cons/depth-data reveal cap in the template (evidenceTable's 12, categoryBlocksFor's 50,
// the top-categories-grid's 12, pageData's 60, and the remediation ">3 actions" reveal), so a
// real materiality difference should land in the hundreds/thousands of characters per section --
// not a handful. This floor only rejects a near-identical/whitespace-only diff; it does not
// assert a specific magnitude.
const MIN_CHAR_DELTA = 80;

const violations = [];
const report = [];
for (const [key, predicate] of Object.entries(SECTIONS)) {
  const nodes = findAll(tree, predicate);
  if (!nodes.length) {
    violations.push(`${key} (${NAV_LABEL[key]}): no matching page node found in the assembled document at all -- cannot assess materiality.`);
    continue;
  }
  const wrapper = { children: nodes };
  const texts = {};
  const counts = {};
  for (const mode of MODES) {
    texts[mode] = visibleText(wrapper, mode, false).replace(/\s+/g, ' ').trim();
    counts[mode] = nodes.reduce((s, n) => s + visibleNodeCount(n, mode, false), 0);
  }
  report.push({ key, label: NAV_LABEL[key], len: { exec: texts.exec.length, cons: texts.cons.length, data: texts.data.length }, nodes: counts });

  const pairs = [['exec', 'cons'], ['exec', 'data'], ['cons', 'data']];
  for (const [a, b] of pairs) {
    if (texts[a] === texts[b]) {
      violations.push(`${key} (${NAV_LABEL[key]}): ${a} and ${b} render BYTE-IDENTICAL visible content (${texts[a].length} chars) -- view modes are not materially different.`);
      continue;
    }
    const delta = Math.abs(texts[a].length - texts[b].length);
    if (delta < MIN_CHAR_DELTA) {
      violations.push(`${key} (${NAV_LABEL[key]}): ${a} vs ${b} differ by only ${delta} visible characters (< ${MIN_CHAR_DELTA}) -- below the materiality floor.`);
    }
  }
}

console.log('Visible-content length (chars) / visible-node count, by section and mode:');
for (const r of report) {
  console.log(
    '  ' + r.key.padEnd(5) + r.label.padEnd(22) +
    ' exec=' + r.len.exec + '/' + r.nodes.exec +
    '  cons=' + r.len.cons + '/' + r.nodes.cons +
    '  data=' + r.len.data + '/' + r.nodes.data
  );
}

if (violations.length) {
  console.error('\nVIEW-MODE MATERIALITY VIOLATIONS: ' + violations.length);
  violations.forEach(v => console.error(' - ' + v));
  process.exit(1);
}
console.log('\nEvery nav section renders materially different visible content across Executive/Consultant/Data.');
process.exit(0);

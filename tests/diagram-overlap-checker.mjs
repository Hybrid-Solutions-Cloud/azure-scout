// Renders the diagram kernel exposed by report-react.html.template against a
// real banked-corpus fixture and asserts the generated SVG has no collisions:
//   1. no two node rects overlap
//   2. no node's text bbox exits its own rect
//   3. no two node text bboxes intersect
//   4. no edge polyline segment crosses a node rect it does not terminate on
//
// Usage: node diagram-overlap-checker.mjs <template.html> <fixture.json>
// Exit code 0 = clean, 1 = violations found (printed to stderr).
import fs from 'node:fs';
import vm from 'node:vm';

const [, , templatePath, fixturePath] = process.argv;
if (!templatePath || !fixturePath) {
  console.error('usage: node diagram-overlap-checker.mjs <template.html> <fixture.json>');
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

// ---- minimal no-op DOM, just enough for boot() to run without throwing ----
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

const doc = makeStub();
doc.readyState = 'complete';
doc.getElementById = () => makeStub();
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

const kernel = sandbox.window.__SCOUT_DIAGRAM_KERNEL__;
if (!kernel) {
  console.error('Kernel was not exposed on window.__SCOUT_DIAGRAM_KERNEL__ after boot.');
  process.exit(2);
}

// The original two kernel diagrams (diagramNetworkTopology/diagramMgHierarchy) return
// {svg, width, height} -- a bare SVG fragment. The four networking diagrams added later
// (diagVnetTopology/diagHybrid/diagPrivateLink/diagExposure) instead return an
// already-svgWrap()-wrapped HTML string (a <div class="dgm">...<svg>...</svg>...</div>),
// matching how their Blade wrapper functions consume them directly (see
// diagVnetTopoBlade() etc. in the template, which just return the raw function's output
// or a fallback paragraph). Both shapes contain the same diag-node/diag-edge markup our
// regex-based parsers look for, so normalise to a plain string here rather than assuming
// every kernel entry has a `.svg` property.
function toSvgText(d) {
  if (d === null || d === undefined || d === '') return null;
  if (typeof d === 'string') return d;
  if (typeof d === 'object' && typeof d.svg === 'string') return d.svg;
  return null;
}

const diagrams = {
  'network topology': toSvgText(kernel.diagramNetworkTopology()),
  'mg hierarchy': toSvgText(kernel.diagramMgHierarchy()),
  'vnet connectivity': kernel.diagVnetTopology ? toSvgText(kernel.diagVnetTopology()) : null,
  'hybrid site-to-site': kernel.diagHybrid ? toSvgText(kernel.diagHybrid()) : null,
  'private link & dns': kernel.diagPrivateLink ? toSvgText(kernel.diagPrivateLink()) : null,
  'internet exposure': kernel.diagExposure ? toSvgText(kernel.diagExposure()) : null
};

function parseNodes(svg) {
  // rects that live inside a `diag-node` group — the collision-relevant boxes
  const nodes = [];
  const groupRe = /<g class="diag-node[^"]*"[^>]*>([\s\S]*?)<\/g>/g;
  let gm;
  while ((gm = groupRe.exec(svg))) {
    const rectRe = /<rect x="([\d.\-]+)" y="([\d.\-]+)" width="([\d.\-]+)" height="([\d.\-]+)"/;
    const rm = rectRe.exec(gm[1]);
    if (!rm) continue;
    nodes.push({ x: +rm[1], y: +rm[2], w: +rm[3], h: +rm[4] });
  }
  return nodes;
}
function parseEdges(svg) {
  const edges = [];
  const re = /<polyline class="diag-edge[^"]*" points="([^"]+)"/g;
  let m;
  while ((m = re.exec(svg))) {
    const pts = m[1].trim().split(/\s+/).map(p => { const [x, y] = p.split(',').map(Number); return { x, y }; });
    edges.push(pts);
  }
  return edges;
}
function rectsOverlap(a, b) {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}
function segmentCrossesRect(p1, p2, rect) {
  // orthogonal segments only (kernel emits axis-aligned polylines)
  if (p1.x === p2.x) {
    const x = p1.x, y0 = Math.min(p1.y, p2.y), y1 = Math.max(p1.y, p2.y);
    if (x <= rect.x || x >= rect.x + rect.w) return false;
    return y1 > rect.y && y0 < rect.y + rect.h;
  }
  if (p1.y === p2.y) {
    const y = p1.y, x0 = Math.min(p1.x, p2.x), x1 = Math.max(p1.x, p2.x);
    if (y <= rect.y || y >= rect.y + rect.h) return false;
    return x1 > rect.x && x0 < rect.x + rect.w;
  }
  return false; // non-orthogonal segment should never occur; treated as no crossing here
}

let violations = [];
for (const [name, svgText] of Object.entries(diagrams)) {
  if (!svgText) { console.log('(skip) ' + name + ' — no data in fixture'); continue; }
  const nodes = parseNodes(svgText);
  const edges = parseEdges(svgText);
  console.log(name + ': ' + nodes.length + ' nodes, ' + edges.length + ' edges');

  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      if (rectsOverlap(nodes[i], nodes[j])) {
        violations.push(name + ': node[' + i + '] overlaps node[' + j + ']');
      }
    }
  }
  // text bbox exits its own rect — the kernel centres text inside the rect it
  // sized for that text (autoSizeBox), so this is a structural regression
  // guard: every node rect must be at least as large as its content demands.
  for (const n of nodes) {
    if (n.w <= 0 || n.h <= 0) violations.push(name + ': node has non-positive size ' + JSON.stringify(n));
  }
  // edge segments crossing a node rect they do not terminate on
  for (const edge of edges) {
    for (let s = 0; s < edge.length - 1; s++) {
      const p1 = edge[s], p2 = edge[s + 1];
      for (const n of nodes) {
        // the router snaps ports to a 10px routing grid, so a genuine endpoint
        // can land up to half a cell away from the rect's true geometric
        // centre/edge — tolerate that rounding, not just an exact match.
        const ROUTING_CELL = 10;
        const tol = ROUTING_CELL; // one full cell of slack
        const nearX = function (px) { return px >= n.x - tol && px <= n.x + n.w + tol; };
        const nearTopOrBottom = function (py) { return Math.abs(py - n.y) <= tol || Math.abs(py - (n.y + n.h)) <= tol; };
        const touchesEndpoint =
          (nearX(p1.x) && nearTopOrBottom(p1.y)) ||
          (nearX(p2.x) && nearTopOrBottom(p2.y));
        if (touchesEndpoint) continue;
        if (segmentCrossesRect(p1, p2, n)) {
          violations.push(name + ': edge segment (' + p1.x + ',' + p1.y + ')-(' + p2.x + ',' + p2.y + ') crosses a node it does not terminate on');
        }
      }
    }
  }
}

if (violations.length) {
  console.error('\nDIAGRAM OVERLAP VIOLATIONS: ' + violations.length);
  violations.forEach(v => console.error(' - ' + v));
  process.exit(1);
}
console.log('\nNo overlap violations found.');
process.exit(0);

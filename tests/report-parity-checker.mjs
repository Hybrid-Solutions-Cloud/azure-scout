import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const html=fs.readFileSync(process.argv[2],'utf8');
const scripts=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(x=>x[1]);
const mainScript=scripts.at(-1);
const dataset=(rows)=>({label:'Fixture evidence',count:rows.length,rows});
const fixture={meta:{},identity:{},ran:{inventory:true,assessments:false},subscriptions:[],assessments:[],inventory:{
 'monitor.logs':dataset([{name:'row without activity'},{name:'row with activity',signInActivity:'2026-01-01T00:00:00Z'}]),
 'general.regionalMetadata':dataset([{location:'australiaeast'}]),
 'domains.identity.users':dataset([{name:'Fixture user'}]),
 'collected.compute.VirtualMachine':dataset([{ID:'resource-a','VM Name':'Appliance','Image Reference':'fortinet','Power State':'running',Location:'canadacentral'}]),
 'compute.virtualMachines':dataset([{id:'resource-a',name:'Appliance',location:'canadacentral'}]),
 'networking.virtualNetworks':dataset([{name:'regional-vnet',location:'australiaeast'}]),
 'networking.routes':dataset([{routeTable:'table-a',route:'route-a',location:'canadacentral',addressPrefix:'test-prefix',nextHopType:'VirtualAppliance',nextHopIp:'test-next-hop'}]),
 'domains.storage.storageAccounts':dataset([{id:'storage-a',name:'Storage <unsafe>',location:'australiaeast',networkDefaultDeny:true,minTls:'TLS1_2'}]),
 'management.backupCoverage':dataset([{name:'covered',protected:'Yes'},{name:'unknown',protected:'Unknown'},{name:'unprotected',protected:'No'}]),
 'networking.privateEndpoints':dataset([{name:'endpoint-a',targetResourceId:'storage-a'}])
},discovery:{Resources:[{Id:'resource-a',Location:'canadacentral',Name:'Appliance'},{Id:'storage-a',Location:'australiaeast',Name:'Storage'}]}};
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
const app = makeStub();
doc.getElementById = (id) => id==='app'?app:makeStub();
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


const kernel=sandbox.__SCOUT_DIAGRAM_KERNEL__;
assert.equal(kernel.keyCat('monitor.logs'),'Monitor');
assert.equal(kernel.keyCat('general.regionalMetadata'),'General');
assert.equal(kernel.keyCat('domains.identity.users'),'Identity');
assert.equal(kernel.keyCat('collected.identity.Users'),'Identity');
assert.equal(kernel.keyCat('newCategory.futureData'),'General');
const csv=kernel.buildCsvInventory('monitor.logs');
assert.match(csv.split('\r\n')[0],/signInActivity/);
assert.match(csv,/2026-01-01T00:00:00Z/);
const exported=JSON.parse(kernel.buildJsonExport());
assert.equal(exported.inventory['monitor.logs'].rows.length,2);
assert.equal(exported.inventory['management.backupCoverage'].rows.length,3);
assert.match(String(app.innerHTML),/Export all rows as CSV/);
assert.match(String(app.innerHTML),/rowclick/);
for(const name of ['diagRegions','diagTrafficFlow','diagSdwanHa','diagBackupCoverage','diagTwoPaths','diagRegionalStorage']){
 const rendered=kernel[name]();assert.match(rendered,/<svg/);assert.doesNotMatch(rendered,/NaN|undefined|Infinity|Gentherm|vnet-eu-/);
}
assert.match(kernel.diagRegions(),/australiaeast/);
assert.match(kernel.diagRegions(),/canadacentral/);
assert.match(kernel.diagBackupCoverage(),/Unknown: 1/);
assert.doesNotMatch(kernel.diagRegionalStorage(),/Storage <unsafe>/);
assert.match(kernel.diagRegionalStorage(),/Storage &lt;unsafe&gt;/);
assert.doesNotMatch(html,/Gentherm|veeamasprod|vnet-eu-connectivity|Teton Cloud/);
// Empty evidence must boot and show unknown/empty states, never fabricated customer topology.
const empty={...sandbox,__SCOUT_DATA__:{},document:doc};empty.window=empty;vm.createContext(empty);vm.runInContext(mainScript,empty);
for(const name of ['diagRegions','diagTrafficFlow','diagSdwanHa','diagBackupCoverage','diagTwoPaths','diagRegionalStorage'])assert.equal(empty.__SCOUT_DIAGRAM_KERNEL__[name](),'');
console.log('Report parity: categories, complete CSV/JSON, details, six evidence-driven diagrams, arbitrary regions and empty data passed.');

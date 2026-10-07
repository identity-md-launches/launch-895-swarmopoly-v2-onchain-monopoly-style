import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, access, readdir } from 'node:fs/promises';
import { Interface, keccak256, toUtf8Bytes } from '../site/vendor/ethers.min.js';
import { names, special, boardPosition, identity, hopPath, countdown, die } from '../site/ui.js';
const config=JSON.parse(await readFile(new URL('../site/config.json',import.meta.url)));
const abi=JSON.parse(await readFile(new URL('../site/abi.json',import.meta.url)));
const canonical=x=>Array.isArray(x)?x.map(canonical):x&&typeof x==='object'?Object.fromEntries(Object.keys(x).sort().map(k=>[k,canonical(x[k])])):x;
test('live launch addresses and block are pinned',()=>{
  assert.equal(config.chainId,4663);assert.equal(config.deploymentBlock,82454371);
  assert.equal(config.game,'0xa5ae5282aa914a4ce689f1609462e2a5eaa2490d');assert.equal(config.vault,'0x5a3dc16c23447f70c414145118ee2e9984260482');assert.equal(config.pot,'0xd77f768d634328bdfa826051457c974f4028a6dc');
});
test('all three ABIs match the verified deployment hashes',()=>{
  const expected={SeasonPot:'7af39e324d984ce950c934349cf3fd2bfb04d390a606c841f5536dd656bea927',DeedVault:'6874e0e9f6b9684135984c7986e88b2935078971f0883c79c6b088d7518a6680',SwarmopolyGame:'19f7ca862ec6d3f9ee38dbd176dffbe4ab728a9f71a00dcea91723fc1b0eb9ff'};
  for(const [name,value] of Object.entries(abi))assert.equal(keccak256(toUtf8Bytes(JSON.stringify(canonical(value)))).slice(2),expected[name]);
});
test('board has forty unique perimeter coordinates and 28 properties',()=>{
  assert.equal(names.length,40);assert.equal(40-special.size,28);
  assert.equal(new Set(names.map((_,i)=>boardPosition(i).join(','))).size,40);
  for(let i=0;i<40;i++){const [r,c]=boardPosition(i);assert.ok(r===1||r===11||c===1||c===11);}
  assert.deepEqual(boardPosition(0),[11,11]);assert.deepEqual(boardPosition(10),[11,1]);assert.deepEqual(boardPosition(20),[1,1]);assert.deepEqual(boardPosition(30),[1,11]);
});
test('hops cross GO and include Chance or jail relocations',()=>{
  assert.deepEqual(hopPath(38,2,1,1),[39,0,1]);
  assert.deepEqual(hopPath(25,3,2,10),[26,27,28,29,30,10]);
  assert.deepEqual(hopPath(1,3,3,0),[2,3,4,5,6,7,0]);
});
test('wallet identities are case invariant and cover six shapes',()=>{
  assert.deepEqual(identity(config.game),identity(config.game.toUpperCase()));
  const shapes=new Set(Array.from({length:300},(_,n)=>identity('0x'+n.toString(16).padStart(40,'0')).shape));assert.equal(shapes.size,6);
});
test('countdowns clamp at zero and dice have six physical faces',()=>{
  assert.equal(countdown(-2),'00:00:00');assert.equal(countdown(90061),'1d 01:01:01');
  assert.equal((die(6).match(/class="face face-/g)||[]).length,6);
});
test('every wallet action is present in the pinned ABI',()=>{
  const game=new Interface(abi.SwarmopolyGame),vault=new Interface(abi.DeedVault),pot=new Interface(abi.SeasonPot);
  for(const name of ['joinSeason','deposit','withdraw','fundPot','commitRoll','revealRoll','expireRoll','claimRent','claimPrize','finalizeSeason','startSeason','setParams','setPaused','listTile','payBail','skipJailRoll'])assert.ok(game.getFunction(name));
  assert.ok(game.getFunction('buyDeed(uint8,uint256,uint256,uint8)'));
  for(const name of ['quote','redeem','sponsorTile','claimSponsor','withdrawSponsor','bindGame'])assert.ok(vault.getFunction(name));assert.ok(pot.getFunction('bindGame'));
});
test('production export is complete, identical to source and uses local relative assets',async()=>{
  const base=new URL('../dist/',import.meta.url),source=new URL('../site/',import.meta.url);
  async function walk(dir){for(const entry of await readdir(new URL(dir,base),{withFileTypes:true})){const name=dir+entry.name;if(entry.isDirectory()){assert.ok(!/node_modules|cache/.test(name));await walk(name+'/');}else{assert.ok(!name.endsWith('.tgz'));assert.deepEqual(await readFile(new URL(name,base)),await readFile(new URL(name,source)));}}}
  await walk('');
  for(const file of ['index.html','rules.html']){const html=await readFile(new URL(file,base),'utf8');for(const m of html.matchAll(/(?:src|href)="([^"#]+)"/g)){assert.ok(!m[1].startsWith('/')&&!m[1].startsWith('http'));await access(new URL(m[1].split('#')[0],base));}}
  const html=await readFile(new URL('index.html',base),'utf8');const ids=[...html.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]);assert.equal(new Set(ids).size,ids.length);
});

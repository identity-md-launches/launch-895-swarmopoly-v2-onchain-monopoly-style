// Dependency-free startup/rendering smoke test. Run: node --test test/site.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile, access } from 'node:fs/promises';
import * as ethers from '../site/vendor/ethers.min.js';

const base = new URL('../site/', import.meta.url);
const html = await readFile(new URL('index.html', base), 'utf8');
const source = (await readFile(new URL('app.js', base), 'utf8')).replace(/^import[^\n]+\n/, '');
const config = JSON.parse(await readFile(new URL('config.json', base), 'utf8'));
const abi = JSON.parse(await readFile(new URL('abi.json', base), 'utf8'));

test('unconfigured site renders all forty squares without invented live data', async () => {
  const elements = new Map();
  class Element {
    children=[]; style={setProperty(name,value){this[name]=value;}}; attributes={}; textContent=''; hidden=false; disabled=false; className='';
    constructor(tag='div'){this.tagName=tag;this.classList={add:(...v)=>{this.className=[...new Set([...this.className.split(' '),...v])].join(' ');},remove:(v)=>{this.className=this.className.split(' ').filter(x=>x!==v).join(' ');},toggle:(v,on)=>{if(on)this.classList.add(v);else this.classList.remove(v);},contains:v=>this.className.split(' ').includes(v)};}
    set id(value){this._id=value;elements.set(value,this);}get id(){return this._id;}
    append(child){this.children.push(child);}replaceChildren(...children){this.children=children;}
    setAttribute(name,value){this.attributes[name]=value;}
  }
  for(const match of html.matchAll(/\bid="([^"]+)"/g)){const element=new Element();element.id=match[1];}
  const document={getElementById:id=>elements.get(id),createElement:tag=>new Element(tag),createTextNode:text=>({textContent:text}),querySelector:selector=>[...elements.values()].find(e=>selector==='.tile.selected'&&e.classList.contains('tile')&&e.classList.contains('selected'))};
  const intervals=[];
  const context=vm.createContext({...ethers,JsonRpcProvider:class{async getNetwork(){return {chainId:4663n};}},document,window:{},console:{...console,error(){}},fetch:async url=>({json:async()=>url.includes('config')?{...config,game:null,vault:null,pot:null,deploymentBlock:null}:abi}),setInterval:(fn,ms)=>intervals.push({fn,ms}),setTimeout,Date,Number,BigInt,Set,Map,localStorage:{getItem:()=>null}});
  vm.runInContext(source,context);
  await new Promise(resolve=>setImmediate(resolve));
  assert.match(elements.get('status').textContent,/Launch setup in progress/);
  const board=[...elements.values()].filter(e=>e.classList.contains('tile'));
  assert.equal(board.length,40);
  assert.equal(new Set(board.map(e=>`${e.style.gridRow},${e.style.gridColumn}`)).size,40);
  assert.equal(elements.get('tile-0').style.gridRow,11);assert.equal(elements.get('tile-0').style.gridColumn,11);
  assert.equal(board.filter(e=>e.children.some(c=>c.textContent==='Launch Day soon')).length,28);
  elements.get('tile-6').onclick();assert.equal(elements.get('tile-name').textContent,'Oriental Avenue');
  assert.equal(elements.get('buy').disabled,true);assert.equal(elements.get('roll').disabled,true);
  assert.equal(intervals.length,2);
  elements.get('connect').onclick();await new Promise(resolve=>setImmediate(resolve));
  assert.match(elements.get('status').textContent,/browser wallet is required/);
});

test('all local entrypoint assets exist and ABI exposes the UI transaction methods', async()=>{
  for(const match of html.matchAll(/(?:src|href)="([^"#]+)"/g)){
    if(!match[1].startsWith('http'))await access(new URL(match[1],base));
  }
  const game=new ethers.Interface(abi.SwarmopolyGame),vault=new ethers.Interface(abi.DeedVault),pot=new ethers.Interface(abi.SeasonPot);
  for(const name of ['joinSeason','deposit','withdraw','commitRoll','revealRoll','expireRoll','claimRent','claimPrize','finalizeSeason','startSeason','setParams','setPaused','listTile','payBail','skipJailRoll'])assert.ok(game.getFunction(name));
  assert.ok(game.getFunction('buyDeed(uint8,uint256,uint256,uint8)'));
  for(const name of ['quote','redeem','sponsorTile','claimSponsor','withdrawSponsor','bindGame'])assert.ok(vault.getFunction(name));
  assert.ok(pot.getFunction('bindGame'));
});

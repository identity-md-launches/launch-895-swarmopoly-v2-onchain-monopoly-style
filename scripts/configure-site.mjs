// Read-only deployment handoff validation. Usage: node scripts/configure-site.mjs GAME VAULT POT DEPLOYMENT_BLOCK
import { readFile, writeFile } from 'node:fs/promises';
import { JsonRpcProvider, Contract, getAddress, ZeroAddress } from '../site/vendor/ethers.min.js';
const [gameAddress,vaultAddress,potAddress,block] = process.argv.slice(2);
if (!block || ![gameAddress,vaultAddress,potAddress].every(a=>a && getAddress(a)!==ZeroAddress) || !/^\d+$/.test(block)) throw Error('Pass confirmed GAME VAULT POT DEPLOYMENT_BLOCK.');
const cfg=JSON.parse(await readFile(new URL('../site/config.json',import.meta.url),'utf8'));
const abi=JSON.parse(await readFile(new URL('../site/abi.json',import.meta.url),'utf8'));
const rpc=new JsonRpcProvider(cfg.rpcUrl);
if ((await rpc.getNetwork()).chainId!==4663n) throw Error('Wrong chain');
for(const address of [gameAddress,vaultAddress,potAddress]) if(await rpc.getCode(address)==='0x') throw Error(`No code at ${address}`);
const game=new Contract(gameAddress,abi.SwarmopolyGame,rpc),vault=new Contract(vaultAddress,abi.DeedVault,rpc),pot=new Contract(potAddress,abi.SeasonPot,rpc);
const eq=(a,b)=>a.toLowerCase()===b.toLowerCase();
if(!eq(await game.vault(),vaultAddress)||!eq(await game.pot(),potAddress)||!eq(await game.currency(),cfg.currency)||!eq(await vault.poolManager(),cfg.poolManager)||!eq(await vault.currency(),cfg.currency)||!eq(await pot.currency(),cfg.currency)) throw Error('Dependency mismatch');
const owner=await game.owner();
if(!eq(owner,await vault.owner())||!eq(owner,await pot.owner())) throw Error('Owner mismatch');
for(const component of [pot,vault]) {const binding=await component.game();if(binding!==ZeroAddress&&!eq(binding,gameAddress))throw Error('Wrong bound game');}
const height=Number(block);if(!Number.isSafeInteger(height)||height>await rpc.getBlockNumber())throw Error('Invalid deployment block');
Object.assign(cfg,{game:getAddress(gameAddress),vault:getAddress(vaultAddress),pot:getAddress(potAddress),deploymentBlock:height});
await writeFile(new URL('../site/config.json',import.meta.url),JSON.stringify(cfg,null,2)+'\n');
console.log('Verified deployment configuration written. Bind pot/vault and start a season using the owner panel.');

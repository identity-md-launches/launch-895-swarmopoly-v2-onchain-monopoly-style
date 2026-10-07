// Read-only deployment evidence. No signer or transaction methods are used.
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { JsonRpcProvider, Contract, FetchRequest, keccak256, toUtf8Bytes, ZeroAddress } from '../site/vendor/ethers.min.js';
const cfg=JSON.parse(await readFile(new URL('../site/config.json',import.meta.url))),abi=JSON.parse(await readFile(new URL('../site/abi.json',import.meta.url)));
const request=new FetchRequest(cfg.rpcUrl);request.timeout=15000;const rpc=new JsonRpcProvider(request);
const history=new JsonRpcProvider(cfg.rpcFallbackUrl);
const canonical=x=>Array.isArray(x)?x.map(canonical):x&&typeof x==='object'?Object.fromEntries(Object.keys(x).sort().map(k=>[k,canonical(x[k])])):x;
const eq=(a,b)=>assert.equal(a.toLowerCase(),b.toLowerCase());
try{
  assert.equal((await rpc.getNetwork()).chainId,4663n);assert.equal((await history.getNetwork()).chainId,4663n);
  for(const address of [cfg.game,cfg.vault,cfg.pot,cfg.currency,cfg.poolManager])assert.notEqual(await rpc.getCode(address),'0x');
  const game=new Contract(cfg.game,abi.SwarmopolyGame,rpc),vault=new Contract(cfg.vault,abi.DeedVault,rpc),pot=new Contract(cfg.pot,abi.SeasonPot,rpc);
  eq(await game.vault(),cfg.vault);eq(await game.pot(),cfg.pot);eq(await game.currency(),cfg.currency);eq(await vault.currency(),cfg.currency);eq(await pot.currency(),cfg.currency);eq(await vault.poolManager(),cfg.poolManager);eq(await game.owner(),await vault.owner());eq(await game.owner(),await pot.owner());
  const block=await history.getBlock(cfg.deploymentBlock);assert.equal(block.number,cfg.deploymentBlock);
  let primaryHistory='available',logs;
  const filter={address:[cfg.game,cfg.vault],fromBlock:cfg.deploymentBlock,toBlock:cfg.deploymentBlock+4999};
  try{logs=await rpc.getLogs(filter);}catch(error){primaryHistory=error.error?.message||error.info?.error?.message||error.shortMessage;logs=await history.getLogs(filter);}
  const season=await game.currentSeason(),tiles=await Promise.all(Array.from({length:40},(_,i)=>vault.tile(i)));
  console.log(JSON.stringify({checkedAt:new Date().toISOString(),chainId:4663,deploymentBlock:block.number,deploymentBlockHash:block.hash,abiHashes:Object.fromEntries(Object.entries(abi).map(([name,value])=>[name,keccak256(toUtf8Bytes(JSON.stringify(canonical(value))))])),codeAndDependencies:'pass',currentSeason:String(season),potAvailableWei:String(await pot.available()),listedTiles:tiles.filter(t=>t.token!==ZeroAddress).length,potGame:await pot.game(),vaultGame:await vault.game(),primaryHistory,historyRange:{from:filter.fromBlock,to:filter.toBlock,logs:logs.length},transactionsSent:0},null,2));
}finally{rpc.destroy();history.destroy();}

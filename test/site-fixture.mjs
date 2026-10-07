// Local-only JSON-RPC fixture. Actual ethers encoding and wallet calls run in the browser.
import { readFileSync } from 'node:fs';
import { Interface, ZeroAddress as Z, ZeroHash as H, parseEther, keccak256, AbiCoder } from '../site/vendor/ethers.min.js';
const cfg=JSON.parse(readFileSync(new URL('../site/config.json',import.meta.url)));
const abi=JSON.parse(readFileSync(new URL('../site/abi.json',import.meta.url)));
export const USER='0x1111111111111111111111111111111111111111';
export const OWNER='0x2222222222222222222222222222222222222222';
const TOKEN='0x3333333333333333333333333333333333333333';
const token=new Interface(['function decimals() view returns(uint8)','function symbol() view returns(string)','function allowance(address,address) view returns(uint256)','function approve(address,uint256) returns(bool)']);
const game=new Interface(abi.SwarmopolyGame),vault=new Interface(abi.DeedVault),pot=new Interface(abi.SeasonPot);
const hex=n=>'0x'+BigInt(n).toString(16),hash=n=>'0x'+BigInt(n).toString(16).padStart(64,'0');
export function fixture({owner=false,noSeason=false,noWallet=false}={}){
  const timestamp=Math.floor(Date.now()/1000);let height=cfg.deploymentBlock+10,evmHeight=100n,sequence=1;
  const account=owner?OWNER:USER;
  const state={chain:'0x1237',calls:[],walletCalls:[],account,noWallet,season:noSeason?0n:1n,balance:100n*10n**18n,joined:false,position:38,canBuy:false,jailed:false,bankrupt:false,nextRoll:0n,nonce:0n,pending:[H,0n,0n,0n,0n],allowance:0n,pot:1250n*10n**18n,paused:false,buyPaused:false,prize:0n,score:0n,finalized:false,bound:true,bindings:{},rollFinal:5,die1:3,die2:4,quote:12n*10n**18n,deeds:new Map(),rent:new Map(),txs:new Map(),receipts:new Map(),logs:[],end:timestamp+86400*7};
  const season=()=>[parseEther('10'),BigInt(state.end),parseEther('1'),parseEther('100'),state.finalized];
  const player=who=>[state.joined&&who.toLowerCase()===account?state.season:0n,state.balance,state.nextRoll,state.nonce,0n,state.position,state.jailed,state.bankrupt,state.canBuy];
  function tile(slot){const listed=slot===5||slot===1;return [[cfg.currency,TOKEN,3000,60,Z],listed?TOKEN:Z,listed?1:0,listed?parseEther('50'):0n,listed?parseEther('50'):0n,listed?parseEther('100'):0n,0n,0n];}
  const iface=address=>address.toLowerCase()===cfg.game?game:address.toLowerCase()===cfg.vault?vault:address.toLowerCase()===cfg.pot?pot:token;
  function read(address,data){const i=iface(address),q=i.parseTransaction({data}),a=q.args;let value;
    switch(q.name){
      case 'vault':value=cfg.vault;break;case 'pot':value=cfg.pot;break;case 'currency':value=cfg.currency;break;case 'poolManager':value=cfg.poolManager;break;case 'owner':value=OWNER;break;
      case 'decimals':value=18;break;case 'symbol':value='IMPS';break;case 'allowance':value=state.allowance;break;case 'currentSeason':value=state.season;break;
      case 'seasons':return i.encodeFunctionResult(q.fragment,season());
      case 'available':value=state.pot;break;case 'reserved':value=0n;break;case 'leaders':value=state.joined?[account,...Array(9).fill(Z)]:Array(10).fill(Z);break;
      case 'scores':value=state.score;break;case 'tile':value=tile(Number(a[0]));break;case 'rollsPaused':value=state.paused;break;case 'buysPaused':value=state.buyPaused;break;case 'game':value=(state.bindings[address.toLowerCase()]??state.bound)?cfg.game:Z;break;case 'tierRent':value=parseEther(String([1,2,3,5,8,12,20,30][Number(a[0])]));break;
      case 'player':value=player(a[0]);break;case 'rolls':return i.encodeFunctionResult(q.fragment,state.pending);
      case 'chainBlockNumber':value=evmHeight;break;
      case 'commitmentFor':value=keccak256(AbiCoder.defaultAbiCoder().encode(['uint256','address','address','uint256','bytes32'],[4663,cfg.game,a[0],state.nonce+1n,a[1]]));break;
      case 'quote':value=state.quote;break;
      case 'deeds':return i.encodeFunctionResult(q.fragment,state.deeds.get(a[0].toString())||[Z,0,0n,0n,0n,0n,0n,0n,0n]);
      case 'pendingRent':value=state.rent.get(a[0].toString())||0n;break;
      default:throw Error('Unmocked read '+q.name);
    }
    return i.encodeFunctionResult(q.fragment,[value]);
  }
  function send(tx){const i=iface(tx.to),q=i.parseTransaction(tx),a=q.args,txHash=hash(sequence++);height++;state.calls.push({name:q.name,to:tx.to,args:[...a]});let emitted=[];
    const emit=(contract,address,name,values)=>{const e=contract.encodeEventLog(contract.getEvent(name),values);emitted.push({address,topics:e.topics,data:e.data,blockNumber:hex(height),transactionHash:txHash,transactionIndex:'0x0',blockHash:hash(height),logIndex:hex(emitted.length),removed:false});};
    switch(q.name){
      case 'approve':state.allowance=a[1];break;
      case 'joinSeason':state.joined=true;emit(game,cfg.game,'Joined',[state.season,account]);break;
      case 'deposit':state.balance+=a[0];break;case 'withdraw':state.balance-=a[0];break;case 'fundPot':state.pot+=a[0];break;
      case 'commitRoll':state.nonce++;state.pending=[a[0],evmHeight+1n,BigInt(timestamp+3600),parseEther('30'),state.season];state.nextRoll=BigInt(timestamp+72000);break;
      case 'revealRoll':state.pending=[H,0n,0n,0n,0n];if(state.position+state.die1+state.die2>=40||state.rollFinal===0){state.balance+=parseEther('1');state.score+=parseEther('1');emit(game,cfg.game,'ScoreChanged',[state.season,account,state.score]);}state.position=state.rollFinal;state.jailed=state.rollFinal===10;state.canBuy=!state.jailed;if([1,5].includes(state.rollFinal)){state.balance-=parseEther('1');emit(vault,cfg.vault,'RentCredited',[state.position,parseEther('.8')]);}emit(game,cfg.game,'Rolled',[account,state.die1,state.die2,state.position]);break;
      case 'buyDeed':{const id=String(state.deeds.size+1);const d=[account,Number(a[0]),parseEther('12'),parseEther('24'),BigInt(timestamp+(Number(a[3])||1)*86400),0n,0n,0n,state.season];state.deeds.set(id,d);state.rent.set(id,parseEther('2'));state.canBuy=false;emit(vault,cfg.vault,'DeedBought',[BigInt(id),account,a[0],parseEther('12'),parseEther('12')]);break;}
      case 'claimRent':state.rent.set(a[0].toString(),0n);break;
      case 'redeem':state.deeds.get(a[0].toString())[2]=0n;emit(vault,cfg.vault,'Redeemed',[a[0],parseEther('12')]);break;
      case 'setPaused':state.paused=a[0];state.buyPaused=a[1];break;case 'startSeason':state.season++;break;case 'bindGame':state.bindings[tx.to.toLowerCase()]=true;break;
      case 'skipJailRoll':case 'payBail':state.jailed=false;break;case 'expireRoll':state.pending=[H,0n,0n,0n,0n];state.bankrupt=true;break;
      case 'finalizeSeason':state.finalized=true;break;
      case 'claimPrize':case 'listTile':case 'setParams':case 'sponsorTile':case 'claimSponsor':case 'withdrawSponsor':break;
      default:throw Error('Unmocked write '+q.name);
    }
    const receipt={transactionHash:txHash,transactionIndex:'0x0',blockHash:hash(height),blockNumber:hex(height),from:account,to:tx.to,cumulativeGasUsed:'0x186a0',gasUsed:'0x186a0',contractAddress:null,logs:emitted,logsBloom:'0x'+'00'.repeat(256),status:'0x1',effectiveGasPrice:'0x1',type:'0x0'};
    state.txs.set(txHash,{hash:txHash,nonce:hex(sequence),blockHash:hash(height),blockNumber:hex(height),transactionIndex:'0x0',from:account,to:tx.to,value:'0x0',gas:'0x186a0',gasPrice:'0x1',input:tx.data,type:'0x0',chainId:'0x1237',v:'0x25',r:hash(1),s:hash(2)});state.receipts.set(txHash,receipt);state.logs.push(...emitted);return txHash;
  }
  async function rpc(method,params=[]){
    switch(method){
      case 'eth_chainId':return state.chain;case 'eth_accounts':case 'eth_requestAccounts':return [account];case 'wallet_switchEthereumChain':state.walletCalls.push(method);state.chain='0x1237';return null;case 'wallet_addEthereumChain':state.walletCalls.push(method);return null;
      case 'eth_getCode':return '0x60006000';case 'eth_blockNumber':return hex(height);case 'eth_call':return read(params[0].to,params[0].data);case 'eth_estimateGas':return '0x186a0';case 'eth_gasPrice':return '0x1';case 'eth_getTransactionCount':return hex(sequence);case 'eth_sendTransaction':return send(params[0]);
      case 'eth_getTransactionByHash':return state.txs.get(params[0])||null;case 'eth_getTransactionReceipt':return state.receipts.get(params[0])||null;
      case 'eth_getLogs':return state.logs.filter(l=>Number(l.blockNumber)>=Number(params[0].fromBlock)&&Number(l.blockNumber)<=Number(params[0].toBlock));
      case 'eth_getBlockByNumber':return {number:hex(height),hash:hash(height),parentHash:hash(height-1),timestamp:hex(timestamp),nonce:'0x0000000000000000',difficulty:'0x0',gasLimit:'0x1c9c380',gasUsed:'0x0',miner:Z,extraData:'0x',transactions:[],baseFeePerGas:'0x1'};
      default:throw Error('Unmocked RPC '+method);
    }
  }
  return {state,rpc,advanceReveal(){evmHeight+=3n;},async install(page){
    await page.route(/https:\/\/(robinhood-rpc\.publicnode\.com|rpc\.mainnet\.chain\.robinhood\.com)\/?$/,async route=>{
      const body=route.request().postDataJSON();const respond=async q=>{try{return{jsonrpc:'2.0',id:q.id,result:await rpc(q.method,q.params)};}catch(e){return{jsonrpc:'2.0',id:q.id,error:{code:-32000,message:e.message}};}};
      const result=Array.isArray(body)?await Promise.all(body.map(respond)):await respond(body);await route.fulfill({contentType:'application/json',body:JSON.stringify(result)});
    });
    if(!noWallet){await page.exposeFunction('walletRPC',rpc);await page.addInitScript(()=>{window.walletListeners={};window.ethereum={request:({method,params})=>window.walletRPC(method,params),on:(event,callback)=>window.walletListeners[event]=callback};});}
  }};
}

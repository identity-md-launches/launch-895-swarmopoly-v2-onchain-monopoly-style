import { BrowserProvider, JsonRpcProvider, FetchRequest, Contract, ZeroAddress, ZeroHash, parseUnits, formatUnits, randomBytes, hexlify, getAddress, AbiCoder, keccak256 } from './vendor/ethers.min.js';
import { names, special, tiers, boardPosition, short, equal, identity, hopPath, countdown, icon, specialIcon, die } from './ui.js';

/** @param {string} id @returns {HTMLElement & {value: string, disabled: boolean, checked: boolean}} */
const $ = id => /** @type {any} */ (document.getElementById(id));
/** @type {any} */ const injected = window.ethereum;
const erc20 = ['function approve(address,uint256) returns(bool)','function allowance(address,address) view returns(uint256)','function decimals() view returns(uint8)','function symbol() view returns(string)'];
/** @type {any} */ let cfg, abi, rpc, wallet, signer, game, vault, pot, cash, season, me, pending;
/** @type {string | undefined} */ let account, owner;
/** @type {any[]} */ let tiles = [], rents = [], leaders = [], myDeeds = [];
let ready=false, busy=false, quoting=false, claimingAll=false, refreshing=false, scanning=false, animating=false, wrongNetwork=false, pausedEffects=false, rollsPaused=false, buysPaused=false;
let seasonId=0n, selected=1, logCursor=0, logHead=0, logsComplete=false, autoReveal=false, revealChecking=false;
let potBound=false, vaultBound=false, page='board';
/** @type {any} */ let historyRpc;
/** @type {{slot:number,amount:bigint,minOut:bigint,time:number,input:string,slippage:string} | undefined} */ let quoteState;
/** @type {Map<string, any>} */ const deeds = new Map(), metadata = new Map(), activity = new Map(), positions = new Map();
/** @type {Set<string>} */ const joined = new Set();
const now = () => Math.floor(Date.now()/1000);
const reduced = () => pausedEffects || matchMedia('(prefers-reduced-motion: reduce)').matches;
const fmt = (value, decimals=18) => Number(formatUnits(value,decimals)).toLocaleString(undefined,{maximumFractionDigits:5});
const units = value => parseUnits(String(value).trim(),18);
const positive = value => { const n=units(value); if(n<=0n) throw new Error('Enter an IMD amount greater than zero.'); return n; };
const sleep = ms => new Promise(resolve=>setTimeout(resolve,reduced()?0:ms));
function status(message, error=false) { $('status').textContent=message; $('status').classList.toggle('error',error); }
function toast(message, hash='', error=false) {
  const el=document.createElement('div'); el.className=`toast${error?' error':''}`;
  const p=document.createElement('p');p.textContent=message;el.append(p);
  if(hash){const a=document.createElement('a');a.href=`${cfg.explorerUrl}/tx/${hash}`;a.target='_blank';a.rel='noopener noreferrer';a.textContent='View transaction ↗';el.append(a);}
  const close=document.createElement('button');close.textContent='×';close.setAttribute('aria-label','Dismiss transaction notice');close.onclick=()=>el.remove();el.append(close);$('toasts').append(el);
  $('announcer').textContent=message;
  return { update(text, failed=false) { p.textContent=text;el.classList.toggle('error',failed);$('announcer').textContent=text; } };
}
function messageFor(error) {
  if(error.code===4001 || error.code==='ACTION_REJECTED') return 'Wallet request declined. You can try again when ready.';
  return error.shortMessage || error.reason || error.message || String(error);
}
function report(error) { const message=messageFor(error);status(message,true);toast(message,'',true); }
const secretKey = () => `swarmopoly:${cfg.chainId}:${cfg.game.toLowerCase()}:${account.toLowerCase()}`;
function savedRoll(){try{return JSON.parse(localStorage.getItem(secretKey())||'null');}catch{return null;}}
function saveRoll(value){try{localStorage.setItem(secretKey(),JSON.stringify(value));}catch{throw new Error('Allow site storage before rolling so your reveal secret can be saved.');}}
const action=(id,fn)=>{$(id).onclick=()=>Promise.resolve().then(fn).catch(report);};
const form=(id,fn)=>{$(id).onsubmit=event=>{event.preventDefault();Promise.resolve().then(()=>fn(new FormData(/** @type {HTMLFormElement} */(event.target)))).catch(report);};};
function activeSeason(){return seasonId>0n && season && !season.finalized && Number(season.end)>now();}
function canTransact(){return ready && !!account && !wrongNetwork && !busy && !claimingAll;}
function hasPending(){return pending && pending.commitment!==ZeroHash;}
function drawBoard(){
  document.querySelectorAll('[data-icon]').forEach(el=>el.innerHTML=icon(el.getAttribute('data-icon')));
  $('dice').innerHTML=die(1)+die(1);
  names.forEach((name,slot)=>{
    const button=document.createElement('button');button.className=`tile${slot%10===0?' corner':''}${!special.has(slot)?' vacant':''}`;button.id=`tile-${slot}`;
    const [row,col]=boardPosition(slot);button.style.gridRow=String(row);button.style.gridColumn=String(col);
    button.style.setProperty('--tier',tiers[Math.min(7,Math.floor(slot/5))]);
    // All HTML here is from original, static artwork. Chain strings use textContent.
    button.innerHTML=`<span class="number">${String(slot).padStart(2,'0')}</span>${special.has(slot)?`<span class="tile-icon">${icon(specialIcon(slot))}</span>`:'<span class="tile-monogram">◇</span>'}<span class="tile-name"></span><span class="tile-sub"></span><span class="tile-holders"></span><span class="markers"></span>`;
    button.querySelector('.tile-name').textContent=name;
    button.querySelector('.tile-sub').textContent=special.has(slot)?'':'Launch Day soon';
    button.setAttribute('aria-label',`${slot}: ${name}${special.has(slot)?'':'. Launch Day soon.'}`);
    button.onclick=()=>selectTile(slot,true);$('board').append(button);
    const option=document.createElement('option');option.value=String(slot);option.textContent=`${String(slot).padStart(2,'0')} · ${name}`;$('square-select').append(option);
  });
  $('square-select').onchange=()=>selectTile(Number($('square-select').value),true);
  selectTile(1);
}
function selectTile(slot, announce=false){
  document.querySelector('.tile.selected')?.classList.remove('selected');selected=slot;quoteState=undefined;
  $(`tile-${slot}`).classList.add('selected');$('square-select').value=String(slot);
  $('landing-outcome').hidden=true;$('landing-card').classList.remove('landed','chance','jailed');
  $('quote-output').textContent='Get a fresh quote before buying.';renderSelected();updateControls();
  if(announce) $('announcer').textContent=`${names[slot]}. ${$('tile-description').textContent}`;
}
function renderSelected(){
  const tile=tiles[selected], listed=tile && tile.token!==ZeroAddress;
  $('tile-number').textContent=`Square / ${String(selected).padStart(2,'0')}`;$('tile-name').textContent=names[selected];
  $('tile-badge').textContent=special.has(selected)?'Board stop':listed?`Tier ${tile.tier}`:'Vacant lot';
  $('landing-card').style.setProperty('--tier',listed?tiers[Number(tile.tier)-1]:'var(--line)');
  const descriptions={0:'Pass GO and collect your salary from the pot.',10:'Just visiting? Carry on. In jail? Pay 5 IMD bail or skip your next roll.',20:'Free Parking pays a pot reward once per UTC day.',30:'Go directly to jail. Pay bail or skip a roll to return.',4:'Income tax: up to 5 IMD from your play balance.',38:'Luxury tax: up to 5 IMD from your play balance.'};
  const meta=listed?metadata.get(tile.token.toLowerCase()):undefined;
  $('tile-description').textContent=special.has(selected)?descriptions[selected]||'A little surprise. Your roll reveals a reward, tax, move or quiet turn.':listed?`${meta?.symbol || short(tile.token)} · ${fmt(rents[Number(tile.tier)-1]||0n)} IMD rent · ${holderCount(selected)} holders`:'Launch Day soon. A future home for a community token. Explore the lots while the neighborhood gets ready.';
  $('buy-form').hidden=!listed;$('sponsor-details').hidden=!listed;$('vacant-link').hidden=!!listed;
}
function updateControls(){
  const enabled=canTransact(), active=activeSeason(), playing=active && me?.season===seasonId && !me?.bankrupt;
  const listed=tiles[selected]?.token && tiles[selected].token!==ZeroAddress;
  for(const id of ['deposit','withdraw','claim-prize','fund-pot']) $(id).disabled=!enabled;
  for(const id of ['sponsor','claim-sponsor','withdraw-sponsor']) $(id).disabled=!enabled || !listed;
  $('sponsor').disabled ||= !active || !vaultBound;
  $('finalize').disabled=!enabled || !seasonId || !!season?.finalized || Number(season?.end)>now();
  $('join').disabled=!enabled || !active || !potBound || !vaultBound || me?.season===seasonId || !!hasPending();
  const canRoll=enabled && playing && !me?.jailed && !hasPending() && !rollsPaused && Number(me.nextRoll)<=now() && Number(season.end)>now()+3600 && me.balance>=season.rollBond;
  $('roll').disabled=!canRoll;
  $('quote').disabled=!ready || !listed || busy || quoting;
  $('buy').disabled=!enabled || !listed || !quoteState || Date.now()-quoteState.time>60000 || !playing || !me.canBuy || Number(me.position)!==selected || buysPaused || animating;
  $('buy-hint').textContent=buysPaused?'Deed purchases are paused.':playing && me.canBuy && Number(me.position)===selected?`Buy up to ${fmt(season.maxBuy)} IMD. Payment comes from your wallet.`:'Land here during an active season to buy a deed.';
  $('bail').hidden=$('skip').hidden=!me?.jailed || me?.bankrupt || !active;
  $('bail').disabled=!enabled || (me?.balance||0n)<5n*10n**18n;
  $('skip').disabled=!enabled || Number(me?.nextRoll)>now();
  $('reveal').hidden=$('recover').hidden=!hasPending();$('reveal').disabled=!enabled;
  $('export-secret').hidden=!account || !hasPending() || !savedRoll();
  $('import-secret').disabled=$('expire').disabled=!enabled;
  const isOwner=!!account && equal(owner,account);$('admin').hidden=$('owner-nav').hidden=!isOwner;
  document.querySelectorAll('#admin button').forEach(el=>/** @type {HTMLButtonElement} */(el).disabled=!enabled || !isOwner);
  $('bind-pot').disabled ||= potBound;$('bind-vault').disabled ||= vaultBound;
  $('claim-all').disabled=!enabled || !myDeeds.some(d=>d.pending>0n);
  document.querySelectorAll('#deeds button').forEach(el=>{const button=/** @type {HTMLButtonElement} */(el);button.disabled=!enabled || button.dataset.available!=='true';});
  $('connect').textContent=account?short(account):'Connect wallet ↗';
  $('add-chain').hidden=!!account && !wrongNetwork;
  $('dice').classList.toggle('waiting',!!hasPending() && !animating);
  let label='Connect to play ↗', title='Take a seat.', desc='A little strategy. A little luck. A whole neighborhood to build together.', disabled=false;
  if(wrongNetwork){title='Meet us on Robinhood.';desc='Switch to Robinhood Chain to continue your game.';label='Switch to Robinhood Chain';}
  else if(!ready){title='The table is open.';desc='Explore the board while we connect to Robinhood Chain.';label='Connect to play ↗';disabled=!!account;}
  else if(account){
    if(busy || animating){title=hasPending() || animating?'Rolling…':'One moment…';desc='Follow the request in your wallet. Your place is saved.';label=animating?'Rolling…':'Waiting for your wallet…';disabled=true;}
    else if(hasPending()){title='Rolling…';desc='Your roll is committed. Keep this tab open and confirm the reveal request.';label='Resume reveal';}
    else if(!active){title=seasonId?'Season complete.':'A new game is coming.';desc=seasonId?'The next season is on the horizon. Your deeds and rent stay yours.':'The neighborhood is getting ready for its first season. Explore the lots and come back for your first roll.';label='Explore My Swarm ↗';}
    else if(me?.season!==seasonId){title='Your seat is waiting.';desc=`Join this season for ${fmt(season.buyIn)} IMD from your wallet. Deposit a play balance separately.`;label=`Join season · ${fmt(season.buyIn)} IMD`;disabled=$('join').disabled;}
    else if(me.bankrupt){title='Back next season.';desc='Your play balance ran out. You can still claim rent, withdraw and redeem unlocked deeds.';label='Visit My Swarm ↗';}
    else if(me.jailed){title='A little time out.';desc='Pay 5 IMD bail or skip a roll once your cooldown ends.';label=Number(me.nextRoll)>now()?'Waiting for jail cooldown':'Skip jail roll';disabled=$('skip').disabled;}
    else if(me.balance<season.rollBond){title='Fuel your next move.';desc=`Keep at least ${fmt(season.rollBond)} IMD in your play balance to roll.`;label='Deposit IMD ↗';}
    else if(rollsPaused){title='A short intermission.';desc='New rolls are paused. Claims and exits remain open.';label='Rolls paused';disabled=true;}
    else if(Number(season.end)<=now()+3600){title='Last call for this season.';desc='New rolls close one hour before the season ends. Claim current-season rent before the scoring cutoff.';label='Visit My Swarm ↗';}
    else if(Number(me.nextRoll)>now()){title='Make yourself at home.';desc='Your next roll is on its way. Collect rent or explore your landing.';label=`Next roll in ${countdown(Number(me.nextRoll)-now())}`;disabled=true;}
    else{title='Make your move.';desc='Commit your roll, then reveal it. Two wallet confirmations. A new possibility.';label='Roll the dice ↗';disabled=!canRoll;}
  }
  $('turn-title').textContent=title;$('turn-description').textContent=desc;$('next-action').textContent=label;$('next-action').disabled=disabled;
  $('player-state').textContent=!account?'Spectator':wrongNetwork?'Wrong network':me?.season!==seasonId?'Your wallet':me?.bankrupt?'Out this season':me?.jailed?'In jail':`Square ${me?.position||0}`;
  const buyPrimary=!$('buy').disabled;
  $('next-action').classList.toggle('primary',!buyPrimary);$('buy').classList.toggle('primary',buyPrimary);
  if(page==='owner' && !isOwner){location.hash='#board';}
}
async function nextAction(){
  if(!account || wrongNetwork){await connect();return;}
  if(hasPending()){await revealIfReady(true);return;}
  if(!activeSeason()){location.hash='#swarm';return;}
  if(me?.season!==seasonId){await join();return;}
  if(me?.bankrupt || me?.balance<season.rollBond || Number(season.end)<=now()+3600){location.hash='#swarm';return;}
  if(me?.jailed){await transact('Skip jail roll',()=>game.connect(signer).skipJailRoll());return;}
  await commit();
}
function route(){
  const target=location.hash.slice(1);page=['board','swarm','leaders','owner'].includes(target)?target:'board';
  if(page==='owner' && !equal(owner,account))page='board';
  document.querySelectorAll('.page').forEach(el=>/** @type {HTMLElement} */(el).hidden=el.id!==`page-${page}`);
  document.querySelectorAll('nav a').forEach(el=>{if(el.getAttribute('href')===`#${page}`)el.setAttribute('aria-current','page');else el.removeAttribute('aria-current');});
  $('page-title').textContent=({board:'Small moves. Big neighborhood.',swarm:'My Swarm',leaders:'Leaderboard & pot',owner:'Owner controls'})[page];
  updateControls();
}
async function addChain(){
  if(!injected){$('wallet-help').hidden=false;status('Open Swarmopoly in a wallet browser to add Robinhood Chain.');return;}
  if(!cfg)throw new Error('Connection settings are still loading. Try again in a moment.');
  try{await injected.request({method:'wallet_switchEthereumChain',params:[{chainId:'0x1237'}]});}
  catch(error){if(error.code!==4902 && error?.data?.originalError?.code!==4902)throw error;await injected.request({method:'wallet_addEthereumChain',params:[{chainId:'0x1237',chainName:cfg.chainName,rpcUrls:[cfg.rpcUrl,cfg.rpcFallbackUrl],blockExplorerUrls:[cfg.explorerUrl],nativeCurrency:{name:'Ether',symbol:'ETH',decimals:18}}]});await injected.request({method:'wallet_switchEthereumChain',params:[{chainId:'0x1237'}]});}
  wrongNetwork=BigInt(await injected.request({method:'eth_chainId'}))!==BigInt(cfg.chainId);updateControls();
}
async function connect(){
  if(!injected){$('wallet-help').hidden=false;status('No wallet detected. Open this site in an Ethereum-compatible wallet browser.');return;}
  await injected.request({method:'eth_requestAccounts'});await addChain();
  wallet=new BrowserProvider(injected,'any');signer=await wallet.getSigner();account=await signer.getAddress();
  const who=identity(account);$('my-piece').innerHTML=icon(who.shape);$('my-piece').style.color=who.color;$('my-piece').title=account;
  autoReveal=true;await refresh();updateControls();
}
async function assertChain(){
  if(!ready)throw new Error('Live contract verification is not complete. Retry the connection.');
  if(!injected || !signer || !account)throw new Error('Connect a wallet first.');
  if(BigInt(await injected.request({method:'eth_chainId'}))!==BigInt(cfg.chainId))throw new Error('Switch your wallet to Robinhood Chain 4663.');
  const accounts=await injected.request({method:'eth_accounts'});
  if(!equal(accounts[0],account) || !equal(await signer.getAddress(),account))throw new Error('Your wallet account changed. Connect again.');
}
async function transact(label,operation,refreshAfter=true){
  if(busy)throw new Error('Wait for the current transaction to finish.');
  busy=true;updateControls();let notice;
  try{
    await assertChain();status(`${label}: confirm in your wallet.`);
    const tx=await operation();notice=toast(`${label}: confirming…`,tx.hash);status(`${label}: waiting for confirmation.`);
    const receipt=await tx.wait();if(!receipt || receipt.status!==1)throw new Error(`${label} failed. Check the transaction and try again.`);
    notice.update(`${label} confirmed.`);status(`${label} confirmed.`);return receipt;
  }catch(error){notice?.update(`${label}: ${messageFor(error)}`,true);throw error;}
  finally{busy=false;if(refreshAfter)await refresh().catch(error=>status(`Transaction finished. Refresh delayed: ${messageFor(error)}`,true));updateControls();}
}
async function approve(token,spender,amount){
  const instance=new Contract(token,erc20,signer);
  if(await instance.allowance(account,spender)<amount){
    status('Approve the exact token amount in your wallet.');const tx=await instance.approve(spender,amount);const notice=toast('Token approval: confirming…',tx.hash);
    try{const receipt=await tx.wait();if(receipt?.status!==1)throw new Error('Token approval failed.');notice.update('Token approval confirmed.');}
    catch(error){notice.update('Token approval failed. Try again.',true);throw error;}
    await assertChain();
  }
}
async function join(){await transact('Join season',async()=>{await approve(cfg.currency,cfg.game,season.buyIn);return game.connect(signer).joinSeason();});}
async function verifyDeployment(){
  if(![cfg.game,cfg.vault,cfg.pot].every(address=>address && getAddress(address)!==ZeroAddress))throw new Error('The deployment is not configured.');
  if((await rpc.getNetwork()).chainId!==4663n)throw new Error('The RPC is on the wrong chain.');
  const code=await Promise.all([cfg.game,cfg.vault,cfg.pot,cfg.currency,cfg.poolManager].map(address=>rpc.getCode(address)));if(code.some(v=>v==='0x'))throw new Error('A configured contract has no code.');
  game=new Contract(cfg.game,abi.SwarmopolyGame,rpc);vault=new Contract(cfg.vault,abi.DeedVault,rpc);pot=new Contract(cfg.pot,abi.SeasonPot,rpc);cash=new Contract(cfg.currency,erc20,rpc);
  const [v,p,c,m,d,vc,pc,go,vo,po]=await Promise.all([game.vault(),game.pot(),game.currency(),vault.poolManager(),cash.decimals(),vault.currency(),pot.currency(),game.owner(),vault.owner(),pot.owner()]);
  if(!equal(v,cfg.vault)||!equal(p,cfg.pot)||!equal(c,cfg.currency)||!equal(m,cfg.poolManager)||d!==18n||!equal(vc,cfg.currency)||!equal(pc,cfg.currency)||!equal(go,vo)||!equal(go,po))throw new Error('Deployment dependency verification failed.');
  owner=go;logCursor ||= cfg.deploymentBlock;$('game-address').textContent=`Game: ${cfg.game}`;
}
async function startRpc(){
  ready=false;$('retry').hidden=true;status('Connecting to Robinhood Chain…');
  for(const endpoint of [cfg.rpcUrl,cfg.rpcFallbackUrl]){
    try{rpc?.destroy();const request=new FetchRequest(endpoint);request.timeout=12000;rpc=new JsonRpcProvider(request,undefined,{batchMaxCount:40});await verifyDeployment();ready=true;await refresh();status('Live on Robinhood Chain · updates every 12 seconds');return;}
    catch(error){ready=false;status(`Connection delayed: ${messageFor(error)}`,true);}
  }
  $('retry').hidden=false;status('The live board is temporarily unavailable. Explore the squares, then retry the connection.',true);updateControls();
}
async function syncLogs(){
  if(scanning || !ready)return;scanning=true;
  try{
    logHead=await rpc.getBlockNumber();let start=Math.max(cfg.deploymentBlock,logCursor-12);
    for(let chunk=0;start<=logHead && chunk<8;chunk++){
      const end=Math.min(logHead,start+4999);
      const topics=[game.interface.getEvent('Joined').topicHash,game.interface.getEvent('Rolled').topicHash,vault.interface.getEvent('DeedBought').topicHash,vault.interface.getEvent('Redeemed').topicHash,vault.interface.getEvent('RentCredited').topicHash];
      const filter={address:[cfg.game,cfg.vault],topics:[topics],fromBlock:start,toBlock:end};
      let logs;
      try{logs=await (historyRpc||rpc).getLogs(filter);}
      catch(error){
        if(historyRpc)throw error;
        const request=new FetchRequest(cfg.rpcFallbackUrl);request.timeout=15000;historyRpc=new JsonRpcProvider(request);
        if((await historyRpc.getNetwork()).chainId!==4663n)throw new Error('History RPC is on the wrong chain.');
        logs=await historyRpc.getLogs(filter);
      }
      const changed=new Set();
      // Replayed recent feed entries replace reorged events; positions/deeds are read from current state.
      for(const [key,row] of activity)if(row.block>=start && row.block<=end)activity.delete(key);
      for(const log of logs){
        const event=(equal(log.address,cfg.game)?game:vault).interface.parseLog(log);if(!event)continue;
        if(event.name==='Joined')joined.add(event.args.player);
        if(event.name==='DeedBought' || event.name==='Redeemed')changed.add(event.args.id.toString());
        if(event.name==='Rolled'){joined.add(event.args.player);activity.set(`${log.transactionHash}:${log.index}`,{block:log.blockNumber,index:log.index,hash:log.transactionHash,text:`${short(event.args.player)} rolled ${event.args.die1} + ${event.args.die2}`,detail:`Landed on ${names[Number(event.args.position)]}`});}
        if(event.name==='RentCredited')activity.set(`${log.transactionHash}:${log.index}`,{block:log.blockNumber,index:log.index,hash:log.transactionHash,text:`${fmt(event.args.amount)} IMD to holders`,detail:names[Number(event.args.tile)]});
      }
      for(const id of changed)deeds.set(id,await vault.deeds(id));
      logCursor=end+1;start=end+1;
    }
    logsComplete=logCursor>logHead;
    const ordered=[...activity.entries()].sort((a,b)=>b[1].block-a[1].block || b[1].index-a[1].index);
    for(const [key] of ordered.slice(60))activity.delete(key);
    await loadPositions();renderTiles();renderActivity();renderSelected();if(account)await renderDeeds();
    $('rent-summary').textContent=logsComplete?'All indexed deeds are included.':`Finding deeds · block ${logCursor.toLocaleString()} of ${logHead.toLocaleString()}.`;
  }catch(error){logsComplete=false;$('rent-summary').textContent='Deed history is delayed. Keep this tab open to retry.';status('Live balances loaded. Player and deed history is delayed; retrying automatically.',true);}
  finally{scanning=false;updateControls();}
}
async function loadPositions(){
  const who=[...joined];
  if(account && !who.some(a=>equal(a,account)))who.push(account);
  for(let i=0;i<who.length;i+=20){await Promise.all(who.slice(i,i+20).map(async a=>{const p=await game.player(a);if(p.season===seasonId && seasonId>0n)positions.set(a.toLowerCase(),{address:a,position:Number(p.position)});else positions.delete(a.toLowerCase());}));}
}
function holderCount(slot){if(!logsComplete)return '…';return new Set([...deeds.values()].filter(d=>Number(d.tile)===slot && d.shares>0n).map(d=>d.holder.toLowerCase())).size;}
function renderTiles(){
  tiles.forEach((tile,slot)=>{
    if(special.has(slot))return;const el=$(`tile-${slot}`),listed=tile.token!==ZeroAddress,meta=metadata.get(tile.token.toLowerCase());
    el.classList.toggle('vacant',!listed);el.style.setProperty('--tier',tiers[listed?Number(tile.tier)-1:Math.min(7,Math.floor(slot/5))]);
    el.querySelector('.tile-monogram').textContent=listed?(meta?.symbol || short(tile.token)).slice(0,4):'◇';
    el.querySelector('.tile-sub').textContent=listed?`${fmt(rents[Number(tile.tier)-1])} IMD`:'Launch Day soon';
    el.querySelector('.tile-holders').textContent=listed?`${holderCount(slot)} holders`:'';
    el.setAttribute('aria-label',`${slot}: ${names[slot]}. ${listed?`${meta?.symbol || tile.token}. Tier ${tile.tier}, ${fmt(rents[Number(tile.tier)-1])} IMD rent, ${holderCount(slot)} holders.`:'Launch Day soon.'}`);
  });
  if(!animating)renderPieces();
}
function renderPieces(hopping=''){
  names.forEach((_,slot)=>{
    const marker=$(`tile-${slot}`).querySelector('.markers');marker.replaceChildren();const players=[...positions.values()].filter(p=>p.position===slot);
    players.sort((a,b)=>Number(equal(b.address,account))-Number(equal(a.address,account)));
    players.slice(0,4).forEach((p,i)=>{
      const who=identity(p.address),span=document.createElement('span');span.className=`piece${equal(p.address,account)?' mine':''}${equal(p.address,hopping)?' hopping':''}`;span.style.color=who.color;
      span.style.setProperty('--tilt',`${players.length>1?(i-1)*9:0}deg`);span.style.setProperty('--lift',`${i%2?-3:0}px`);span.innerHTML=icon(who.shape);
      const label=document.createElement('span');label.className='piece-label';label.textContent=p.address.slice(0,6);span.append(label);span.title=p.address;span.setAttribute('aria-label',`${who.label}${equal(p.address,account)?', you':''}`);marker.append(span);
    });
    if(players.length>4){const more=document.createElement('span');more.className='stack-count';more.textContent=`+${players.length-4}`;marker.append(more);}
    $(`tile-${slot}`).title=`${names[slot]}${players.length?' · Players: '+players.map(p=>p.address).join(', '):''}`;
  });
}
function renderActivity(){
  $('activity').replaceChildren();const rows=[...activity.values()].sort((a,b)=>b.block-a.block||b.index-a.index).slice(0,3);
  if(!rows.length){const li=document.createElement('li');li.className='empty';li.textContent=logsComplete?'The next move could be yours.':'Finding recent moves…';$('activity').append(li);}
  for(const row of rows){const li=document.createElement('li'),a=document.createElement('a'),small=document.createElement('small');a.textContent=row.text;a.href=`${cfg.explorerUrl}/tx/${row.hash}`;a.target='_blank';a.rel='noopener noreferrer';small.textContent=row.detail;li.append(a,small);$('activity').append(li);}
}
/** @type {bigint | undefined} */ let lastPot;
/** @param {bigint} value */
function animatePot(value){
  $('pot-total').textContent=fmt(value);
  const previous=lastPot;lastPot=value;
  if(previous===undefined || previous===value || reduced()){$('pot-value').textContent=fmt(value);return;}
  const start=performance.now();function frame(t){const progress=Math.min(1,(t-start)/700);const steps=BigInt(Math.floor(progress*1000));$('pot-value').textContent=fmt(previous+(value-previous)*steps/1000n);if(progress<1)requestAnimationFrame(frame);}requestAnimationFrame(frame);
}
async function refresh(){
  if(!ready || refreshing || animating)return;refreshing=true;
  try{
    const currentAccount=account;
    seasonId=await game.currentSeason();season=await game.seasons(seasonId);
    const result=await Promise.all([pot.available(),game.leaders(seasonId),Promise.all(names.map((_,i)=>vault.tile(i))),game.rollsPaused(),game.buysPaused(),pot.game(),vault.game(),Promise.all(tiers.map((_,i)=>game.tierRent(i)))]);
    const [available,list,tileList,pr,bp,pb,vb,tierRents]=result;tiles=tileList;rents=tierRents;rollsPaused=pr;buysPaused=bp;potBound=equal(pb,cfg.game);vaultBound=equal(vb,cfg.game);
    animatePot(available);$('season-label').textContent=seasonId?`Season ${String(seasonId).padStart(2,'0')}${season.finalized?' · Complete':''}`:'Season zero · Coming soon';
    $('binding-state').textContent=`SeasonPot: ${potBound?'bound':'not bound'} · DeedVault: ${vaultBound?'bound':'not bound'}`;
    if(!busy && !document.activeElement?.closest('#admin')){$('pause-rolls').checked=rollsPaused;$('pause-buys').checked=buysPaused;}
    await Promise.all(tiles.filter(t=>t.token!==ZeroAddress&&!metadata.has(t.token.toLowerCase())).map(async tile=>{try{const token=new Contract(tile.token,erc20,rpc);metadata.set(tile.token.toLowerCase(),{symbol:String(await token.symbol()).slice(0,16)});}catch{metadata.set(tile.token.toLowerCase(),{symbol:short(tile.token)});}}));
    leaders=await Promise.all(list.filter(a=>a!==ZeroAddress).map(async address=>({address,score:await game.scores(seasonId,address)})));renderLeaders();
    if(currentAccount){
      const [player,roll]=await Promise.all([game.player(currentAccount),game.rolls(currentAccount)]);
      if(currentAccount===account){me=player;pending=roll;if(!me.jailed && $('landing-card').classList.contains('jailed')){$('landing-card').classList.remove('jailed');$('landing-outcome').textContent='Out of jail. Your next roll follows the cooldown.';}$('balance').textContent=`${fmt(me.balance)} IMD`;$('balance-note').textContent=roll.exposure?`${fmt(roll.exposure)} IMD is reserved for your roll. ${fmt(me.balance-roll.exposure)} IMD is withdrawable.`:'Available to withdraw. Rent, tax and bail use this balance.';
        if(me.season===seasonId && seasonId>0n)positions.set(account.toLowerCase(),{address:account,position:Number(me.position)});
        await renderDeeds();
      }
    }
    renderTiles();renderSelected();tick();updateControls();
    void syncLogs();
  }finally{refreshing=false;}
}
function renderLeaders(){
  for(const id of ['leaders','top-three']){
    $(id).replaceChildren();const list=leaders.slice(0,id==='top-three'?3:10);
    if(!list.length){const li=document.createElement('li');li.className='empty';li.textContent='The first chapter is yours to write.';$(id).append(li);}
    for(const {address,score} of list){const li=document.createElement('li'),who=identity(address),label=document.createElement('span'),text=document.createElement('span'),value=document.createElement('strong');label.className='player-label';label.style.color=who.color;label.innerHTML=icon(who.shape);text.textContent=who.label;text.title=address;label.append(text);value.textContent=`${fmt(score)} IMD`;li.append(label,value);$(id).append(li);}
  }
}
async function renderDeeds(){
  if(!account)return;const currentAccount=account;
  const owned=[...deeds.entries()].filter(([,d])=>equal(d.holder,currentAccount));
  const loaded=await Promise.all(owned.map(async([id])=>{const [deed,rent]=await Promise.all([vault.deeds(id),vault.pendingRent(id)]);deeds.set(id,deed);return{id,deed,pending:rent};}));
  if(account!==currentAccount)return;myDeeds=loaded.filter(d=>d.deed.shares>0n||d.pending>0n);$('claimable').textContent=`${fmt(myDeeds.reduce((sum,d)=>sum+d.pending,0n))} IMD`;
  // Avoid replacing a focused claim/redeem control during polling.
  if(document.activeElement?.closest('#deeds')){
    document.querySelectorAll('.deed-row').forEach(row=>{
      const d=myDeeds.find(item=>item.id===/** @type {HTMLElement} */(row).dataset.deedId);
      row.querySelector('.deed-rent').textContent=`${fmt(d?.pending||0n)} IMD claimable rent`;
      const buttons=row.querySelectorAll('button');buttons[0].dataset.available=String(!!d && d.pending>0n);buttons[1].dataset.available=String(!!d && d.deed.shares>0n && Number(d.deed.redeemAt)<=now());
      if(!d || d.deed.shares===0n)row.querySelector('.lock-clock').textContent='Deed redeemed';
    });updateControls();return;
  }
  $('deeds').replaceChildren();
  if(!myDeeds.length){const div=document.createElement('div');div.className='panel empty';div.innerHTML=icon('house')+'<h3>Your first deed is around the corner.</h3><p>Land on a listed property, buy a deed and share its rent.</p><a href="#board">Explore the board ↗</a>';$('deeds').append(div);}
  for(const {id,deed,pending:rent} of myDeeds){
    const row=document.createElement('section');row.className='panel deed-row';row.dataset.deedId=id;const title=document.createElement('h3');title.textContent=`#${id} · ${names[Number(deed.tile)]}`;
    const amount=document.createElement('p');amount.className='deed-rent';amount.textContent=`${fmt(rent)} IMD claimable rent`;
    const clock=document.createElement('p');clock.className='lock-clock';clock.dataset.unlock=String(deed.redeemAt);clock.textContent=deed.shares===0n?'Deed redeemed':Number(deed.redeemAt)>now()?`Unlocks in ${countdown(Number(deed.redeemAt)-now())}`:'Unlocked · ready to redeem';
    const buttons=document.createElement('div');buttons.className='button-row';
    const claim=document.createElement('button');claim.textContent='Claim rent';claim.dataset.available=String(rent>0n);claim.disabled=!canTransact()||rent===0n;claim.onclick=()=>transact('Claim rent',()=>game.connect(signer).claimRent(id)).catch(report);
    const redeem=document.createElement('button');redeem.textContent='Redeem tokens';redeem.dataset.available=String(deed.shares>0n && Number(deed.redeemAt)<=now());redeem.disabled=!canTransact()||redeem.dataset.available!=='true';redeem.onclick=()=>transact('Redeem deed',()=>vault.connect(signer).redeem(id)).catch(report);
    buttons.append(claim,redeem);row.append(title,amount,clock,buttons);$('deeds').append(row);
  }
}
function tick(){
  if(season)$('season-end').textContent=seasonId?Number(season.end)>now()?`${countdown(Number(season.end)-now())} left this season`:'Season ended · the next chapter awaits':'A new season is on the horizon.';
  if(account)$('roll-info').textContent=hasPending()?`Rolling… reveal before ${new Date(Number(pending.deadline)*1000).toLocaleTimeString()}. Keep this tab open.`:me && Number(me.nextRoll)>now()?`Next roll in ${countdown(Number(me.nextRoll)-now())}`:'Commit, then reveal. Keep this tab open for both wallet requests.';
  document.querySelectorAll('[data-unlock]').forEach(el=>{const at=Number(/** @type {HTMLElement} */(el).dataset.unlock);if(at>now())el.textContent=`Unlocks in ${countdown(at-now())}`;else if(el.textContent!=='Deed redeemed')el.textContent='Unlocked · ready to redeem';});
  if(quoteState && Date.now()-quoteState.time>60000){quoteState=undefined;$('quote-output').textContent='Quote expired. Get a fresh quote before buying.';}
  updateControls();
}
async function commit(){
  await assertChain();const roll=await game.rolls(account);if(roll.commitment!==ZeroHash)throw new Error('Reveal or resolve your pending roll first.');
  const secret=hexlify(randomBytes(32)),commitment=await game.commitmentFor(account,secret);
  saveRoll({secret,commitment});autoReveal=true;
  // Persistence precedes the signature. A failed request must never discard a potentially mined secret.
  await transact('Commit roll',()=>game.connect(signer).commitRoll(commitment));
  $('dice').classList.add('waiting');$('roll-info').textContent='Rolling… waiting for the reveal block.';
}
async function revealIfReady(manual=false){
  if(!ready || !account || wrongNetwork || busy || animating || revealChecking || (!autoReveal&&!manual))return;
  revealChecking=true;
  try{
    const roll=await game.rolls(account);pending=roll;if(roll.commitment===ZeroHash)return;
    const saved=savedRoll();if(!saved || saved.commitment!==roll.commitment){if(manual)throw new Error('Restore the secret saved before this roll was committed.');return;}
    // Robinhood Nitro RPC height is NOT the EVM block clock used by the contract.
    const [height,block]=await Promise.all([game.chainBlockNumber(),rpc.getBlock('latest')]);
    if(height>roll.entropyBlock+200n || BigInt(block.timestamp)>roll.deadline){autoReveal=false;status('Reveal expired. Resolve the roll in recovery controls; the reserved balance is forfeited.',true);return;}
    if(height<=roll.entropyBlock){status('Rolling… waiting for the EVM reveal block.');return;}
    autoReveal=false;
    const before=await game.player(account),beforeScore=await game.scores(seasonId,account);
    const receipt=await transact('Reveal roll',()=>game.connect(signer).revealRoll(saved.secret),false);
    // Remove only the confirmed roll secret, before any animation or optional read can fail.
    localStorage.removeItem(secretKey());pending=undefined;
    const events=receipt.logs.map(log=>{try{return(equal(log.address,cfg.game)?game:vault).interface.parseLog(log);}catch{return null;}});
    const rolled=events.find(e=>e?.name==='Rolled');
    if(rolled){const after=await game.player(account);me=after;const score=events.find(e=>e?.name==='ScoreChanged');const earned=score?score.args.score-beforeScore:0n;await playRoll(Number(before.position),Number(rolled.args.die1),Number(rolled.args.die2),Number(rolled.args.position),before.balance+earned-after.balance,earned,after.jailed);}
    await refresh();status('Roll revealed. Explore your landing square.');
  }finally{revealChecking=false;updateControls();}
}
async function playRoll(start,d1,d2,final,paid,earned,jailed){
  animating=true;updateControls();$('dice').classList.remove('waiting');
  const dice=$('dice').querySelectorAll('.die');dice[0].setAttribute('data-value',String(d1));dice[1].setAttribute('data-value',String(d2));$('dice').setAttribute('aria-label',`Rolled ${d1} and ${d2}`);$('dice').classList.add('rolling');
  try{
    await sleep(960);$('dice').classList.remove('rolling');
    const path=hopPath(start,d1,d2,final);
    for(const slot of path){positions.set(account.toLowerCase(),{address:account,position:slot});renderPieces(account);if(slot===0 && earned>0n){$('salary-chip').textContent=`+salary · ${fmt(earned)} IMD`;$('salary-chip').hidden=false;}if(!reduced())await sleep(180);}
    selectTile(final);$('landing-card').classList.add('landed');
    const original=(start+d1+d2)%40, chance=[2,7,17,22,33,36].includes(original);
    if(chance)$('landing-card').classList.add('chance');if(jailed)$('landing-card').classList.add('jailed');
    let outcome=jailed?'In jail. Pay bail or skip a roll to return.':chance?`Card revealed · ${final===0?'Advance to GO':paid>0n?`Pay ${fmt(paid)} IMD tax`:earned>0n?`Receive ${fmt(earned)} IMD`:'A quiet turn. Your next move awaits.'}`:`Landed on ${names[final]}.`;
    if(!special.has(final) && tiles[final]?.token!==ZeroAddress){outcome=`${fmt(paid>0n?paid:0n)} IMD rent paid. ${me.bankrupt?'You are out of play this season.':'You can buy a deed here.'}`;if(paid>0n){const credited=tiles[final].weight>0n?paid*80n/100n:0n;$('rent-flight').textContent=credited?`${fmt(credited)} IMD → holders`:`${fmt(paid)} IMD → pot`;$('rent-flight').hidden=false;}}
    $('landing-outcome').textContent=outcome;$('landing-outcome').hidden=false;$('announcer').textContent=`Rolled ${d1} and ${d2}. ${outcome}`;
    setTimeout(()=>{$('salary-chip').hidden=$('rent-flight').hidden=true;},reduced()?0:1700);
  }finally{animating=false;$('dice').classList.remove('rolling');renderPieces();updateControls();}
}
async function getQuote(){
  if(quoting)return;
  const slot=selected,input=$('buy-amount').value,slippageInput=$('slippage').value,amount=positive(input),slippage=Number(slippageInput);
  if(!Number.isFinite(slippage)||slippage<=0||slippage>5)throw new Error('Choose slippage above 0 and at most 5%.');
  quoting=true;$('quote').disabled=true;$('quote-output').textContent='Getting a fresh pool quote…';
  try{
    const out=await vault.quote.staticCall(slot,amount),minOut=out*BigInt(10000-Math.round(slippage*100))/10000n;if(!minOut)throw new Error('Quote too small. Increase the amount.');
    let display=`${out} raw token units`;try{const token=new Contract(tiles[slot].token,erc20,rpc);display=`${fmt(out,Number(await token.decimals()))} ${metadata.get(tiles[slot].token.toLowerCase())?.symbol||'tokens'}`;}catch{}
    if(selected!==slot||$('buy-amount').value!==input||$('slippage').value!==slippageInput)return;
    quoteState={slot,amount,minOut,time:Date.now(),input,slippage:slippageInput};$('quote-output').textContent=`Estimated ${display}. Minimum ${minOut} raw units. Valid for 60 seconds.`;
  }catch(error){quoteState=undefined;$('quote-output').textContent='Quote unavailable. Check the amount and try again.';throw error;}finally{quoting=false;updateControls();}
}
function bindActions(){
  action('connect',connect);action('add-chain',addChain);action('next-action',nextAction);action('retry',startRpc);action('roll',commit);action('join',join);action('reveal',()=>revealIfReady(true));
  action('motion',()=>{pausedEffects=!pausedEffects;document.body.classList.toggle('effects-paused',pausedEffects);$('motion').textContent=pausedEffects?'Resume effects':'Pause effects';$('motion').setAttribute('aria-pressed',String(pausedEffects));});
  action('deposit',()=>transact('Deposit',async()=>{const amount=positive($('balance-amount').value);await approve(cfg.currency,cfg.game,amount);return game.connect(signer).deposit(amount);}));
  action('withdraw',()=>transact('Withdraw',()=>{const amount=positive($('balance-amount').value);if(amount>me.balance-(pending?.exposure||0n))throw new Error('Choose an amount within your withdrawable balance.');return game.connect(signer).withdraw(amount);}));
  action('bail',()=>transact('Pay bail',()=>game.connect(signer).payBail()));action('skip',()=>transact('Skip jail roll',()=>game.connect(signer).skipJailRoll()));
  action('quote',getQuote);
  for(const id of ['buy-amount','slippage'])$(id).oninput=()=>{quoteState=undefined;$('quote-output').textContent='Amount changed. Get a fresh quote.';updateControls();};
  form('buy-form',()=>transact('Buy deed',async()=>{const q=quoteState;if(!q||q.slot!==selected||Date.now()-q.time>60000||q.input!==$('buy-amount').value||q.slippage!==$('slippage').value)throw new Error('Get a fresh quote first.');if(q.amount>season.maxBuy)throw new Error(`Use at most ${fmt(season.maxBuy)} IMD for this season.`);const lockDays=Number(/** @type {HTMLInputElement} */(document.querySelector('input[name="lock"]:checked')).value);await approve(cfg.currency,cfg.game,q.amount);return game.connect(signer)['buyDeed(uint8,uint256,uint256,uint8)'](q.slot,q.amount,q.minOut,lockDays);}));
  form('fund-form',()=>transact('Fund the pot',async()=>{const amount=positive($('fund-amount').value);await approve(cfg.currency,cfg.game,amount);return game.connect(signer).fundPot(amount);}));
  action('finalize',()=>transact('Finalize season',()=>game.connect(signer).finalizeSeason()));
  action('claim-prize',()=>transact('Claim prize',()=>game.connect(signer).claimPrize(BigInt($('prize-season').value))));
  action('claim-all',async()=>{if(claimingAll)return;claimingAll=true;updateControls();try{const ids=myDeeds.filter(d=>d.pending>0n).map(d=>d.id);for(const id of ids)await transact(`Claim rent · deed #${id}`,()=>game.connect(signer).claimRent(id));}finally{claimingAll=false;updateControls();}});
  action('sponsor',()=>transact('Sponsor tile',async()=>{const slot=selected,amount=BigInt($('sponsor-amount').value),rate=BigInt($('sponsor-rate').value);if(amount<=0n||rate<=0n)throw new Error('Enter positive raw token amounts.');await approve(tiles[slot].token,cfg.vault,amount);return vault.connect(signer).sponsorTile(slot,amount,rate);}));
  action('claim-sponsor',()=>transact('Claim sponsor tokens',()=>vault.connect(signer).claimSponsor(selected)));
  action('withdraw-sponsor',()=>transact('Withdraw sponsorship',()=>vault.connect(signer).withdrawSponsor(BigInt($('sponsor-season').value),selected)));
  action('expire',()=>transact('Resolve expired roll',()=>game.connect(signer).expireRoll(account)));
  action('export-secret',()=>{const saved=savedRoll();if(!saved)throw new Error('No saved roll secret was found.');const blob=new Blob([JSON.stringify({chainId:cfg.chainId,game:cfg.game,account,...saved},null,2)],{type:'application/json'});const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='swarmopoly-roll-recovery.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});
  action('import-secret',async()=>{await assertChain();const secret=$('recovery-secret').value.trim();if(!/^0x[0-9a-fA-F]{64}$/.test(secret))throw new Error('Use a 32-byte recovery secret: 0x followed by 64 hex characters.');const r=await game.rolls(account),p=await game.player(account);const expected=keccak256(AbiCoder.defaultAbiCoder().encode(['uint256','address','address','uint256','bytes32'],[cfg.chainId,cfg.game,account,p.nonce,secret]));if(expected!==r.commitment)throw new Error('This secret does not match your pending roll. Check your recovery file.');saveRoll({secret,commitment:r.commitment});autoReveal=true;await revealIfReady(true);});
  action('bind-pot',()=>transact('Bind SeasonPot',()=>pot.connect(signer).bindGame(cfg.game)));action('bind-vault',()=>transact('Bind DeedVault',()=>vault.connect(signer).bindGame(cfg.game)));
  action('pause',()=>transact('Set pause',()=>game.connect(signer).setPaused($('pause-rolls').checked,$('pause-buys').checked)));
  form('season-form',data=>transact('Start season',()=>game.connect(signer).startSeason(units(data.get('buyIn')),BigInt(String(data.get('days')))*86400n,units(data.get('bond')),units(data.get('maxBuy')))));
  form('listing-form',data=>transact('List tile',()=>{const slot=Number(data.get('slot'));if(special.has(slot))throw new Error('Choose one of the 28 property slots. Special squares cannot be listed.');const token=getAddress(String(data.get('token')));if(equal(token,cfg.currency)||token===ZeroAddress)throw new Error('Use a token paired with IMD, distinct from IMD itself.');const currencies=[cfg.currency,token].sort((a,b)=>BigInt(a)<BigInt(b)?-1:1);return game.connect(signer).listTile(slot,{currency0:currencies[0],currency1:currencies[1],fee:Number(data.get('fee')),tickSpacing:Number(data.get('spacing')),hooks:getAddress(String(data.get('hook')))},Number(data.get('tier')));}));
  form('params-form',data=>transact('Set parameters',()=>{const amounts=String(data.get('rents')).split(',').map(units);if(amounts.length!==8)throw new Error('Enter exactly eight rent amounts, separated by commas.');return game.connect(signer).setParams(BigInt(String(data.get('salary'))),BigInt(String(data.get('cooldown')))*3600n,amounts);}));
}
async function init(){
  drawBoard();bindActions();route();window.addEventListener('hashchange',()=>{route();$('main').focus();});
  [cfg,abi]=await Promise.all(['config','abi'].map(async name=>{const r=await fetch(`./${name}.json`);if(!r.ok)throw new Error(`Unable to load ${name}. Reload the page.`);return r.json();}));
  if(injected?.on){
    injected.on('accountsChanged',()=>{account=undefined;signer=undefined;me=undefined;pending=undefined;myDeeds=[];autoReveal=false;$('balance').textContent=$('claimable').textContent='—';$('balance-note').textContent='Connect your wallet to see your balance.';$('rent-summary').textContent='Connect to find your rent.';$('deeds').textContent='Connect your wallet to see your deeds.';$('my-piece').innerHTML=icon('imp');renderPieces();updateControls();status('Wallet account changed. Connect to continue.');});
    injected.on('chainChanged',chain=>{wrongNetwork=BigInt(chain)!==4663n;updateControls();status(wrongNetwork?'Switch to Robinhood Chain to continue.':'Robinhood Chain selected. Connect to continue.');});
    wrongNetwork=BigInt(await injected.request({method:'eth_chainId'}))!==4663n;
  }
  await startRpc();
  setInterval(()=>{if(!busy)refresh().catch(error=>{status(`Live update delayed: ${messageFor(error)}. Retry the connection.`,true);$('retry').hidden=false;});},12000);
  setInterval(()=>revealIfReady().catch(report),4000);setInterval(tick,1000);
}
init().catch(error=>{report(error);$('retry').hidden=false;});

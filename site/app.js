import { BrowserProvider, JsonRpcProvider, Contract, ZeroAddress, ZeroHash, parseUnits, formatUnits, randomBytes, hexlify, getAddress, AbiCoder, keccak256 } from './vendor/ethers.min.js';

const $ = id => document.getElementById(id);
const names = ['GO','Mediterranean Avenue','Community Chest','Baltic Avenue','Income Tax','Reading Railroad','Oriental Avenue','Chance','Vermont Avenue','Connecticut Avenue','Jail / Just Visiting','St. Charles Place','Electric Company','States Avenue','Virginia Avenue','Pennsylvania Railroad','St. James Place','Community Chest','Tennessee Avenue','New York Avenue','Free Parking','Kentucky Avenue','Chance','Indiana Avenue','Illinois Avenue','B. & O. Railroad','Atlantic Avenue','Ventnor Avenue','Water Works','Marvin Gardens','Go To Jail','Pacific Avenue','North Carolina Avenue','Community Chest','Pennsylvania Avenue','Short Line','Chance','Park Place','Luxury Tax','Boardwalk'];
const special = new Set([0,2,4,7,10,17,20,22,30,33,36,38]);
const colors = ['#926a43','#70b8be','#bf6ea7','#d78b47','#be534d','#d4ba4d','#6b9666','#466893'];
const erc20 = ['function approve(address,uint256) returns(bool)','function allowance(address,address) view returns(uint256)','function decimals() view returns(uint8)','function symbol() view returns(string)'];
let cfg, abi, rpc, wallet, signer, account, game, vault, pot, cash;
let seasonId = 0n, season, me, owner, selected = 1, quoteState, ready = false, busy = false, refreshing = false, autoReveal = true;
let tiles = [], deedIds = new Set(), joined = new Set(), logCursor = 0, visiblePositions = new Map();
const short = address => address.slice(0,6) + '…' + address.slice(-4);
const fmt = (value, decimals = 18) => Number(formatUnits(value, decimals)).toLocaleString(undefined, {maximumFractionDigits: 5});
const equal = (a,b) => a?.toLowerCase() === b?.toLowerCase();
const units = value => parseUnits(String(value).trim(), 18);
const status = (message, error = false) => { $('status').textContent = message; $('status').classList.toggle('error', error); };
const secretKey = () => `swarmopoly:${cfg.chainId}:${cfg.game.toLowerCase()}:${account.toLowerCase()}`;
function savedRoll() { try { return JSON.parse(localStorage.getItem(secretKey()) || 'null'); } catch { return null; } }
function saveRoll(value) { localStorage.setItem(secretKey(), JSON.stringify(value)); }
function report(error) { console.error(error); status(error.shortMessage || error.reason || error.message || String(error), true); }

function drawBoard() {
  names.forEach((name, slot) => {
    const button = document.createElement('button'); button.className = 'tile' + (slot % 10 === 0 ? ' corner' : ''); button.id = `tile-${slot}`;
    let row, col;
    if (slot <= 10) { row = 11; col = 11 - slot; }
    else if (slot <= 20) { row = 21 - slot; col = 1; }
    else if (slot <= 30) { row = 1; col = slot - 19; }
    else { row = slot - 29; col = 11; }
    button.style.gridRow = row; button.style.gridColumn = col;
    if (!special.has(slot)) button.style.setProperty('--color', colors[Math.min(7, Math.floor(slot / 5))]);
    for (const [cls, text] of [['number', String(slot).padStart(2,'0')], ['tile-name', name], ['tile-sub', special.has(slot) ? ' ' : 'Launch Day soon'], ['markers',' ']]) {
      const span = document.createElement('span'); span.className = cls; span.textContent = text; button.append(span);
    }
    button.setAttribute('aria-label', `${slot}: ${name}`);
    button.onclick = () => selectTile(slot); $('board').append(button);
  });
  selectTile(1);
}
function selectTile(slot) {
  document.querySelector('.tile.selected')?.classList.remove('selected'); selected = slot; quoteState = null;
  $(`tile-${slot}`)?.classList.add('selected'); $('tile-number').textContent = `SQUARE / ${String(slot).padStart(2,'0')}`;
  $('tile-name').textContent = names[slot];
  const tile = tiles[slot];
  $('tile-description').textContent = special.has(slot) ? 'A classic neighborhood stop.' : tile?.token && tile.token !== ZeroAddress ? `Tier ${tile.tier} · ${short(tile.token)} · ${fmt(tile.assets, 0)} raw tokens in deeds` : 'Launch Day soon';
  $('quote-output').textContent = 'Get a fresh quote before buying.'; updateControls();
}
function updateControls() {
  const enabled = ready && !!account && !busy;
  const listed = tiles[selected]?.token && tiles[selected].token !== ZeroAddress;
  for (const id of ['deposit','withdraw','claim-prize','finalize']) $(id).disabled = !enabled;
  for (const id of ['sponsor','claim-sponsor','withdraw-sponsor']) $(id).disabled = !enabled || !listed;
  $('join').disabled = !enabled || me?.season === seasonId;
  $('quote').disabled = !ready || !listed || busy;
  $('buy').disabled = !enabled || !listed || !quoteState || !me?.canBuy || Number(me.position) !== selected || me.bankrupt;
  $('roll').disabled = !enabled || me?.season !== seasonId || me?.bankrupt || me?.jailed;
  $('bail').hidden = $('skip').hidden = !me?.jailed || me?.bankrupt;
  $('admin').hidden = !account || !equal(owner, account);
}
async function assertChain() {
  if (!window.ethereum || !signer) throw new Error('Connect a wallet first.');
  const chain = await window.ethereum.request({method:'eth_chainId'});
  if (BigInt(chain) !== BigInt(cfg.chainId)) throw new Error('Switch your wallet to Robinhood Chain 4663.');
  if (!equal(await signer.getAddress(), account)) throw new Error('Wallet account changed. Reconnect.');
}
async function transact(label, operation) {
  if (busy) return;
  busy = true; updateControls();
  try {
    await assertChain(); status(`${label}: confirm in your wallet.`);
    const tx = await operation(); status(`${label}: waiting for confirmation (${short(tx.hash)}).`);
    const receipt = await tx.wait();
    if (!receipt || receipt.status !== 1) throw new Error(`${label} failed.`);
    status(`${label} confirmed.`);
    return receipt;
  } finally { busy = false; await refresh().catch(report); updateControls(); }
}
async function approve(token, spender, amount) {
  const instance = new Contract(token, erc20, signer);
  if (await instance.allowance(account, spender) < amount) {
    status('Approve the exact token amount in your wallet.');
    const tx = await instance.approve(spender, amount); await tx.wait();
    await assertChain();
  }
}
const action = (id, fn) => { $(id).onclick = () => Promise.resolve().then(fn).catch(report); };
const form = (id, fn) => { $(id).onsubmit = event => { event.preventDefault(); Promise.resolve().then(() => fn(new FormData(event.target))).catch(report); }; };

async function connect() {
  if (!window.ethereum) throw new Error('An Ethereum-compatible browser wallet is required.');
  await window.ethereum.request({method:'eth_requestAccounts'});
  try { await window.ethereum.request({method:'wallet_switchEthereumChain',params:[{chainId:'0x1237'}]}); }
  catch (error) {
    if (error.code !== 4902) throw error;
    await window.ethereum.request({method:'wallet_addEthereumChain',params:[{chainId:'0x1237',chainName:cfg.chainName,rpcUrls:[cfg.rpcUrl],blockExplorerUrls:[cfg.explorerUrl],nativeCurrency:{name:'Ether',symbol:'ETH',decimals:18}}]});
    await window.ethereum.request({method:'wallet_switchEthereumChain',params:[{chainId:'0x1237'}]});
  }
  wallet = new BrowserProvider(window.ethereum, 'any'); signer = await wallet.getSigner(); account = await signer.getAddress();
  $('connect').textContent = short(account); await refresh();
}
async function verifyDeployment() {
  if (![cfg.game,cfg.vault,cfg.pot].every(address => address && getAddress(address) !== ZeroAddress) || !Number.isSafeInteger(cfg.deploymentBlock) || cfg.deploymentBlock < 0) return false;
  if ((await rpc.getNetwork()).chainId !== 4663n) throw new Error('Configured RPC has the wrong chain ID.');
  const code = await Promise.all([cfg.game,cfg.vault,cfg.pot,cfg.currency,cfg.poolManager].map(address => rpc.getCode(address)));
  if (code.some(value => value === '0x')) throw new Error('Deployment configuration points to an address without code.');
  game = new Contract(cfg.game,abi.SwarmopolyGame,rpc); vault = new Contract(cfg.vault,abi.DeedVault,rpc); pot = new Contract(cfg.pot,abi.SeasonPot,rpc); cash = new Contract(cfg.currency,erc20,rpc);
  const [v,p,c,m,d,vc,pc] = await Promise.all([game.vault(),game.pot(),game.currency(),vault.poolManager(),cash.decimals(),vault.currency(),pot.currency()]);
  if (!equal(v,cfg.vault) || !equal(p,cfg.pot) || !equal(c,cfg.currency) || !equal(m,cfg.poolManager) || d !== 18n || !equal(vc,cfg.currency) || !equal(pc,cfg.currency)) throw new Error('Deployment dependency verification failed.');
  logCursor = cfg.deploymentBlock;
  owner = await game.owner(); return true;
}
async function syncLogs() {
  const head = await rpc.getBlockNumber();
  // Retain sets but replay the last 12 blocks, so a missed/reorganized event is not lost.
  for (let start = Math.max(cfg.deploymentBlock,logCursor - 12); start <= head; start += 2000) {
    const end = Math.min(head,start + 1999);
    const [players,deeds] = await Promise.all([game.queryFilter(game.filters.Joined(),start,end),vault.queryFilter(vault.filters.DeedBought(),start,end)]);
    players.forEach(log => joined.add(log.args.player)); deeds.forEach(log => deedIds.add(log.args.id.toString()));
  }
  logCursor = head + 1;
}
async function refresh() {
  if (!ready || refreshing) return;
  refreshing = true;
  try {
    seasonId = await game.currentSeason(); season = await game.seasons(seasonId);
    const [available, list, tileList, rollsPaused, buysPaused] = await Promise.all([pot.available(),game.leaders(seasonId),Promise.all(names.map((_,i)=>vault.tile(i))),game.rollsPaused(),game.buysPaused()]);
    tiles = tileList;
    $('pot-value').replaceChildren(document.createTextNode(`${fmt(available)} `)); const small=document.createElement('small');small.textContent='IMD';$('pot-value').append(small);
    $('season-label').textContent = seasonId ? `Season ${seasonId}${season.finalized ? ' · Finalized' : ''}` : 'Awaiting the first season';
    $('season-end').textContent = seasonId ? `Ends ${new Date(Number(season.end)*1000).toLocaleString()}` : 'Owner setup pending';
    $('leaders').replaceChildren();
    for (const who of list) {
      if (who === ZeroAddress) continue;
      const row = document.createElement('li'); row.textContent = short(who);
      const score = document.createElement('strong'); score.textContent = `${fmt(await game.scores(seasonId,who))} IMD`; row.append(score); $('leaders').append(row);
    }
    await syncLogs(); visiblePositions = new Map();
    for (const who of joined) {
      const p = await game.player(who); if (p.season !== seasonId) continue;
      const slot = Number(p.position); if (!visiblePositions.has(slot)) visiblePositions.set(slot,[]); visiblePositions.get(slot).push(who);
    }
    tiles.forEach((tile,slot) => {
      const element = $(`tile-${slot}`); const players=visiblePositions.get(slot)||[];
      element.querySelector('.tile-sub').textContent = special.has(slot) ? '' : tile.token === ZeroAddress ? 'Launch Day soon' : `Tier ${tile.tier}`;
      const markers=element.querySelector('.markers');markers.textContent=players.length ? '●'.repeat(Math.min(players.length,3)) + (players.length > 3 ? `+${players.length-3}` : '') : '';
      markers.classList.toggle('mine',players.some(who=>equal(who,account)));element.title=`${names[slot]}${players.length ? '\nPlayers: '+players.map(short).join(', ') : ''}`;
    });
    if (account) {
      me = await game.player(account); const pending = await game.rolls(account);
      $('balance').textContent = fmt(me.balance);
      $('balance-note').textContent = pending.exposure ? `${fmt(pending.exposure)} IMD is committed to this roll; ${fmt(me.balance-pending.exposure)} IMD is withdrawable.` : 'Available to withdraw. Rent, tax and bail use this balance.';
      $('player-state').textContent = me.season !== seasonId ? 'Join to play' : me.bankrupt ? 'Out this season' : me.jailed ? 'In jail' : `Square ${me.position}`;
      $('roll-info').textContent = pending.commitment !== ZeroHash ? 'Committed. Waiting for the reveal block…' : me.nextRoll > BigInt(Math.floor(Date.now()/1000)) ? `Next roll: ${new Date(Number(me.nextRoll)*1000).toLocaleString()}` : 'Your next move is ready.';
      $('roll').textContent = pending.commitment !== ZeroHash ? 'Roll committed' : 'Commit & roll';
      $('reveal').hidden = $('recover').hidden = pending.commitment === ZeroHash;
      $('export-secret').hidden = !savedRoll() || pending.commitment === ZeroHash;
      await renderDeeds();
    }
    $('pause-rolls').checked=rollsPaused; $('pause-buys').checked=buysPaused;
    updateControls();
    if (account) {
      const pending = await game.rolls(account);
      if (pending.commitment !== ZeroHash || rollsPaused) $('roll').disabled = true;
      if (buysPaused) $('buy').disabled=true;
    }
  } finally { refreshing=false; }
}
async function renderDeeds() {
  $('deeds').replaceChildren();
  for (const id of deedIds) {
    const deed = await vault.deeds(id); if (!equal(deed.holder,account)) continue;
    const pending = await vault.pendingRent(id); if (deed.shares === 0n && pending === 0n) continue;
    const row = document.createElement('div');row.className='deed-row'; const title=document.createElement('strong');title.textContent=`#${id} · ${names[Number(deed.tile)]}`;row.append(title);
    const info=document.createElement('p'); info.textContent=`${fmt(pending)} IMD rent · ${deed.shares ? 'Redeem from '+new Date(Number(deed.redeemAt)*1000).toLocaleString() : 'Deed redeemed'}`;row.append(info);
    const claim=document.createElement('button');claim.textContent='Claim rent';claim.disabled=pending===0n;claim.onclick=()=>transact('Claim rent',()=>game.connect(signer).claimRent(id)).catch(report);row.append(claim);
    const redeem=document.createElement('button');redeem.textContent='Redeem tokens';redeem.disabled=deed.shares===0n || Number(deed.redeemAt)*1000>Date.now();redeem.onclick=()=>transact('Redeem deed',()=>vault.connect(signer).redeem(id)).catch(report);row.append(redeem);$('deeds').append(row);
  }
  if (!$('deeds').children.length) $('deeds').textContent='Your first deed is waiting around the corner.';
}
async function commit() {
  if (!ready) return;
  const pending = await game.rolls(account);if(pending.commitment!==ZeroHash) throw new Error('Reveal or resolve your pending roll first.');
  const secret=hexlify(randomBytes(32));const commitment=await game.commitmentFor(account,secret);
  // Persist BEFORE requesting a signature. Losing this secret causes the timeout penalty.
  saveRoll({secret,commitment});autoReveal=true;$('dice').classList.add('rolling');
  try { await transact('Commit roll',()=>game.connect(signer).commitRoll(commitment)); }
  finally { $('dice').classList.remove('rolling'); }
}
async function revealIfReady(manual=false) {
  if (!ready || !account || busy || (!autoReveal && !manual)) return;
  const pending=await game.rolls(account);if(pending.commitment===ZeroHash) return;
  const saved=savedRoll();if(!saved || saved.commitment!==pending.commitment) { if(manual) throw new Error('Restore the secret saved before committing.');return; }
  const [height,block]=await Promise.all([game.chainBlockNumber(),rpc.getBlock('latest')]);
  if (height > pending.entropyBlock + 200n || BigInt(block.timestamp)>pending.deadline) {autoReveal=false;status('Reveal window expired. Resolve the roll to release committed accounting; the timeout penalty applies.',true);return;}
  if(height<=pending.entropyBlock) {if(manual)status('Still waiting for the EVM reveal block.');return;}
  autoReveal=false;$('dice').classList.add('rolling');
  try {
    const receipt=await transact('Reveal roll',()=>game.connect(signer).revealRoll(saved.secret));
    if (!receipt) return;
    for(const log of receipt.logs) {try{const event=game.interface.parseLog(log);if(event?.name==='Rolled'){$('dice').textContent=`${['','⚀','⚁','⚂','⚃','⚄','⚅'][Number(event.args.die1)]} ${['','⚀','⚁','⚂','⚃','⚄','⚅'][Number(event.args.die2)]}`;selectTile(Number(event.args.position));}}catch{}}
    localStorage.removeItem(secretKey());status('Roll revealed. Explore your landing square.');
  } finally {$('dice').classList.remove('rolling');}
}
async function getQuote() {
  const slot=selected,input=$('buy-amount').value,slippageInput=$('slippage').value;
  const amount=units(input);if(amount<=0n)throw new Error('Enter a positive buy amount.');
  const slippage=Number(slippageInput);if(!Number.isFinite(slippage)||slippage<=0||slippage>5)throw new Error('Choose slippage above 0 and at most 5%.');
  const token=tiles[slot].token;const out=await vault.quote.staticCall(slot,amount);
  const minOut=out*BigInt(10000-Math.round(slippage*100))/10000n;if(!minOut)throw new Error('Quote too small.');
  let display=`${out} raw tokens`;try{const decimals=await new Contract(token,erc20,rpc).decimals();display=`${fmt(out,Number(decimals))} tokens`;}catch{}
  if(selected!==slot || $('buy-amount').value!==input || $('slippage').value!==slippageInput) return;
  quoteState={slot,amount,minOut,time:Date.now(),input,slippage:slippageInput};
  $('quote-output').textContent=`Estimated ${display}. Minimum ${minOut} raw units. Quote expires in 60 seconds.`;updateControls();
}

async function init() {
  drawBoard();
  [cfg,abi]=await Promise.all([fetch('./config.json').then(r=>r.json()),fetch('./abi.json').then(r=>r.json())]);
  rpc=new JsonRpcProvider(cfg.rpcUrl);ready=await verifyDeployment();
  status(ready ? 'Connected to Robinhood Chain. Board updates every 12 seconds.' : 'Launch setup in progress. Contract addresses will appear after the verified deployment.');
  action('connect',connect);action('roll',commit);action('reveal',()=>revealIfReady(true));
  action('deposit',()=>transact('Deposit',async()=>{const amount=units($('balance-amount').value);await approve(cfg.currency,cfg.game,amount);return game.connect(signer).deposit(amount);}));
  action('withdraw',()=>transact('Withdraw',()=>game.connect(signer).withdraw(units($('balance-amount').value))));
  action('join',()=>transact('Join season',async()=>{await approve(cfg.currency,cfg.game,season.buyIn);return game.connect(signer).joinSeason();}));
  action('bail',()=>transact('Pay bail',()=>game.connect(signer).payBail()));action('skip',()=>transact('Skip jail roll',()=>game.connect(signer).skipJailRoll()));
  action('quote',getQuote);
  for(const id of ['buy-amount','slippage']) $(id).oninput=()=>{quoteState=null;updateControls();};
  form('buy-form',()=>transact('Buy deed',async()=>{const q=quoteState;if(!q||q.slot!==selected||Date.now()-q.time>60000||q.input!==$('buy-amount').value||q.slippage!==$('slippage').value)throw new Error('Get a fresh quote first.');const lockDays=Number($('lock').value);await approve(cfg.currency,cfg.game,q.amount);return game.connect(signer)['buyDeed(uint8,uint256,uint256,uint8)'](q.slot,q.amount,q.minOut,lockDays);}));
  action('finalize',()=>transact('Finalize season',()=>game.connect(signer).finalizeSeason()));
  action('claim-prize',()=>transact('Claim prize',()=>game.connect(signer).claimPrize(BigInt($('prize-season').value))));
  action('sponsor',()=>transact('Sponsor tile',async()=>{const slot=selected;const amount=BigInt($('sponsor-amount').value);await approve(tiles[slot].token,cfg.vault,amount);return vault.connect(signer).sponsorTile(slot,amount,BigInt($('sponsor-rate').value));}));
  action('claim-sponsor',()=>transact('Claim sponsor tokens',()=>vault.connect(signer).claimSponsor(selected)));
  action('withdraw-sponsor',()=>transact('Withdraw sponsorship',()=>vault.connect(signer).withdrawSponsor(BigInt($('sponsor-season').value),selected)));
  action('expire',()=>transact('Resolve expired roll',()=>game.connect(signer).expireRoll(account)));
  action('export-secret',()=>{const saved=savedRoll();if(!saved)throw new Error('No saved secret.');const blob=new Blob([JSON.stringify({chainId:cfg.chainId,game:cfg.game,account,...saved},null,2)],{type:'application/json'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='swarmopoly-roll-recovery.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});
  action('import-secret',async()=>{const secret=$('recovery-secret').value.trim();if(!/^0x[0-9a-fA-F]{64}$/.test(secret))throw new Error('Use the 32-byte recovery secret.');const r=await game.rolls(account);const p=await game.player(account);const expected=keccak256(AbiCoder.defaultAbiCoder().encode(['uint256','address','address','uint256','bytes32'],[cfg.chainId,cfg.game,account,p.nonce,secret]));if(expected!==r.commitment)throw new Error('This secret does not match the pending commitment.');saveRoll({secret,commitment:r.commitment});autoReveal=true;await revealIfReady(true);});
  action('bind-pot',()=>transact('Bind pot',()=>pot.connect(signer).bindGame(cfg.game)));action('bind-vault',()=>transact('Bind vault',()=>vault.connect(signer).bindGame(cfg.game)));
  action('pause',()=>transact('Set pause',()=>game.connect(signer).setPaused($('pause-rolls').checked,$('pause-buys').checked)));
  form('season-form',data=>transact('Start season',()=>game.connect(signer).startSeason(units(data.get('buyIn')),BigInt(data.get('days'))*86400n,units(data.get('bond')),units(data.get('maxBuy')))));
  form('listing-form',data=>transact('List tile',()=>{const token=getAddress(data.get('token'));const currencies=[cfg.currency,token].sort((a,b)=>BigInt(a)<BigInt(b)?-1:1);return game.connect(signer).listTile(Number(data.get('slot')),{currency0:currencies[0],currency1:currencies[1],fee:Number(data.get('fee')),tickSpacing:Number(data.get('spacing')),hooks:getAddress(data.get('hook'))},Number(data.get('tier')));}));
  form('params-form',data=>transact('Set parameters',()=>{const rents=data.get('rents').split(',').map(units);if(rents.length!==8)throw new Error('Enter exactly eight rent tiers.');return game.connect(signer).setParams(BigInt(data.get('salary')),BigInt(data.get('cooldown'))*3600n,rents);}));
  window.ethereum?.on('accountsChanged',()=>location.reload());window.ethereum?.on('chainChanged',()=>location.reload());
  await refresh();setInterval(()=>refresh().catch(report),12000);setInterval(()=>revealIfReady().catch(report),4000);
}
init().catch(report);

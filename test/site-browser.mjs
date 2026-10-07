import assert from 'node:assert/strict';
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fixture } from './site-fixture.mjs';
const require=createRequire(process.env.CHECK_PACKAGE || new URL('../site/tooling/package.json',import.meta.url));
const {chromium}=require('playwright');const AxeBuilder=require('@axe-core/playwright').default;
const root=new URL('../dist/',import.meta.url),results=[];
const server=http.createServer(async(req,res)=>{try{const path=decodeURIComponent(req.url.split('?')[0]);if(!path.startsWith('/preview/')||path.includes('..'))throw Error('Not found');const file=path.slice(9)||'index.html';const data=await readFile(new URL(file,root));res.setHeader('Content-Type',file.endsWith('.html')?'text/html':file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':file.endsWith('.json')?'application/json':file.endsWith('.svg')?'image/svg+xml':'application/octet-stream');res.end(data);}catch{res.statusCode=404;res.end('Not found');}});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const url=`http://127.0.0.1:${server.address().port}/preview/`;
const browser=await chromium.launch({headless:true});
async function scenario(name,fn){try{await fn();results.push({name,result:'pass'});console.log('PASS',name);}catch(error){console.error('FAIL',name,error);results.push({name,result:'fail',error:error.message});throw error;}}
async function setup(options={}){const context=await browser.newContext({viewport:{width:1440,height:1000},reducedMotion:'reduce'}),page=await context.newPage(),mock=fixture(options),errors=[];page.on('pageerror',e=>errors.push(e.message));await mock.install(page);await page.goto(url);await page.waitForFunction(()=>document.querySelector('#pot-value').textContent!=='—');await page.waitForFunction(()=>document.querySelector('#activity').textContent!=='Finding recent moves…');return{context,page,mock,errors};}
async function visible(page,selector){return page.locator(selector).isVisible();}
async function waitText(page,id,text){await page.waitForFunction(({id,text})=>document.getElementById(id).textContent.includes(text),{id,text});}
async function waitIdle(page){await page.waitForFunction(()=>!document.querySelector('#deposit').disabled);}
async function tx(page,mock,selector,name){const before=mock.state.calls.filter(c=>c.name===name).length;await page.locator(selector).click();await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('confirmed.'));assert.equal(mock.state.calls.filter(c=>c.name===name).length,before+1);await waitIdle(page);}
try{
  await scenario('launch, no wallet, navigation, mobile ordering, local assets, keyboard, axe',async()=>{
    const {context,page,errors}=await setup({noSeason:true,noWallet:true});assert.equal(await page.locator('.tile').count(),40);assert.equal(await page.locator('.tile.vacant').count(),26);
    await page.locator('#next-action').click();assert.ok(await visible(page,'#wallet-help'));await page.locator('#add-chain').click();await waitText(page,'status','wallet browser');
    await page.locator('#tile-8').click();await waitText(page,'tile-name','Vermont Avenue');await page.locator('#square-select').selectOption('30');await waitText(page,'tile-name','Go to Jail');
    await page.locator('nav a[href="#swarm"]').click();assert.ok(await visible(page,'#page-swarm'));assert.ok(await page.locator('#deposit').isDisabled());
    await page.locator('nav a[href="#leaders"]').click();assert.ok(await visible(page,'#page-leaders'));assert.ok(await page.locator('#fund-pot').isDisabled());
    await page.locator('nav a[href="#board"]').click();assert.equal(await visible(page,'#owner-nav'),false);
    for(const width of [1440,1000,760,759,390,320]){await page.setViewportSize({width,height:1000});const metrics=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth,board:document.querySelector('#board').getBoundingClientRect().toJSON(),turn:document.querySelector('.turn-panel').getBoundingClientRect().toJSON(),font:document.fonts.check('16px "Space Grotesk"')}));assert.ok(metrics.scroll<=width,`overflow at ${width}`);assert.ok(metrics.font);if(width<760)assert.ok(metrics.turn.top<metrics.board.top);}
    await page.setViewportSize({width:390,height:844});const mobileAxe=await new AxeBuilder({page}).analyze();assert.deepEqual(mobileAxe.violations.map(v=>v.id),[]);
    await page.setViewportSize({width:1440,height:1000});await page.evaluate(()=>document.activeElement.blur());await page.keyboard.press('Control+Home');await page.locator('.skip-link').focus();await page.keyboard.press('Enter');assert.equal(await page.evaluate(()=>document.activeElement.id),'main');await page.keyboard.press('Tab');assert.ok(await page.evaluate(()=>getComputedStyle(document.activeElement).outlineStyle!=='none'));
    const axe=await new AxeBuilder({page}).analyze();assert.deepEqual(axe.violations.map(v=>v.id),[]);
    await page.evaluate(()=>document.documentElement.style.fontSize='200%');assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.evaluate(()=>document.documentElement.style.fontSize='');
    assert.equal(await page.locator('.tile.vacant').first().evaluate(el=>getComputedStyle(el,'::after').animationName),'none');
    await page.locator('nav a[href="./rules.html"]').click();await page.waitForURL('**/rules.html');assert.ok((await page.textContent('main')).includes('24 hours'));const rulesAxe=await new AxeBuilder({page}).analyze();assert.deepEqual(rulesAxe.violations.map(v=>v.id),[]);
    assert.deepEqual(errors,[]);await context.close();
  });
  await scenario('wallet join, approval amount, deposit, withdrawal, pot funding and account reset',async()=>{
    const {context,page,mock,errors}=await setup();await page.locator('#connect').click();await waitText(page,'next-action','Join season');await tx(page,mock,'#next-action','joinSeason');assert.equal(mock.state.calls[0].name,'approve');assert.equal(mock.state.calls[0].args[1],10n*10n**18n);
    await page.locator('nav a[href="#swarm"]').click();await page.locator('#balance-amount').fill('5');await tx(page,mock,'#deposit','deposit');await waitIdle(page);await tx(page,mock,'#withdraw','withdraw');assert.equal(mock.state.balance,100n*10n**18n);
    await page.locator('#balance-amount').fill('0');const count=mock.state.calls.length;await page.locator('#deposit').click();await waitText(page,'status','greater than zero');assert.equal(mock.state.calls.length,count);
    await page.locator('nav a[href="#leaders"]').click();await page.locator('#fund-amount').fill('7.5');await tx(page,mock,'#fund-pot','fundPot');assert.equal(mock.state.calls.at(-1).args[0],75n*10n**17n);assert.ok(await page.locator('.toast a').count()>0);
    await page.evaluate(()=>window.walletListeners.accountsChanged([]));assert.equal(await page.locator('#claimable').textContent(),'—');assert.equal(await visible(page,'#owner-nav'),false);assert.deepEqual(errors,[]);await context.close();
  });
  await scenario('persisted commit, EVM reveal clock, dice landing, quote invalidation, deed locks, claim and redeem',async()=>{
    const {context,page,mock,errors}=await setup();mock.state.joined=true;
    await page.locator('#connect').click();await waitText(page,'next-action','Roll the dice');await tx(page,mock,'#next-action','commitRoll');assert.ok(await page.evaluate(()=>Object.keys(localStorage).some(k=>k.startsWith('swarmopoly:'))));
    await waitText(page,'turn-title','Rolling');await page.locator('#reveal').click();await waitText(page,'status','EVM reveal block');assert.equal(mock.state.calls.filter(c=>c.name==='revealRoll').length,0,'RPC height must not unlock reveal');
    mock.advanceReveal();await page.locator('#reveal').click();await waitText(page,'status','Roll revealed');await waitText(page,'tile-name','Reading Railroad');assert.equal(await page.locator('#dice').getAttribute('aria-label'),'Rolled 3 and 4');assert.equal(await page.evaluate(()=>Object.keys(localStorage).filter(k=>k.startsWith('swarmopoly:')).length),0);
    await page.locator('#buy-amount').fill('2');await page.locator('#quote').click();await waitText(page,'quote-output','Estimated');assert.equal(await page.locator('#buy').isDisabled(),false);await page.locator('#slippage').fill('2');assert.equal(await page.locator('#buy').isDisabled(),true);await page.locator('#quote').click();await waitText(page,'quote-output','Estimated');await page.locator('input[name="lock"][value="30"]').check();await tx(page,mock,'#buy','buyDeed');assert.equal(mock.state.calls.at(-1).args[3],30n);assert.equal(mock.state.calls.at(-1).args[2],mock.state.quote*98n/100n);
    await page.locator('nav a[href="#swarm"]').click();await waitText(page,'deeds','Reading Railroad');assert.ok((await page.locator('.lock-clock').textContent()).includes('29d'));assert.equal(await page.getByRole('button',{name:'Redeem tokens',exact:true}).isDisabled(),true);
    await tx(page,mock,'#claim-all','claimRent');await waitText(page,'claimable','0 IMD');
    mock.state.deeds.get('1')[4]=1n;await page.reload();await page.locator('#connect').click();await waitText(page,'deeds','Unlocked');await tx(page,mock,'#deeds button:last-child','redeem');assert.equal(mock.state.deeds.get('1')[2],0n);assert.deepEqual(errors,[]);await context.close();
  });
  await scenario('owner visibility, bindGame one-shot state, listing, parameters, pause and season start',async()=>{
    const {context,page,mock,errors}=await setup({owner:true,noSeason:true});mock.state.bound=false;await page.locator('#connect').click();await page.locator('#owner-nav').click();assert.ok(await visible(page,'#admin'));
    await tx(page,mock,'#bind-pot','bindGame');assert.ok(await page.locator('#bind-pot').isDisabled());assert.equal(await page.locator('#bind-vault').isDisabled(),false);await tx(page,mock,'#bind-vault','bindGame');assert.ok(await page.locator('#bind-vault').isDisabled());
    await page.locator('#listing-form [name="token"]').fill('0x3333333333333333333333333333333333333333');await tx(page,mock,'#listing-form button','listTile');
    await tx(page,mock,'#params-form button','setParams');await page.locator('#pause-rolls').check();await tx(page,mock,'#pause','setPaused');assert.equal(mock.state.paused,true);
    await tx(page,mock,'#season-form button','startSeason');assert.equal(mock.state.season,1n);assert.deepEqual(errors,[]);await context.close();
  });
  await scenario('wrong wallet chain offers a switch and returns to the same game',async()=>{
    const {context,page,mock}=await setup();await page.locator('#connect').click();await waitText(page,'next-action','Join season');mock.state.chain='0x1';await page.evaluate(()=>window.walletListeners.chainChanged('0x1'));await waitText(page,'player-state','Wrong network');assert.ok(await page.locator('#deposit').isDisabled());await page.locator('#next-action').click();await waitText(page,'next-action','Join season');assert.equal(mock.state.chain,'0x1237');await context.close();
  });
  await scenario('Chance relocation, jail bars and bail recovery',async()=>{
    for(const jail of [false,true]){
      const {context,page,mock,errors}=await setup();mock.state.joined=true;mock.state.position=jail?25:1;mock.state.die1=3;mock.state.die2=jail?2:3;mock.state.rollFinal=jail?10:0;
      await page.locator('#connect').click();await waitText(page,'next-action','Roll the dice');await tx(page,mock,'#next-action','commitRoll');mock.advanceReveal();await page.locator('#reveal').click();await waitText(page,'status','Roll revealed');
      if(jail){assert.ok(await page.locator('#landing-card').evaluate(el=>el.classList.contains('jailed')));await tx(page,mock,'#bail','payBail');assert.equal(await page.locator('#landing-card').evaluate(el=>el.classList.contains('jailed')),false);await waitText(page,'landing-outcome','Out of jail');}
      else{assert.ok(await page.locator('#landing-card').evaluate(el=>el.classList.contains('chance')));await waitText(page,'landing-outcome','Advance to GO');}
      assert.deepEqual(errors,[]);await context.close();
    }
  });
  console.log(JSON.stringify({results},null,2));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}

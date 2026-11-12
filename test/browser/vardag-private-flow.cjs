// Browser UI proof against demo-vardag-privacy on localhost only.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright-core');
const fs=require('node:fs');
const path=require('node:path');
const out=process.env.VARDAG_TEST_OUTPUT;
if(!out) throw Error('VARDAG_TEST_OUTPUT is required.');
const fixture=JSON.parse(fs.readFileSync(path.join(out,'ui-fixture.json'),'utf8'));
(async()=>{
 const browser=await chromium.launch({executablePath:'/usr/bin/google-chrome',headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const context=await browser.newContext({viewport:{width:390,height:844},colorScheme:'dark'});
 const page=await context.newPage(); const errors=[],blocked=[],checks=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',route=>{
  const host=new URL(route.request().url()).hostname;
  if(['127.0.0.1','localhost','www.gstatic.com','fonts.gstatic.com'].includes(host)) return route.continue();
  blocked.push(host); return route.abort();
 });
 async function semantics(){const s=page.locator('flt-semantics-placeholder');await s.waitFor({state:'attached',timeout:60000});await s.evaluate(e=>e.click());await page.waitForTimeout(1000);}
 try {
  await page.goto('http://localhost:8793/',{waitUntil:'domcontentloaded',timeout:60000});
  await semantics();
  await page.screenshot({path:path.join(out,'ui-dark-login.png')});
  await page.getByRole('textbox',{name:'E-post'}).fill(fixture.parentEmail);
  await page.getByRole('textbox',{name:'Lösenord'}).fill(fixture.password);
  await page.getByRole('button',{name:'Logga in',exact:true}).click();
  await page.getByRole('button',{name:/Kalender/}).waitFor({timeout:45000});
  await page.screenshot({path:path.join(out,'ui-dark-home.png')});
  checks.push('signed in to the local test family in dark mode');
  await page.getByRole('button',{name:/Kalender/}).click();
  await page.waitForTimeout(12000);
  await page.mouse.click(180, 496);
  await page.waitForTimeout(2000);
  await page.screenshot({path:path.join(out,'ui-dark-detail-final.png')});
  await page.getByRole('button',{name:'Ändra aktivitet'}).click({timeout:10000});
  await page.waitForTimeout(1000);
  await page.screenshot({path:path.join(out,'ui-dark-menu-final.png')});
  fs.writeFileSync(path.join(out,'ui-dark-menu-semantics.html'),await page.locator('flt-semantics-host').innerHTML());
  await page.getByRole('menuitem',{name:'Redigera'}).click();
  await page.getByRole('button',{name:'Flytta bara detta tillfälle'}).click();
  await page.screenshot({path:path.join(out,'ui-dark-move-final.png')});
  await page.getByRole('textbox',{name:'Datum ÅÅÅÅ-MM-DD'}).fill(fixture.nextDate);
  await page.getByRole('button',{name:'Flytta',exact:true}).click();
  await page.waitForTimeout(3000);
  const crypto=require('node:crypto');
  const id='moved_'+crypto.createHash('sha256').update(fixture.seriesId+'|'+fixture.date).digest('hex');
  const root='http://127.0.0.1:8280/v1/projects/demo-vardag-privacy/databases/(default)/documents';
  const read=async p=>{const r=await fetch(root+'/'+p,{headers:{Authorization:'Bearer owner'}}); if(!r.ok)throw Error('Emulator read failed '+r.status);return (await r.json()).fields;};
  const marker=await read('planner_events/'+id);
  const detail=await read('private_activities/'+fixture.parent+'/events/'+id);
  if(marker.title.stringValue!=='Privat' || detail.title.stringValue!=='Privat testträning' || marker.date.stringValue!==fixture.nextDate) throw Error('Unexpected moved activity or privacy data');
  checks.push('private recurring occurrence moved in the web UI and private detail remains separate');

  const sem = await page.locator('flt-semantics-host').innerHTML();
  fs.writeFileSync(path.join(out,'ui-dark-detail-semantics.html'),sem);
  await page.screenshot({path:path.join(out,'ui-dark-calendar.png')});
  const labels=await page.locator('flt-semantics[aria-label]').evaluateAll(es=>es.map(e=>({role:e.getAttribute('role'),label:e.getAttribute('aria-label')})));
  fs.writeFileSync(path.join(out,'ui-dark-calendar-labels.json'),JSON.stringify(labels,null,2));
  if(errors.length || blocked.length) throw Error('Unexpected browser or external request');
  checks.push('calendar opens in dark mode');
  console.log(JSON.stringify({checks,errors,blocked},null,2));
 } catch(e) {
  const labels=await page.locator('flt-semantics[aria-label]').evaluateAll(es=>es.map(e=>({role:e.getAttribute('role'),label:e.getAttribute('aria-label')})));
  console.error(JSON.stringify({checks,errors,blocked,labels,reason:e.message}));
  await page.screenshot({path:path.join(out,'ui-dark-failed.png')}); process.exitCode=1;
 } finally {await browser.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1});

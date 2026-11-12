// End-to-end role and privacy check against the local synthetic Firebase emulators.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright-core');
const fs=require('node:fs'),path=require('node:path');
const out=process.env.VARDAG_TEST_OUTPUT;
const fixture=JSON.parse(fs.readFileSync(path.join(out,'ui-fixture.json'),'utf8'));
(async()=>{
 const browser=await chromium.launch({executablePath:'/usr/bin/google-chrome',headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 const context=await browser.newContext({viewport:{width:390,height:844},colorScheme:'dark'});
 const page=await context.newPage();const errors=[],blocked=[],checks=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',route=>{const host=new URL(route.request().url()).hostname;if(['127.0.0.1','localhost','www.gstatic.com','fonts.gstatic.com'].includes(host))return route.continue();blocked.push(host);return route.abort();});
 try {
  await page.goto('http://localhost:8793/',{waitUntil:'domcontentloaded',timeout:60000});
  const sem=page.locator('flt-semantics-placeholder');await sem.waitFor({state:'attached',timeout:60000});await sem.evaluate(e=>e.click());
  await page.getByRole('textbox',{name:'E-post'}).fill(fixture.youthEmail);
  await page.getByRole('textbox',{name:'Lösenord'}).fill(fixture.password);
  await page.getByRole('button',{name:'Logga in',exact:true}).click();
  await page.getByRole('button',{name:/Kalender/}).waitFor({timeout:45000});
  await page.getByRole('button',{name:/Kalender/}).click();
  await page.waitForTimeout(12000);
  await page.screenshot({path:path.join(out,'ui-youth-calendar.png')});
  const html=await page.locator('flt-semantics-host').innerHTML();
  if(html.includes('Privat testträning'))throw Error('Owner private title exposed to youth');
  if(!html.includes('Privat'))throw Error('Neutral private marker is missing');
  checks.push('youth sees a neutral marker but not another account’s private title');
  await page.getByRole('button',{name:'Lägg till · skriv eller säg'}).click();
  await page.getByRole('button',{name:'Fyll i själv'}).click();
  await page.getByRole('textbox',{name:'Aktivitetsnamn'}).fill('Ungdomens privata test');
  await page.mouse.wheel(0,550);await page.waitForTimeout(1000);
  await page.screenshot({path:path.join(out,'ui-youth-add.png')});
  fs.writeFileSync(path.join(out,'ui-youth-add-semantics.html'),await page.locator('flt-semantics-host').innerHTML());
  await page.getByRole('checkbox',{name:'🔒 Privat'}).click();
  await page.getByRole('button',{name:'Spara aktivitet'}).click();
  await page.waitForTimeout(3000);
  const root='http://127.0.0.1:8280/v1/projects/demo-vardag-privacy/databases/(default)/documents';
  const res=await fetch(root+'/private_activities/'+fixture.youth+'/events',{headers:{Authorization:'Bearer owner'}});
  if(!res.ok)throw Error('Could not inspect the local test result');
  const docs=(await res.json()).documents||[];
  const detail=docs.find(d=>d.fields.title?.stringValue==='Ungdomens privata test');
  if(!detail)throw Error('Youth private activity was not saved');
  const id=detail.name.split('/').pop();
  const markerRes=await fetch(root+'/planner_events/'+id,{headers:{Authorization:'Bearer owner'}});
  const marker=await markerRes.json();
  if(!markerRes.ok || marker.fields.title.stringValue!=='Privat' || marker.fields.privateOwnerUid.stringValue!==fixture.youth)throw Error('Youth marker is not private');
  checks.push('youth creates a private activity with neutral family marker');

  if(errors.length || blocked.length)throw Error('Unexpected browser or external request');
  checks.push('youth can open the activity form');console.log(JSON.stringify({checks,errors,blocked},null,2));
 }catch(e){await page.screenshot({path:path.join(out,'ui-youth-failed.png')});console.error(JSON.stringify({checks,errors,blocked,reason:e.message}));process.exitCode=1;}
 finally {await browser.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1});

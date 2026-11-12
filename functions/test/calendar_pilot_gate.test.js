const test = require('node:test');
const assert = require('node:assert/strict');
const {pilotProblems, startTrialPatch, completionProblems, OBSERVATION_MS} = require('../calendar_pilot')._test;
const now = 1000000000;
const checks={androidDeviceTest:true,iphonePwaTest:true,reimportTest:true};
const report=platform=>({protocol:2,version:'1',platform,familyId:'f',seenAt:{toMillis:()=>now}});
const members=[{id:'u',data:{familyId:'f',calendarClients:{a:report('android'),p:report('pwa'),old:{protocol:1}}}},{id:'untested',data:{familyId:'f'}}];
const clients=[{uid:'u',installationId:'a'},{uid:'u',installationId:'p'}];
test('representative clients suffice: other members and old unselected devices do not block',()=>assert.deepEqual(pilotProblems({id:'f'},members,clients,checks,now),[]));
test('selected clients must be current, same family and protocol aware',()=>{
 for(const change of [{protocol:1},{familyId:'other'},{seenAt:{toMillis:()=>now-8*86400000}},{seenAt:{toMillis:()=>now+1}}]) {
  const changed=[{id:'u',data:{familyId:'f',calendarClients:{a:{...report('android'),...change},p:report('pwa')}}}];
  assert.ok(pilotProblems({id:'f'},changed,clients,checks,now).length);
 }
 assert.ok(pilotProblems({id:'f'},members,[...clients,{uid:'outsider',installationId:'x'}],checks,now).length);
});
test('empty, malformed, duplicate and single-platform samples fail',()=>{
 for(const selection of [[],null,[{}],[clients[0]],[...clients,clients[0]]]) assert.ok(pilotProblems({id:'f'},members,selection,checks,now).length);
 assert.ok(pilotProblems({id:'f'},members,clients,{},now).length);
});
test('trial starts now without inventing quiet48Hours evidence',()=>{
 const patch=startTrialPatch({id:'f'},members,clients,checks,'SERVER_TIME',now);
 assert.equal(patch.calendarPilot,true);assert.equal(patch.calendarPilotTrial.status,'observing');assert.equal(patch.calendarPilotTrial.startedAt,'SERVER_TIME');assert.equal(patch.pilotReadiness,undefined);
});
test('retry preserves start; restarting after disable gets a new start',()=>{
 const family={id:'f',calendarPilot:true,calendarPilotTrial:{status:'observing',startedAt:'OLD'}};
 assert.equal(startTrialPatch(family,members,clients,checks,'NEW',now),null);
 assert.equal(startTrialPatch({...family,calendarPilot:false},members,clients,checks,'NEW',now).calendarPilotTrial.startedAt,'NEW');
});
test('completion needs elapsed 48 hours, active trial and explicit observation',()=>{
 const family={calendarPilot:true,calendarPilotTrial:{status:'observing',startedAt:{toMillis:()=>now}}};
 assert.ok(completionProblems(family,true,now+OBSERVATION_MS-1).length);
 assert.deepEqual(completionProblems(family,true,now+OBSERVATION_MS),[]);
 assert.ok(completionProblems(family,false,now+OBSERVATION_MS).length);
 assert.ok(completionProblems({...family,calendarPilot:false},true,now+OBSERVATION_MS).length);
 assert.ok(completionProblems({calendarPilot:true,calendarPilotTrial:{status:'observing'}},true,now+OBSERVATION_MS).length);
});

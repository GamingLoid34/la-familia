// Private recurring moves against local Auth and Firestore emulators only.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {randomUUID, createHash} from 'node:crypto';

if (!process.env.PRIVACY_SDK_DIR) throw Error('Set PRIVACY_SDK_DIR to the local SDK.');
const require = createRequire(resolve(process.env.PRIVACY_SDK_DIR, 'package.json'));
const {initializeApp, deleteApp} = require('firebase/app');
const {getAuth, connectAuthEmulator, createUserWithEmailAndPassword, signInWithEmailAndPassword} = require('firebase/auth');
const {getFirestore, connectFirestoreEmulator, doc, setDoc, getDocFromServer, writeBatch,
  runTransaction, arrayUnion, arrayRemove, deleteField, terminate} = require('firebase/firestore');

const app = initializeApp({apiKey:'local-demo-key',appId:'local-test',projectId:'demo-vardag-privacy'},'private-move-'+randomUUID());
const auth = getAuth(app); connectAuthEmulator(auth,'http://127.0.0.1:9180',{disableWarnings:true});
const db = getFirestore(app); connectFirestoreEmulator(db,'127.0.0.1',8280);
const rand=randomUUID(), family='move-'+rand, password='LocalTestOnly123!';
const email = (role)=>`${role}-${rand}@example.invalid`;
const parent=(await createUserWithEmailAndPassword(auth,email('parent'),password)).user.uid;
await setDoc(doc(db,'families',family),{createdBy:parent});
await setDoc(doc(db,'users',parent),{name:'Alex',role:'admin',familyId:family});
const other=(await createUserWithEmailAndPassword(auth,email('other'),password)).user.uid;
await signInWithEmailAndPassword(auth,email('parent'),password);
await setDoc(doc(db,'users',other),{name:'Robin',role:'parent',familyId:family});
const uid=parent, sourceId='series'+rand.replaceAll('-',''), date='2026-11-09';
const targetId='moved_'+createHash('sha256').update(`${sourceId}|${date}`).digest('hex');
const source=doc(db,'planner_events',sourceId), target=doc(db,'planner_events',targetId);
const detail=(id)=>doc(db,'private_activities',uid,'events',id);
const initial={familyId:family,createdByUid:uid,createdBy:uid,visibility:'private',privateOwnerUid:uid,
  title:'Privat',piktogram:'🔒',type:'activity',date,time:'09:30',persons:['Alex'],personUids:[uid],
  source:'manual',isPending:false,isRecurring:true,recurrence:{type:'weekly',startDate:date,exceptions:[]}};
const secrets={ownerUid:uid,familyId:family,title:'En privat titel',piktogram:'🏥',
  checklist:[{item:'Enbart ägaren ser denna rad',isDone:true}]};
await (writeBatch(db).set(source,initial).set(detail(sourceId),secrets)).commit();
const checks=[];
const denied=(e)=>e.code==='permission-denied';
async function move(day='2026-11-10') {
 return runTransaction(db,async tx=>{
  const original=(await tx.get(source)).data();
  const privateData=(await tx.get(detail(sourceId))).data();
  const existing=original.detachedOccurrences?.[date];
  if(existing) {
   assert.equal(existing,targetId);
   const current=(await tx.get(target)).data();
   if(current.date!==day) throw Error('Already moved to another day');
   return current;
  }
  const marker={...initial,date:day,time:'11:00',isRecurring:false,originalSeriesId:sourceId,originalOccurrenceDate:date};
  delete marker.recurrence;
  tx.update(source,{'recurrence.exceptions':arrayUnion(date),[`detachedOccurrences.${date}`]:targetId});
  tx.set(target,marker); tx.set(detail(targetId),privateData);
  return marker;
 });
}
await move(); await move();
await assert.rejects(move('2026-11-11'),/Already moved/);
const raw=(await getDocFromServer(target)).data();
assert.equal(raw.title,'Privat'); assert.equal(raw.originalSeriesId,sourceId);
assert.equal(raw.checklist,undefined);
assert.equal((await getDocFromServer(detail(targetId))).data().title,'En privat titel');
checks.push('move is atomic, idempotent and keeps private content out of the family marker'); console.log('move passed');
await assert.rejects((writeBatch(db).delete(source).delete(detail(sourceId))).commit(),denied);
await assert.rejects((writeBatch(db).delete(target).delete(detail(targetId))).commit(),denied);
checks.push('old clients cannot orphan a source series or detached occurrence');
await signInWithEmailAndPassword(auth,email('other'),password);
assert.equal((await getDocFromServer(target)).data().title,'Privat');
await assert.rejects(getDocFromServer(detail(targetId)),denied);
await assert.rejects((writeBatch(db).delete(target).delete(detail(targetId))).commit(),denied);
checks.push('other family member sees neutral marker and cannot read or delete private detail'); console.log('access control passed');
await signInWithEmailAndPassword(auth,email('parent'),password);
await runTransaction(db,async tx=>{
 const s=(await tx.get(source)).data(); assert.equal(s.detachedOccurrences[date],targetId);
 tx.update(source,{'recurrence.exceptions':arrayRemove(date),[`detachedOccurrences.${date}`]:deleteField()});
 tx.delete(target); tx.delete(detail(targetId));
});
assert.equal((await getDocFromServer(source)).data().recurrence.exceptions.includes(date),false);
checks.push('undo removes both private target documents and restores the original occurrence'); console.log('undo passed');
await move();
await runTransaction(db,async tx=>{
 const s=(await tx.get(source)).data(); assert.equal(s.detachedOccurrences[date],targetId);
 tx.delete(source); tx.delete(detail(sourceId)); tx.delete(target); tx.delete(detail(targetId));
});
checks.push('series and linked private occurrence can be removed together');

async function bulkSeries(count) {
 const id='bulk'+randomUUID().replaceAll('-','');
 const series=doc(db,'planner_events',id);
 const batch=writeBatch(db); batch.set(series,initial); batch.set(detail(id),secrets); await batch.commit();
 const links=[];
 for(let i=0;i<count;i++) {
  const original=new Date(Date.UTC(2026,10,9+i*7)).toISOString().slice(0,10);
  const moved='moved_'+createHash('sha256').update(`${id}|${original}`).digest('hex');
  const marker={...initial,date:'2027-03-01',time:'11:00',isRecurring:false,originalSeriesId:id,originalOccurrenceDate:original};
  delete marker.recurrence;
  const b=writeBatch(db);
  b.update(series,{'recurrence.exceptions':arrayUnion(original),[`detachedOccurrences.${original}`]:moved});
  b.set(doc(db,'planner_events',moved),marker); b.set(detail(moved),secrets); await b.commit();
  links.push({original,moved});
 }
 return {id,series,links};
}
const eight=await bulkSeries(8);
const b=writeBatch(db); b.delete(eight.series); b.delete(detail(eight.id));
for(const row of eight.links) {b.delete(doc(db,'planner_events',row.moved)); b.delete(detail(row.moved));}
await b.commit();
checks.push('eight linked occurrences and their series delete atomically within the rules access limit');
const nine=await bulkSeries(9);
await assert.rejects(setDoc(nine.series,{...initial,detachedOccurrences:{'2026-11-09':'hemlig text'}}),denied);
const first=nine.links.slice(0,7);
const trim=writeBatch(db);
trim.update(nine.series,Object.fromEntries(first.map(row=>[`detachedOccurrences.${row.original}`,deleteField()])));
for(const row of first) {trim.delete(doc(db,'planner_events',row.moved)); trim.delete(detail(row.moved));}
await trim.commit();
assert.equal(Object.keys((await getDocFromServer(nine.series)).data().detachedOccurrences).length,2);
const rest=writeBatch(db); rest.delete(nine.series); rest.delete(detail(nine.id));
for(const row of nine.links.slice(7)) {rest.delete(doc(db,'planner_events',row.moved)); rest.delete(detail(row.moved));}
await rest.commit();
checks.push('larger series can be safely unlinked in bounded groups without leaking free text');
await terminate(db); await deleteApp(app);
console.log(JSON.stringify({count:checks.length,passed:checks},null,2));

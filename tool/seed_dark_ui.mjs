// Synthetic, local-only browser fixture. Never uses a production project.
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {randomUUID} from 'node:crypto';
import {writeFileSync} from 'node:fs';
if (!process.env.PRIVACY_SDK_DIR || !process.env.VARDAG_TEST_OUTPUT) throw Error('Local SDK and output paths required.');
const require=createRequire(resolve(process.env.PRIVACY_SDK_DIR,'package.json'));
const {initializeApp,deleteApp}=require('firebase/app');
const {getAuth,connectAuthEmulator,createUserWithEmailAndPassword,signInWithEmailAndPassword}=require('firebase/auth');
const {getFirestore,connectFirestoreEmulator,doc,setDoc,writeBatch,terminate}=require('firebase/firestore');
const random=randomUUID(), password='LocalUiOnly123!', parentEmail=`ui-parent-${random}@example.invalid`, youthEmail=`ui-youth-${random}@example.invalid`;
const app=initializeApp({apiKey:'demo-key',appId:'1:123:web:vardag-test',projectId:'demo-vardag-privacy'},'ui-'+random);
const auth=getAuth(app); connectAuthEmulator(auth,'http://127.0.0.1:9180',{disableWarnings:true});
const db=getFirestore(app); connectFirestoreEmulator(db,'127.0.0.1',8280);
const parent=(await createUserWithEmailAndPassword(auth,parentEmail,password)).user.uid;
const family='ui-'+random;
await setDoc(doc(db,'families',family),{createdBy:parent,name:'Testfamilj'});
await setDoc(doc(db,'users',parent),{name:'Alex',role:'admin',familyId:family,viewMode:'parent',email:parentEmail});
const youth=(await createUserWithEmailAndPassword(auth,youthEmail,password)).user.uid;
await signInWithEmailAndPassword(auth,parentEmail,password);
await setDoc(doc(db,'users',youth),{name:'Robin',role:'youth',familyId:family,viewMode:'youth',email:youthEmail});
const root='http://127.0.0.1:8280/v1/projects/demo-vardag-privacy/databases/(default)/documents';
const result=await fetch(`${root}/families/${family}?updateMask.fieldPaths=calendarPilot`,{method:'PATCH',
  headers:{Authorization:'Bearer owner','Content-Type':'application/json'},body:JSON.stringify({fields:{calendarPilot:{booleanValue:true}}})});
if(!result.ok) throw Error(`Fixture flag failed ${result.status}`);
const date=new Date();
const key=`${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
const next=new Date(date.getFullYear(),date.getMonth(),date.getDate()+1);
const nextKey=`${next.getFullYear()}-${String(next.getMonth()+1).padStart(2,'0')}-${String(next.getDate()).padStart(2,'0')}`;
const seriesId='uitest'+random.replaceAll('-','');
const marker={familyId:family,createdByUid:parent,createdBy:parent,visibility:'private',privateOwnerUid:parent,
 title:'Privat',piktogram:'🔒',type:'activity',date:key,time:'09:30',persons:['Alex'],personUids:[parent],
 source:'manual',isPending:false,isRecurring:true,recurrence:{type:'weekly',startDate:key,exceptions:[]}};
const detail={familyId:family,ownerUid:parent,title:'Privat testträning',piktogram:'🏥',checklist:[{item:'Testpacklista',isDone:true}]};
const batch=writeBatch(db); batch.set(doc(db,'planner_events',seriesId),marker);
batch.set(doc(db,'private_activities',parent,'events',seriesId),detail);
for(const [i,title] of ['Lektion Historia','Lektion Svenska'].entries()) {
 batch.set(doc(db,'planner_events',`ui-school-${i}-${random}`),{familyId:family,createdByUid:parent,createdBy:parent,
   date:key,time:i?'10:30':'08:30',endTime:i?'11:15':'09:15',title,persons:['Alex'],personUids:[parent],
   source:'calendar',planningImportKind:'schedule',isRecurring:false});
}
await batch.commit();
writeFileSync(resolve(process.env.VARDAG_TEST_OUTPUT,'ui-fixture.json'),JSON.stringify({family,parent,youth,parentEmail,youthEmail,password,date:key,nextDate:nextKey,seriesId},null,2),{mode:0o600});
await terminate(db); await deleteApp(app);
console.log('Synthetic calendar fixture created in localhost emulators only.');

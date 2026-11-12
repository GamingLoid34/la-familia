// Actual Firebase JS SDK against local emulators, using synthetic accounts only.
// PRIVACY_SDK_DIR must point to an isolated npm prefix containing firebase@12.9.0.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {randomUUID} from 'node:crypto';

if (!process.env.PRIVACY_SDK_DIR) throw Error('Set PRIVACY_SDK_DIR to the local test SDK directory.');
const require = createRequire(resolve(process.env.PRIVACY_SDK_DIR, 'package.json'));
const {initializeApp, deleteApp} = require('firebase/app');
const {getAuth, connectAuthEmulator, createUserWithEmailAndPassword, signInWithEmailAndPassword} = require('firebase/auth');
const {getFirestore, connectFirestoreEmulator, doc, setDoc, getDocFromServer, getDocFromCache,
  writeBatch, disableNetwork, enableNetwork, terminate} = require('firebase/firestore');

const app = initializeApp({apiKey: 'local-demo-key', appId: 'local-test', projectId: 'demo-vardag-privacy'}, 'privacy-' + randomUUID());
const auth = getAuth(app);
connectAuthEmulator(auth, 'http://127.0.0.1:9180', {disableWarnings: true});
const db = getFirestore(app);
connectFirestoreEmulator(db, '127.0.0.1', 8280);
const random = randomUUID();
const family = 'local-' + random;
const parentEmail = `parent-${random}@example.invalid`;
const otherEmail = `other-${random}@example.invalid`;
const childEmail = `child-${random}@example.invalid`;
const youthEmail = `youth-${random}@example.invalid`;
const password = 'LocalTestOnly123!';
const checks = [];
const parent = (await createUserWithEmailAndPassword(auth, parentEmail, password)).user.uid;
await setDoc(doc(db, 'families', family), {createdBy: parent});
await setDoc(doc(db, 'users', parent), {name: 'Alex', role: 'admin', familyId: family});

async function addMember(email, name, role) {
  const uid = (await createUserWithEmailAndPassword(auth, email, password)).user.uid;
  await signInWithEmailAndPassword(auth, parentEmail, password);
  await setDoc(doc(db, 'users', uid), {name, role, familyId: family});
  return uid;
}
const other = await addMember(otherEmail, 'Robin', 'parent');
const child = await addMember(childEmail, 'Child', 'child');
const youth = await addMember(youthEmail, 'Youth', 'youth');
const gate = doc(db, 'config', 'privateCalendarPilot20261030');
assert.deepEqual((await getDocFromServer(gate)).data(), {enabled: true, contract: 'private-v1-20261030'});
await assert.rejects(setDoc(gate, {enabled: true, contract: 'private-v1-20261030'}),
  (e) => e.code === 'permission-denied');
checks.push('server activation is readable but cannot be changed by a family admin');

function pair(uid, name, title) {
  const id = randomUUID();
  const marker = {familyId: family, createdByUid: uid, createdBy: uid, visibility: 'private',
    privateOwnerUid: uid, title: 'Privat', piktogram: '🔒', type: 'activity',
    date: '2026-11-09', time: '09:30', persons: [name], personUids: [uid], source: 'manual', isPending: false};
  return {markerRef: doc(db, 'planner_events', id), detailRef: doc(db, 'private_activities', uid, 'events', id),
    marker, detail: {ownerUid: uid, familyId: family, title, checklist: [{item: 'Privat rad'}]}};
}
async function save(p) {
  const batch = writeBatch(db);
  batch.set(p.markerRef, p.marker);
  batch.set(p.detailRef, p.detail);
  await batch.commit();
}

const event = pair(parent, 'Alex', 'Endast Alex ser detta');
await save(event);
assert.equal((await getDocFromServer(event.detailRef)).data().title, event.detail.title);
assert.equal((await getDocFromServer(event.markerRef)).data().title, 'Privat');
checks.push('owner sees private content; public document has only a generic title');
await signInWithEmailAndPassword(auth, otherEmail, password);
assert.equal((await getDocFromServer(event.markerRef)).data().title, 'Privat');
await assert.rejects(getDocFromServer(event.detailRef), (e) => e.code === 'permission-denied');
checks.push('another parent can read the marker but not the private detail');
await signInWithEmailAndPassword(auth, childEmail, password);
await assert.rejects(save(pair(child, 'Child', 'barnets privata titel')), (e) => e.code === 'permission-denied');
checks.push('child cannot create private activity');
await signInWithEmailAndPassword(auth, youthEmail, password);
await save(pair(youth, 'Youth', 'ungdomens privata titel'));
checks.push('youth can create private activity');
await signInWithEmailAndPassword(auth, parentEmail, password);
const offline = pair(parent, 'Alex', 'Privat i offlinekö');
await disableNetwork(db);
const pending = save(offline);
for (let n = 0; n < 100; n++) {
  const local = await getDocFromCache(offline.markerRef).catch(() => null);
  if (local?.exists()) break;
  await new Promise((resolve) => setTimeout(resolve, 20));
}
assert.equal((await getDocFromCache(offline.markerRef)).data().title, 'Privat');
assert.equal((await getDocFromCache(offline.detailRef)).data().title, 'Privat i offlinekö');
await enableNetwork(db);
await pending;
assert.equal((await getDocFromServer(offline.detailRef)).data().title, 'Privat i offlinekö');
checks.push('offline batch is locally separated and both documents are confirmed after reconnect');
const batch = writeBatch(db);
batch.delete(event.markerRef);
batch.delete(event.detailRef);
await batch.commit();
checks.push('owner deletes marker and detail in one batch');
await terminate(db);
await deleteApp(app);
console.log(JSON.stringify({passed: checks, count: checks.length}, null, 2));

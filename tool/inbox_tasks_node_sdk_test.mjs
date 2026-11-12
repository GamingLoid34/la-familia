// Synthetic accounts only; hardcoded to the local demo emulators.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {randomUUID, createHash} from 'node:crypto';

if (!process.env.PRIVACY_SDK_DIR) throw Error('Set PRIVACY_SDK_DIR to the local SDK.');
const require = createRequire(resolve(process.env.PRIVACY_SDK_DIR, 'package.json'));
const {initializeApp, deleteApp} = require('firebase/app');
const {getAuth, connectAuthEmulator, createUserWithEmailAndPassword, signInWithEmailAndPassword} = require('firebase/auth');
const {getFirestore, connectFirestoreEmulator, collection, doc, setDoc, updateDoc,
  getDocFromServer, getDocsFromServer, query, where, serverTimestamp, deleteField, terminate} = require('firebase/firestore');

const app = initializeApp({apiKey: 'local-demo-key', appId: 'local-test', projectId: 'demo-vardag-privacy'}, 'inbox-' + randomUUID());
const auth = getAuth(app);
connectAuthEmulator(auth, 'http://127.0.0.1:9180', {disableWarnings: true});
const db = getFirestore(app);
connectFirestoreEmulator(db, '127.0.0.1', 8280);
const random = randomUUID(), family = 'inbox-' + random, password = 'LocalTestOnly123!';
const email = (name) => `${name}-${random}@example.invalid`;
const parent = (await createUserWithEmailAndPassword(auth, email('parent'), password)).user.uid;
await setDoc(doc(db, 'families', family), {createdBy: parent});
await setDoc(doc(db, 'users', parent), {name: 'Alex', role: 'admin', familyId: family});
async function addMember(name, role) {
  const uid = (await createUserWithEmailAndPassword(auth, email(name), password)).user.uid;
  await signInWithEmailAndPassword(auth, email('parent'), password);
  await setDoc(doc(db, 'users', uid), {name, role, familyId: family});
  return uid;
}
const other = await addMember('other', 'parent');
await addMember('child', 'child');
await addMember('youth', 'youth');
const denied = (e) => e.code === 'permission-denied';
const checks = [];

const text = 'Veckobrev\nTa med gympapåsen';
const hash = createHash('sha256').update(text.toLowerCase()).digest('hex');
function note(visibility) {
  return {familyId: family, ownerUid: parent, createdByUid: parent, visibility,
    text, contentHash: hash, aboutUids: [other], status: 'saved', requestId: randomUUID(),
    linkedIds: [], createdAt: serverTimestamp()};
}
const sharedRef = doc(collection(db, 'notes'));
const privateRef = doc(collection(db, 'notes'));
await setDoc(sharedRef, note('family'));
await setDoc(privateRef, note('private'));
assert.equal((await getDocFromServer(privateRef)).data().text, text);
checks.push('parent creates multiline shared and private notes with the client schema');
const taskRef = doc(collection(db, 'tasks'));
await setDoc(taskRef, {familyId: family, createdByUid: parent, title: 'Gympapåse',
  dueDate: '2026-11-09', dueTime: '08:00', hasTime: true, showFromDate: null,
  assigneeUid: other, aboutUids: [other], status: 'open', sourceNoteId: sharedRef.id, doneAt: null});
await updateDoc(taskRef, {status: 'done', doneAt: serverTimestamp()});
await updateDoc(taskRef, {title: 'Gympapåse och handduk', dueDate: '2026-11-09',
  dueTime: '08:30', hasTime: true, showFromDate: null, assigneeUid: other, aboutUids: [other]});
const edited = (await getDocFromServer(taskRef)).data();
assert.equal(edited.status, 'done');
assert.equal(edited.sourceNoteId, sharedRef.id);
assert.ok(edited.doneAt);
checks.push('task edits preserve its weekly-letter source and completion');
const mealRef = doc(db, 'meal_choices', `${other}_2026-11-09`);
await setDoc(mealRef, {familyId: family, personUid: other, date: '2026-11-09',
  lunch: {dishId: '1', rakostId: deleteField(), dessertId: deleteField()}, updatedAt: serverTimestamp()}, {merge: true});
await setDoc(mealRef, {familyId: family, personUid: other, date: '2026-11-09',
  middag: {dishId: '2', rakostId: deleteField(), dessertId: deleteField()}, updatedAt: serverTimestamp()}, {merge: true});
const meals = await getDocsFromServer(query(collection(db, 'meal_choices'), where('familyId', '==', family),
  where('personUid', '==', other), where('date', '==', '2026-11-09')));
assert.equal(meals.docs.length, 1);
assert.equal(meals.docs[0].data().lunch.dishId, '1');
assert.equal(meals.docs[0].data().middag.dishId, '2');
checks.push('hospital meal choices use the existing shared document without overwriting another meal');

await signInWithEmailAndPassword(auth, email('other'), password);
assert.equal((await getDocFromServer(sharedRef)).data().text, text);
await assert.rejects(getDocFromServer(privateRef), denied);
const sharedQuery = query(collection(db, 'notes'), where('familyId', '==', family), where('visibility', '==', 'family'));
const myQuery = query(collection(db, 'notes'), where('familyId', '==', family), where('ownerUid', '==', other));
assert.ok((await getDocsFromServer(sharedQuery)).docs.some((d) => d.id === sharedRef.id));
assert.ok(!(await getDocsFromServer(myQuery)).docs.some((d) => d.id === privateRef.id));
await assert.rejects(updateDoc(sharedRef, {text: 'Falsk ändring'}), denied);
checks.push('second parent sees shared notes, never private notes, and cannot alter original text');
for (const role of ['child', 'youth']) {
  await signInWithEmailAndPassword(auth, email(role), password);
  await assert.rejects(getDocFromServer(sharedRef), denied);
  await assert.rejects(getDocFromServer(taskRef), denied);
  checks.push(`${role} cannot read adult notes or tasks`);
}
await terminate(db);
await deleteApp(app);
console.log(JSON.stringify({count: checks.length, passed: checks}, null, 2));

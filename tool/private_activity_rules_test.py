"""Local-only security regression tests. Requires the Auth and Firestore emulators.

No credentials or data from the real Firebase project are used.
"""
import json
import urllib.error
import urllib.request
import uuid

AUTH = 'http://127.0.0.1:9180/identitytoolkit.googleapis.com/v1/accounts:'
ROOT = 'http://127.0.0.1:8280/v1/projects/demo-vardag-privacy/databases/(default)/documents'
NAME = 'projects/demo-vardag-privacy/databases/(default)/documents/'


def request(url, data=None, token=None, method=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(url, None if data is None else json.dumps(data).encode(), headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())


def encode(value):
    if value is None:
        return {'nullValue': None}
    if isinstance(value, bool):
        return {'booleanValue': value}
    if isinstance(value, int):
        return {'integerValue': str(value)}
    if isinstance(value, str):
        return {'stringValue': value}
    if isinstance(value, list):
        return {'arrayValue': {'values': [encode(item) for item in value]}}
    if isinstance(value, dict):
        return {'mapValue': {'fields': {key: encode(item) for key, item in value.items()}}}
    raise TypeError(type(value))


def fields(data):
    return {key: encode(value) for key, value in data.items()}


def expect(expected, result, label):
    status, body = result
    assert status in expected, f'{label}: expected {expected}, got {status}: {body}'
    checks.append(label)
    return body


def get(path, token):
    return request(ROOT + '/' + path, token=token)


def update(path, data, token):
    return request(ROOT + '/' + path, {'fields': fields(data)}, token, 'PATCH')


def commit(writes, token):
    encoded = []
    for path, data in writes:
        encoded.append({'delete': NAME + path} if data is None else
                       {'update': {'name': NAME + path, 'fields': fields(data)}})
    return request(ROOT + ':commit', {'writes': encoded}, token, 'POST')


def account(label, family, role):
    email = label + '-' + uuid.uuid4().hex[:8] + '@example.invalid'
    status, result = request(AUTH + 'signUp?key=demo', {
        'email': email, 'password': 'LocalOnlyTest123!', 'returnSecureToken': True}, method='POST')
    assert status == 200, result
    user = {'uid': result['localId'], 'token': result['idToken'], 'name': label}
    assert update('users/' + user['uid'], {'familyId': family, 'role': role, 'name': label}, 'owner')[0] == 200
    return user


def docs(user, event_id):
    uid = user['uid']
    marker = {'familyId': 'test-family', 'createdByUid': uid, 'createdBy': uid,
              'visibility': 'private', 'privateOwnerUid': uid, 'title': 'Privat',
              'piktogram': '🔒', 'type': 'activity', 'date': '2026-11-09', 'time': '09:30',
              'persons': [user['name']], 'personUids': [uid], 'source': 'manual', 'isPending': False}
    detail = {'familyId': 'test-family', 'ownerUid': uid, 'title': 'Enbart ägarens hemliga titel',
              'checklist': [{'item': 'Privat innehåll', 'isDone': False}]}
    return ('planner_events/' + event_id, marker), ('private_activities/' + uid + '/events/' + event_id, detail)


checks = []
parent = account('parent', 'test-family', 'parent')
admin = account('admin', 'test-family', 'admin')
youth = account('youth', 'test-family', 'youth')
child = account('child', 'test-family', 'child')
outside = account('outside', 'other-family', 'parent')
capability_path = 'config/privateCalendarPilot20261030'
capability = {'enabled': True, 'contract': 'private-v1-20261030'}
expect([403], update(capability_path, capability, admin['token']), 'even a family admin cannot enable the server gate')
expect([200], update(capability_path, capability, 'owner'), 'emulator server can enable the gate')
expect([200], get(capability_path, parent['token']), 'authenticated account can read the server gate')

event_id = uuid.uuid4().hex
marker, detail = docs(parent, event_id)
expect([403], commit([marker], parent['token']), 'marker without private detail rejected')
expect([403], commit([detail], parent['token']), 'private detail without marker rejected')
expect([200], commit([marker, detail], parent['token']), 'parent creates atomic private activity')
recurring, recurring_detail = docs(parent, uuid.uuid4().hex)
recurring[1].update({'isRecurring': True, 'recurrence': {'type': 'weekly', 'startDate': '2026-11-09',
                                                        'endDate': None, 'exceptions': ['2026-11-16']}})
expect([200], commit([recurring, recurring_detail], parent['token']), 'weekly private activity with exception is allowed')
for actor in (parent, admin, youth, child):
    body = expect([200], get(marker[0], actor['token']), actor['name'] + ' can see marker')
    assert body['fields']['title']['stringValue'] == 'Privat'
    assert 'hemlig' not in json.dumps(body, ensure_ascii=False)
expect([403], get(marker[0], outside['token']), 'other family cannot see marker')
expect([200], get(detail[0], parent['token']), 'owner can read private detail')
for actor in (admin, youth, child, outside):
    expect([403], get(detail[0], actor['token']), actor['name'] + ' cannot read private detail')
expect([403], get(detail[0], None), 'unauthenticated private detail rejected')
expect([403], get('private_activities/' + parent['uid'] + '/events', admin['token']), 'another parent cannot list details')
expect([200], get('private_activities/' + parent['uid'] + '/events', parent['token']), 'owner can list own details')

for actor in (youth, child):
    pair = docs(actor, uuid.uuid4().hex)
    expect([200] if actor is youth else [403], commit(pair, actor['token']), actor['name'] + ' role check')

for key, value in [('title', 'Hemlig titel'), ('piktogram', '🏥'), ('location', 'Hemligt'),
                   ('personUids', [admin['uid']]), ('persons', ['Annans namn']),
                   ('writeId', 'secret'), ('recurrence', {'type': 'weekly', 'startDate': '2026-11-09',
                                                        'exceptions': ['hemlighet']})]:
    event_id = uuid.uuid4().hex
    attempted, private = docs(parent, event_id)
    attempted[1][key] = value
    if key == 'recurrence': attempted[1]['isRecurring'] = True
    expect([403], commit([attempted, private], parent['token']), 'reject unsafe marker ' + key)
    expect([404], get(attempted[0], 'owner'), 'atomic denial leaves no marker ' + key)
    expect([404], get(private[0], 'owner'), 'atomic denial leaves no private detail ' + key)

public = {'familyId': 'test-family', 'createdByUid': parent['uid'], 'title': 'Gemensam'}
public_path = 'planner_events/' + uuid.uuid4().hex
expect([200], update(public_path, public, parent['token']), 'normal family event can be created')
expect([200], get(public_path, child['token']), 'normal family event readable')
expect([200], update(public_path, {**public, 'title': 'Ändrad'}, admin['token']), 'normal parent edit still works')
expect([403], update(public_path, {**public, 'visibility': 'private'}, parent['token']), 'existing shared event cannot silently become private')
expect([403], update(marker[0], {**marker[1], 'title': 'Hemlig titel'}, parent['token']), 'old client cannot write title into marker')
expect([403], update(marker[0], {**marker[1], 'time': '10:00'}, admin['token']), 'other parent cannot change marker')
expect([403], update(detail[0], {**detail[1], 'title': 'Ändrad'}, admin['token']), 'other parent cannot edit detail')
expect([403], commit([(marker[0], None)], parent['token']), 'marker cannot be deleted alone')
expect([403], commit([(detail[0], None)], parent['token']), 'detail cannot be deleted alone')
expect([200], commit([(marker[0], {**marker[1], 'time': '10:00'}),
                      (detail[0], {**detail[1], 'title': 'Ändrad privat titel'})], parent['token']), 'owner edits private pair')
expect([200], commit([(marker[0], None), (detail[0], None)], parent['token']), 'owner deletes both atomically')

print(json.dumps({'passed': checks, 'count': len(checks)}, ensure_ascii=False, indent=2))

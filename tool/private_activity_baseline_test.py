"""Fail-closed check against the earlier rules in a second local emulator only."""
import json
import urllib.error
import urllib.request
import uuid

root = 'http://127.0.0.1:8281/v1/projects/demo-vardag-privacy/databases/(default)/documents'
name = 'projects/demo-vardag-privacy/databases/(default)/documents/'

def call(url, body=None, token=None, method=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(url, None if body is None else json.dumps(body).encode(), headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())

status, user = call('http://127.0.0.1:9180/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo',
                    {'email': uuid.uuid4().hex + '@example.invalid', 'password': 'LocalOnlyTest123!',
                     'returnSecureToken': True}, method='POST')
assert status == 200
uid, token = user['localId'], user['idToken']
def encode(value):
    if isinstance(value, bool): return {'booleanValue': value}
    if isinstance(value, list): return {'arrayValue': {'values': [encode(x) for x in value]}}
    return {'stringValue': value}
def fields(data): return {k: encode(v) for k, v in data.items()}
status, _ = call(root + '/users/' + uid, {'fields': fields({'name': 'local', 'role': 'parent', 'familyId': 'local'})}, 'owner', 'PATCH')
assert status == 200
event = uuid.uuid4().hex
marker_path = 'planner_events/' + event
detail_path = 'private_activities/' + uid + '/events/' + event
marker = {'familyId': 'local', 'createdByUid': uid, 'createdBy': uid, 'visibility': 'private',
          'privateOwnerUid': uid, 'title': 'Privat', 'piktogram': '🔒', 'type': 'activity',
          'date': '2026-11-09', 'time': '09:30', 'persons': ['local'], 'personUids': [uid],
          'source': 'manual', 'isPending': False}
detail = {'familyId': 'local', 'ownerUid': uid, 'title': 'Enbart lokal hemlig titel'}
assert call(root + '/private_activities/' + uid + '/events', token=token)[0] == 403
writes = [{'update': {'name': name + path, 'fields': fields(data)}} for path, data in [(marker_path, marker), (detail_path, detail)]]
assert call(root + ':commit', {'writes': writes}, token, 'POST')[0] == 403
assert call(root + '/' + marker_path, token='owner')[0] == 404
assert call(root + '/' + detail_path, token='owner')[0] == 404
print(json.dumps({'passed': ['old rules reject the private support probe',
                              'old rules reject the entire atomic batch',
                              'no marker or private detail is written']}, ensure_ascii=False))

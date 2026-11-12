'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {GoogleCalendarProvider, OutlookCalendarProvider, ICloudCalendarProvider, createdEventIdentity} = require('../calendar_sync/providers');
const sha = (value) => createHash('sha256').update(value).digest('hex');
function mock(responses) {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({url: String(url), ...options});
    assert.ok(responses.length, 'unexpected provider request');
    const next = responses.shift();
    if (next instanceof Error) throw next;
    return new Response(typeof next.body === 'object' ? JSON.stringify(next.body) : next.body ?? null, {
      status: next.status || 200, headers: next.headers || {},
    });
  };
  return {fetchImpl, calls};
}
const g = (m) => new GoogleCalendarProvider({accessToken: 'test-placeholder', fetchImpl: m.fetchImpl});
const o = (m) => new OutlookCalendarProvider({accessToken: 'test-placeholder', fetchImpl: m.fetchImpl});
const i = (m) => new ICloudCalendarProvider({username: 'test@example.org', appPassword: 'test-placeholder', fetchImpl: m.fetchImpl});
const checkCode = (code) => (error) => { assert.equal(error.code, code); return true; };
const calendar = 'https://p12-caldav.icloud.com/123/calendars/work/';
const ics = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:test-event\r\nDTSTART;TZID=Europe/Stockholm:20261019T073000\r\nDTEND;TZID=Europe/Stockholm:20261019T083000\r\nRRULE:FREQ=WEEKLY;COUNT=3\r\nEXDATE;TZID=Europe/Stockholm:20261026T073000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';
const multistatus = (body, token = '') => `<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">${body}${token ? `<d:sync-token>${token}</d:sync-token>` : ''}</d:multistatus>`;
const propResponse = (href, props) => `<d:response><d:href>${href}</d:href><d:propstat><d:prop>${props}</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>`;

test('Google lists all pages preserving recurring masters, moved exceptions and tombstones', async () => {
  const master = {id: 'master', etag: '"one"', recurrence: ['RRULE:FREQ=WEEKLY', 'EXDATE:20261026T053000Z']};
  const moved = {id: 'moved', recurringEventId: 'master', originalStartTime: {dateTime: '2026-10-19T07:30:00+02:00'}, start: {dateTime: '2026-10-20T07:30:00+02:00'}};
  const m = mock([{body: {items: [master], nextPageToken: 'page2'}}, {body: {items: [moved, {id: 'deleted', status: 'cancelled'}], nextSyncToken: 'next'}}]);
  const result = await g(m).listEvents('my/calendar');
  assert.equal(result.full, true);
  assert.equal(result.syncToken, 'next');
  assert.deepEqual(result.items[0].raw, master);
  assert.deepEqual(result.items[1].raw, moved);
  assert.equal(result.items[2].deleted, true);
  assert.match(m.calls[0].url, /my%2Fcalendar/);
  assert.equal(new URL(m.calls[0].url).searchParams.get('singleEvents'), 'false');
  assert.equal(new URL(m.calls[1].url).searchParams.get('pageToken'), 'page2');
});
test('Google incremental request never adds forbidden window filters', async () => {
  const m = mock([{body: {items: [], nextSyncToken: 'new'}}]);
  const result = await g(m).listEvents('primary', {syncToken: 'old', windowStart: '2026-01-01'});
  const query = new URL(m.calls[0].url).searchParams;
  assert.equal(query.get('syncToken'), 'old');
  assert.equal(query.get('timeMin'), null);
  assert.equal(query.get('showDeleted'), 'true');
  assert.equal(result.full, false);
});
test('Google expired cursor demands full resync and never yields a false empty result', async () => {
  const m = mock([{status: 410, body: {error: 'expired'}}]);
  await assert.rejects(g(m).listEvents('primary', {syncToken: 'old'}), checkCode('sync-reset-required'));
});
test('Google deterministic create recognizes retry without overwriting remote edits', async () => {
  const key = sha('operation1');
  const existing = {id: `v${key}`, summary: 'Changed remotely', extendedProperties: {private: {vardagOperationId: key}}};
  const m = mock([{status: 409, body: {}}, {body: existing}]);
  const result = await g(m).createEvent('primary', {operationId: 'operation1', event: {summary: 'Original', recurrence: ['RRULE:FREQ=WEEKLY']}});
  const request = JSON.parse(m.calls[0].body);
  assert.equal(request.id, existing.id);
  assert.deepEqual(request.recurrence, ['RRULE:FREQ=WEEKLY']);
  assert.equal(result.alreadyExists, true);
  assert.equal(result.raw.summary, 'Changed remotely');
  assert.deepEqual(m.calls.map((r) => r.method), ['POST', 'GET']);
});
test('Google retry cannot claim an unrelated existing id', async () => {
  const m = mock([{status: 409, body: {}}, {body: {id: `v${sha('operation1')}`}}]);
  await assert.rejects(g(m).createEvent('primary', {operationId: 'operation1', event: {summary: 'Original'}}), checkCode('conflict'));
});
test('Google PATCH preserves unmentioned fields and requires current ETag', async () => {
  const m = mock([{body: {id: 'a', etag: '"next"'}}]);
  await assert.rejects(g(m).updateEvent('primary', 'a', {summary: 'New'}), checkCode('invalid-etag'));
  await g(m).updateEvent('primary', 'a', {summary: 'New'}, {etag: '"old"'});
  assert.equal(m.calls[0].headers['If-Match'], '"old"');
  assert.deepEqual(JSON.parse(m.calls[0].body), {summary: 'New'});
  assert.equal(m.calls[0].method, 'PATCH');
});
test('ETag conflict is exposed and never retried as unconditional write', async () => {
  const m = mock([{status: 412, body: {privateProviderMessage: 'never expose me'}}]);
  await assert.rejects(o(m).updateEvent('cal', 'a', {subject: 'New'}, {etag: 'W/"old"'}), (error) => {
    assert.equal(error.code, 'conflict'); assert.doesNotMatch(error.message, /never expose/); return true;
  });
  assert.equal(m.calls.length, 1);
});
test('Outlook reads full selected calendar without expanding/loss of recurrence', async () => {
  const master = {id: 'master', type: 'seriesMaster', recurrence: {pattern: {type: 'weekly', interval: 1, daysOfWeek: ['monday']}, range: {type: 'noEnd', startDate: '2026-10-19'}}};
  const m = mock([{body: {value: [master], '@odata.nextLink': 'https://graph.microsoft.com/v1.0/me/calendars/cal/events?$skip=20'}}, {body: {value: [{id: 'single'}]}}, {body: {...master, exceptionOccurrences: [{id: 'moved', occurrenceId: 'OID.master.2026-10-26', start: {dateTime: '2026-10-27T09:00:00'}}], cancelledOccurrences: ['OID.master.2026-11-02']}}]);
  const result = await o(m).listEvents('cal');
  assert.equal(result.full, true); assert.equal(result.syncToken, null);
  assert.deepEqual(result.items[0].raw.recurrence, master.recurrence);
  assert.equal(result.items[0].raw.exceptionOccurrences[0].id, 'moved');
  assert.deepEqual(result.items[0].raw.cancelledOccurrences, ['OID.master.2026-11-02']);
  assert.match(m.calls[2].url, /exceptionOccurrences/);
  assert.match(m.calls[0].headers.Prefer, /ImmutableId/);
});
test('Outlook refuses credential leakage through hostile or cross-calendar pagination', async () => {
  for (const link of ['https://evil.example/next', 'https://graph.microsoft.com.evil.example/v1.0/me/calendars', 'https://graph.microsoft.com/beta/me/calendars', 'https://graph.microsoft.com/v1.0/me/messages']) {
    const m = mock([{body: {value: [], '@odata.nextLink': link}}]);
    await assert.rejects(o(m).listCalendars(), checkCode('unsafe-url'));
    assert.equal(m.calls.length, 1);
  }
});
test('Outlook create retries carry same transactionId and retain native recurrence', async () => {
  const m = mock([{body: {id: 'created'}}, {body: {id: 'created'}}]);
  const event = {subject: 'Weekly', recurrence: {pattern: {type: 'weekly', interval: 2, daysOfWeek: ['tuesday']}, range: {type: 'noEnd', startDate: '2026-10-27'}}};
  const provider = o(m);
  await provider.createEvent('cal', {operationId: 'op', event});
  await provider.createEvent('cal', {operationId: 'op', event});
  assert.deepEqual(JSON.parse(m.calls[0].body), JSON.parse(m.calls[1].body));
  assert.deepEqual(JSON.parse(m.calls[0].body).recurrence, event.recurrence);
});
test('all adapters refuse invitations and writes without ETags before network', async () => {
  const m = mock([]);
  for (const provider of [g(m), o(m)]) {
    await assert.rejects(provider.createEvent('cal', {operationId: 'op', event: {attendees: [{email: 'friend@example.org'}]}}), checkCode('unsupported-invitations'));
    await assert.rejects(provider.deleteEvent('cal', 'id'), checkCode('invalid-etag'));
  }
  await assert.rejects(i(m).createEvent(calendar, {operationId: 'op', event: {ics: ics.replace('UID:test-event', 'UID:test-event\r\nATTENDEE:mailto:friend@example.org')}}), checkCode('unsupported-invitations'));
  assert.equal(m.calls.length, 0);
});
test('iCloud discovers principal, home and writable event calendars', async () => {
  const m = mock([
    {status: 207, body: multistatus(propResponse('/', '<d:current-user-principal><d:href>/123/principal/</d:href></d:current-user-principal>'))},
    {status: 207, body: multistatus(propResponse('/123/principal/', '<c:calendar-home-set><d:href>https://p12-caldav.icloud.com/123/calendars/</d:href></c:calendar-home-set>'))},
    {status: 207, body: multistatus(propResponse('/123/calendars/work/', '<d:resourcetype><d:collection/><c:calendar/></d:resourcetype><d:displayname>Work &amp; family</d:displayname><d:current-user-privilege-set><d:privilege><d:write/></d:privilege></d:current-user-privilege-set><c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>'))},
  ]);
  const result = await i(m).listCalendars();
  assert.equal(result.length, 1); assert.equal(result[0].id, calendar);
  assert.equal(result[0].name, 'Work & family'); assert.equal(result[0].writable, true);
  assert.deepEqual(m.calls.map((r) => [r.method, r.headers.Depth]), [['PROPFIND', '0'], ['PROPFIND', '0'], ['PROPFIND', '1']]);
});
test('iCloud allows only Apple CalDAV hosts including redirects before auth is sent', async () => {
  for (const target of ['http://caldav.icloud.com/', 'https://caldav.icloud.com.evil.example/', 'https://www.icloud.com/', 'https://caldav.icloud.com:444/', 'https://u:p@caldav.icloud.com/', 'https://caldav.icloud.com/a%2fb/']) {
    const m = mock([]);
    await assert.rejects(i(m).listEvents(target), checkCode('unsafe-url'));
    assert.equal(m.calls.length, 0);
  }
  const m = mock([{status: 302, headers: {Location: 'https://evil.example/'}}]);
  await assert.rejects(i(m).listCalendars(), checkCode('unsafe-url'));
  assert.equal(m.calls.length, 1);
});
test('iCloud sync keeps exact calendar body, ETag and deletion tombstones', async () => {
  const report = multistatus(propResponse('/123/calendars/work/a.ics', '<d:getetag>"new"</d:getetag>') + '<d:response><d:href>/123/calendars/work/gone.ics</d:href><d:status>HTTP/1.1 404 Not Found</d:status></d:response>', 'next-token');
  const m = mock([{status: 207, body: report}, {body: ics, headers: {etag: '"new"'}}]);
  const result = await i(m).listEvents(calendar, {syncToken: 'old&amp;token'});
  assert.equal(result.full, false); assert.equal(result.syncToken, 'next-token');
  assert.equal(result.items[0].raw.ics, ics); assert.equal(result.items[0].etag, '"new"');
  assert.equal(result.items[1].deleted, true);
  assert.match(m.calls[0].body, /old&amp;amp;token/);
});
test('iCloud supports full calendar-query when sync-collection is unsupported', async () => {
  const report = multistatus(propResponse('/123/calendars/work/a.ics', `<d:getetag>"one"</d:getetag><c:calendar-data><![CDATA[${ics}]]></c:calendar-data>`));
  const m = mock([{status: 405, body: ''}, {status: 207, body: report}]);
  const result = await i(m).listEvents(calendar);
  assert.equal(result.full, true); assert.equal(result.syncToken, null);
  assert.match(result.items[0].raw.ics, /RRULE:FREQ=WEEKLY;COUNT=3/);
  assert.match(m.calls[1].body, /calendar-query/);
});
test('iCloud deterministic create retries do not overwrite edited calendar resource', async () => {
  const changed = ics.replace('COUNT=3', 'COUNT=4');
  const m = mock([{status: 412, body: ''}, {body: changed, headers: {etag: '"new"'}}]);
  const result = await i(m).createEvent(calendar, {operationId: 'stable-op', event: {ics}});
  assert.equal(m.calls[0].url, `${calendar}${sha('stable-op')}.ics`);
  assert.equal(m.calls[0].headers['If-None-Match'], '*');
  assert.equal(result.alreadyExists, true); assert.equal(result.raw.ics, changed);
  assert.equal(m.calls.length, 2);
});
test('iCloud preserves recurrence and moved exception as one resource', async () => {
  const combined = ics.replace('END:VCALENDAR', 'BEGIN:VEVENT\r\nUID:test-event\r\nRECURRENCE-ID;TZID=Europe/Stockholm:20261102T073000\r\nDTSTART;TZID=Europe/Stockholm:20261103T090000\r\nDTEND;TZID=Europe/Stockholm:20261103T100000\r\nEND:VEVENT\r\nEND:VCALENDAR');
  const m = mock([{status: 204}, {body: combined, headers: {etag: '"new"'}}]);
  await i(m).updateEvent(calendar, `${calendar}a.ics`, {ics: combined}, {etag: '"old"'});
  assert.equal(m.calls[0].body, combined); assert.equal(m.calls[0].headers['If-Match'], '"old"');
});
test('iCloud refuses cross-calendar resources, multi-event writes and XML entities', async () => {
  const m = mock([]);
  await assert.rejects(i(m).deleteEvent(calendar, 'https://p12-caldav.icloud.com/123/calendars/other/a.ics', {etag: '"old"'}), checkCode('unsafe-url'));
  const multiple = ics.replace('END:VCALENDAR', 'BEGIN:VEVENT\r\nUID:other\r\nDTSTART:20261019T070000Z\r\nEND:VEVENT\r\nEND:VCALENDAR');
  await assert.rejects(i(m).createEvent(calendar, {operationId: 'op', event: {ics: multiple}}), checkCode('unsupported-multiple-uids'));
  const hostile = mock([{status: 207, body: '<!DOCTYPE d [<!ENTITY x SYSTEM "file:///etc/passwd">]><d:multistatus xmlns:d="DAV:">&x;</d:multistatus>'}]);
  await assert.rejects(i(hostile).listCalendars(), checkCode('invalid-xml'));
});
test('failed/oversized/paginated responses cannot appear as successful sync', async () => {
  const throttle = mock([{status: 429, headers: {'retry-after': '30'}, body: {secret: 'hide'}}]);
  await assert.rejects(g(throttle).listEvents('primary'), (error) => {assert.equal(error.retryAfter, 30); assert.equal(error.code, 'rate-limited'); return true;});
  const oversized = mock([{headers: {'content-length': '99999999'}, body: '{}'}]);
  await assert.rejects(g(oversized).listCalendars(), checkCode('response-too-large'));
  const duplicate = mock([{body: {items: [], nextPageToken: 'same'}}, {body: {items: [], nextPageToken: 'same'}}]);
  await assert.rejects(g(duplicate).listCalendars(), checkCode('invalid-pagination'));
  const failed = mock([new Error('secret network details')]);
  await assert.rejects(g(failed).listCalendars(), (error) => {assert.equal(error.code, 'network-error'); assert.doesNotMatch(error.message, /secret/); return true;});
});

test('iCloud invalid sync cursor differs from denied calendar access', async () => {
  const expired = mock([{status: 403, body: '<d:error xmlns:d="DAV:"><d:valid-sync-token/></d:error>'}]);
  await assert.rejects(i(expired).listEvents(calendar, {syncToken: 'expired'}), checkCode('sync-reset-required'));
  const denied = mock([{status: 403, body: '<d:error xmlns:d="DAV:"><d:need-privileges/></d:error>'}]);
  await assert.rejects(i(denied).listEvents(calendar, {syncToken: 'previous'}), checkCode('forbidden'));
});
test('Outlook refuses a partial or racing master/exception snapshot', async () => {
  const m = mock([{body: {value: [{id: 'series', type: 'seriesMaster', '@odata.etag': 'W/"one"'}]}}, {body: {id: 'series', '@odata.etag': 'W/"two"', exceptionOccurrences: []}}]);
  await assert.rejects(o(m).listEvents('cal'), checkCode('provider-changed-during-sync'));
});

test('Outlook pre-write getEvent also exposes changed/cancelled series instances', async () => {
  const master = {id: 'master', type: 'seriesMaster', '@odata.etag': 'W/"one"', recurrence: {pattern: {type: 'weekly'}}};
  const m = mock([{body: master}, {body: {...master, cancelledOccurrences: ['OID.master.2026-10-26'], exceptionOccurrences: [{id: 'moved'}]}}]);
  const result = await o(m).getEvent('cal', 'master');
  assert.deepEqual(result.raw.cancelledOccurrences, ['OID.master.2026-10-26']);
  assert.equal(result.raw.exceptionOccurrences[0].id, 'moved');
});

test('Google pre-write master read detects moved and cancelled instances omitted by get', async () => {
  const master = {id: 'master', iCalUID: 'stable-uid', etag: '"one"', recurrence: ['RRULE:FREQ=WEEKLY']};
  const m = mock([{body: master}, {body: {items: [master], nextPageToken: 'next'}}, {body: {items: [{id: 'cancelled', status: 'cancelled', recurringEventId: 'master'}]}}]);
  const result = await g(m).getEvent('cal', 'master');
  assert.equal(result.raw.vardagSeriesHasExceptions, true);
  const query = new URL(m.calls[1].url).searchParams;
  assert.equal(query.get('iCalUID'), 'stable-uid'); assert.equal(query.get('singleEvents'), 'false');
});
test('Google complete exception-free series remains writable and racing snapshot fails', async () => {
  const master = {id: 'master', iCalUID: 'stable-uid', etag: '"one"', recurrence: ['RRULE:FREQ=WEEKLY']};
  const m = mock([{body: master}, {body: {items: [master]}}]);
  assert.equal((await g(m).getEvent('cal', 'master')).raw.vardagSeriesHasExceptions, false);
  const race = mock([{body: master}, {body: {items: [{...master, etag: '"two"'}]}}]);
  await assert.rejects(g(race).getEvent('cal', 'master'), checkCode('provider-changed-during-sync'));
});
test('CalDAV cannot hide invitation properties by line-folding', async () => {
  const m = mock([]);
  const hidden = ics.replace('UID:test-event', 'UID:test-event\r\nATTEN\r\n DEE:mailto:friend@example.org');
  await assert.rejects(i(m).createEvent(calendar, {operationId: 'op', event: {ics: hidden}}), checkCode('unsupported-invitations'));
  assert.equal(m.calls.length, 0);
});

test('quarantine recovery uses exactly the same identity as provider create requests', async () => {
  const operationId = 'shared-identity';
  assert.deepEqual(createdEventIdentity('google', 'primary', operationId), {id: `v${sha(operationId)}`});
  assert.deepEqual(createdEventIdentity('icloud', calendar, operationId), {id: `${calendar}${sha(operationId)}.ics`});
  const m = mock([{body: {id: 'created'}}]);
  await o(m).createEvent('cal', {operationId, event: {subject: 'Example'}});
  assert.equal(createdEventIdentity('outlook', 'cal', operationId).transactionId, JSON.parse(m.calls[0].body).transactionId);
});

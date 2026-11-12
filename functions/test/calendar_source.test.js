const {test}=require('node:test');
const assert=require('node:assert/strict');
const {parseCalendar,calendarUrl,publicIp,fetchCalendar}=require('../calendar_source');
const fixture=body=>`BEGIN:VCALENDAR\r\nVERSION:2.0\r\n${body}\r\nEND:VCALENDAR`;
const event=body=>`BEGIN:VEVENT\r\nUID:training\r\nSUMMARY:Träning\r\n${body}\r\nEND:VEVENT`;
test('normalizes webcal, rejects credentials and non-HTTPS',()=>{
 assert.equal(calendarUrl('webcal://example.org/a.ics').protocol,'https:');
 for(const url of ['http://example.org','https://user:pw@example.org','ftp://example.org','https://example.org:444/a']) assert.throws(()=>calendarUrl(url));
});
test('rejects internal IPv4 and IPv6 before any request',async()=>{
 for(const address of ['127.0.0.1','10.1.1.1','169.254.169.254','::1','::ffff:127.0.0.1','fe80::1','fc00::1']) assert.equal(publicIp(address),false);
 await assert.rejects(fetchCalendar('https://internal.test',{lookup:async()=>[{address:'10.1.1.1',family:4}],request:()=>assert.fail('must not connect')}));
});
test('weekly local time survives DST and excludes cancelled date',()=>{
 const text=fixture(event('DTSTART;TZID=Europe/Stockholm:20261019T073000\r\nDTEND;TZID=Europe/Stockholm:20261019T083000\r\nRRULE:FREQ=WEEKLY;COUNT=4\r\nEXDATE;TZID=Europe/Stockholm:20261102T073000'));
 const rows=parseCalendar(text,new Date('2026-10-18'));
 assert.deepEqual(rows.map(r=>[r.date,r.time]),[['2026-10-19','07:30'],['2026-10-26','07:30'],['2026-11-09','07:30']]);
 assert.deepEqual(parseCalendar(text,new Date('2026-10-18')),rows);
});
test('all-day and midnight remain distinct',()=>{
 const rows=parseCalendar(fixture(event('DTSTART;VALUE=DATE:20261026\r\nDTEND;VALUE=DATE:20261027')),new Date('2026-10-18'));
 assert.equal(rows[0].date,'2026-10-26'); assert.equal(rows[0].time,'');
 const midnight=parseCalendar(fixture(event('DTSTART;TZID=Europe/Stockholm:20261026T000000\r\nDTEND;TZID=Europe/Stockholm:20261026T010000')),new Date('2026-10-18'));
 assert.equal(midnight[0].time,'00:00');
});
test('rejects login pages and resource-heavy recurrence',()=>{
 assert.throws(()=>parseCalendar('<html>Login</html>'));
 assert.throws(()=>parseCalendar(fixture(event('DTSTART:20261026T070000Z\r\nRRULE:FREQ=SECONDLY')),new Date('2026-10-18')));
});
test('moved occurrence keeps original identity and cancellation is omitted',()=>{
 const base=event('DTSTART;TZID=Europe/Stockholm:20261019T073000\r\nDTEND;TZID=Europe/Stockholm:20261019T083000\r\nRRULE:FREQ=WEEKLY;COUNT=3');
 const moved=event('RECURRENCE-ID;TZID=Europe/Stockholm:20261026T073000\r\nDTSTART;TZID=Europe/Stockholm:20261027T090000\r\nDTEND;TZID=Europe/Stockholm:20261027T100000');
 const cancelled=event('RECURRENCE-ID;TZID=Europe/Stockholm:20261102T073000\r\nDTSTART;TZID=Europe/Stockholm:20261102T073000\r\nSTATUS:CANCELLED');
 const rows=parseCalendar(fixture(base+'\r\n'+moved+'\r\n'+cancelled),new Date('2026-10-18'));
 assert.equal(rows.length,2); assert.equal(rows[1].date,'2026-10-27'); assert.match(rows[1].icsKey,/2026-10-26/);
});

test('floating times use Stockholm and multi-day holiday occupies each date',()=>{
 const rows=parseCalendar(fixture(event('DTSTART:20261026T073000\r\nDTEND:20261026T083000')),new Date('2026-10-18'));
 assert.equal(rows[0].time,'07:30');
 const days=parseCalendar(fixture(event('DTSTART;VALUE=DATE:20261026\r\nDTEND;VALUE=DATE:20261029')),new Date('2026-10-18'));
 assert.deepEqual(days.map(r=>r.date),['2026-10-26','2026-10-27','2026-10-28']);
 assert.equal(new Set(days.map(r=>r.icsKey)).size,3);
});

test('removed source details clear previously imported values on merge',()=>{
 const {eventFieldsFromParsed}=require('../calendar_feeds')._test;
 const fields=eventFieldsFromParsed({title:'Ny titel',date:'2026-10-26',time:'07:30',icsKey:'stable'}, {targetType:'activity',familyId:'f',importId:'i',createdByUid:'u'});
 assert.equal(fields.endTime,null);assert.equal(fields.location,'');assert.equal(fields.calendarDescription,'');
});

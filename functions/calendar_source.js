const https = require('node:https');
const dns = require('node:dns').promises;
const net = require('node:net');
const ical = require('node-ical');

function calendarUrl(value) {
  let url;
  try { url = new URL(String(value).trim().replace(/^webcal:/i, 'https:')); }
  catch { throw new Error('Ange en giltig kalenderlänk (ICS).'); }
  if (url.protocol !== 'https:' || url.username || url.password || (url.port && url.port !== '443')) {
    throw new Error('Kalenderlänken måste använda HTTPS utan inloggningsuppgifter.');
  }
  return url;
}
function publicIp(ip) {
  if (net.isIPv4(ip)) {
    const [a,b] = ip.split('.').map(Number);
    return !(a === 0 || a === 10 || a === 127 || a >= 224 ||
      (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) || (a === 192 && (b === 168 || b === 0)) ||
      (a === 198 && (b === 18 || b === 19)));
  }
  // Only globally routable IPv6 unicast; excludes mapped IPv4, NAT64 and link-local.
  return net.isIPv6(ip) && /^[23][0-9a-f]{3}:/i.test(ip) && !/^2001:db8:/i.test(ip);
}
async function fetchCalendar(value, deps = {}) {
  const lookup = deps.lookup || dns.lookup;
  const request = deps.request || https.get;
  let url = calendarUrl(value);
  for (let hop = 0; hop < 5; hop++) {
    const host = url.hostname.replace(/^\[|\]$/g, '');
    const addresses = net.isIP(host) ? [{address:host,family:net.isIP(host)}] : await lookup(host, {all:true});
    if (!addresses.length || addresses.some(a => !publicIp(a.address))) throw new Error('Kalenderlänken måste peka på en publik server.');
    const address = addresses[0];
    const result = await new Promise((resolve,reject) => {
      // Pin the checked DNS result to this connection, including on redirects.
      const req = request(url, {lookup: (_h, opts, cb) => opts.all ? cb(null,[address]) : cb(null,address.address,address.family), headers:{accept:'text/calendar','user-agent':'VardagCalendar/1.0'}}, res => {
        if ([301,302,303,307,308].includes(res.statusCode)) { res.resume(); resolve({redirect:res.headers.location}); return; }
        if (res.statusCode !== 200) { res.resume(); reject(new Error('Kunde inte hämta kalendern. Kontrollera delningslänken.')); return; }
        let size=0; const chunks=[];
        res.on('data', chunk => { size+=chunk.length; if(size>2*1024*1024) { req.destroy(); reject(new Error('Kalendern är för stor (max 2 MB).')); } else chunks.push(chunk); });
        res.on('end', () => resolve({text:Buffer.concat(chunks).toString('utf8')}));
        res.on('error', () => reject(new Error('Hämtningen avbröts. Försök igen.')));
      });
      const timer=setTimeout(() => { req.destroy(); reject(new Error('Kalenderhämtningen tog för lång tid.')); },20000);
      req.on('close',()=>clearTimeout(timer));
      req.on('error',()=>reject(new Error('Kunde inte ansluta till kalendern.')));
    });
    if (result.text !== undefined) return result.text;
    if (!result.redirect) throw new Error('Ogiltig omdirigering för kalendern.');
    url=calendarUrl(new URL(result.redirect,url).toString());
  }
  throw new Error('Kalenderlänken omdirigeras för många gånger.');
}
function localParts(d) {
  const p=Object.fromEntries(new Intl.DateTimeFormat('en-GB',{timeZone:'Europe/Stockholm',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(d).map(p=>[p.type,p.value]));
  return {date:`${p.year}-${p.month}-${p.day}`,time:`${p.hour}:${p.minute}`};
}
function parseCalendar(text, now = new Date()) {
  if (!/BEGIN:VCALENDAR/i.test(text) || !/END:VCALENDAR/i.test(text)) throw new Error('Länken gav ingen ICS-kalender. Använd kalenderns delningslänk.');
  const from=new Date(now); from.setUTCHours(0,0,0,0); from.setUTCDate(from.getUTCDate()-1);
  const to=new Date(from); to.setUTCDate(to.getUTCDate()+181);
  // Floating local times belong to the family's Swedish timezone.
  const normalized=text.replace(/\r\n/g,'\n').replace(/^(DTSTART|DTEND|RECURRENCE-ID|EXDATE|RDATE):(\d{8}T\d{6}(?:,\d{8}T\d{6})*)$/gm,'$1;TZID=Europe/Stockholm:$2');
  const events=ical.sync.parseICS(normalized), rows=[];
  for(const [key,event] of Object.entries(events)) {
    if(event.type!=='VEVENT' || event.status==='CANCELLED' || !(event.start instanceof Date)) continue;
    // Reject very frequent recurrences before expansion to keep resource use bounded.
    if(event.rrule && /FREQ=(SECONDLY|MINUTELY|HOURLY)/.test(event.rrule.toString())) throw new Error('Kalendern innehåller för täta upprepningar.');
    for(const instance of ical.expandRecurringEvent(event,{from,to})) {
      const source=instance.event;
      if(source.status==='CANCELLED' || !instance.summary.trim()) continue;
      const start=localParts(instance.start), end=localParts(instance.end);
      const date=instance.isFullDay ? instance.start.toISOString().slice(0,10) : start.date;
      const original=source.recurrenceid || instance.start;
      rows.push({icsKey:`${event.uid||key}|${original.toISOString()}`,title:instance.summary.trim(),date,time:instance.isFullDay?'':start.time,endTime:instance.isFullDay?null:end.time,location:String(source.location||event.location||'').slice(0,2000),description:String(source.description||event.description||'').slice(0,15000),startMs:instance.start.getTime()});
      if (instance.isFullDay) {
        const row=rows[rows.length-1];
        const cursor=new Date(instance.start); cursor.setUTCDate(cursor.getUTCDate()+1);
        while(cursor < instance.end) {
          const date=cursor.toISOString().slice(0,10);
          rows.push({...row,icsKey:`${row.icsKey}|day:${date}`,date,startMs:cursor.getTime()});
          if(rows.length>500) break;
          cursor.setUTCDate(cursor.getUTCDate()+1);
        }
      }
      if(rows.length>500) throw new Error('Kalendern innehåller fler än 500 tillfällen under de närmaste sex månaderna. Välj en mindre kalender.');
    }
  }
  return rows.sort((a,b)=>a.startMs-b.startMs);
}
module.exports={calendarUrl,publicIp,fetchCalendar,parseCalendar};

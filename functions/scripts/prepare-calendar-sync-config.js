#!/usr/bin/env node
'use strict';

// Produces a reviewable template only. Does not read or provision credentials,
// call cloud APIs, change OAuth registrations or enable/deploy calendar sync.
const fs = require('node:fs');
const path = require('node:path');
const destination = process.argv[2];
if (!destination || process.argv.length !== 3) {
  process.stderr.write('Usage: node functions/scripts/prepare-calendar-sync-config.js /tmp/calendar-sync.env.template\n');
  process.exitCode = 2;
} else {
  const template = [
    '# Vardag calendar sync: fill secret values only through approved Secret Manager flow.',
    '# Keep public readiness false until matching provider handlers are deployed and tested.',
    'CALENDAR_GOOGLE_READY=false',
    'CALENDAR_MICROSOFT_READY=false',
    'CALENDAR_ICLOUD_READY=false',
    '',
    '# Exact registered redirect URI for Google Web client and Microsoft Web app:',
    'CALENDAR_OAUTH_REDIRECT_URI=https://us-central1-la-familia-5d9f5.cloudfunctions.net/calendarOAuthCallback',
    'CALENDAR_MICROSOFT_TENANT=common',
    '',
    '# Secret Manager names (empty; this generator never creates real secrets):',
    'CALENDAR_PROVIDER_CONFIG=',
    'CALENDAR_TOKEN_ENCRYPTION_KEY=',
    '',
    '# Provider config JSON may contain only google first: {"google":{"clientId":"...","clientSecret":"..."}}',
    '# Add outlook later to the same encrypted secret: {"google":{...},"outlook":{"clientId":"...","clientSecret":"..."}}',
    '# Google scopes: https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.calendarlist.readonly',
    '# Microsoft delegated scopes: https://graph.microsoft.com/Calendars.ReadWrite offline_access',
    '# Microsoft supported accounts: organizations and personal Microsoft accounts.',
    '# AES key: 32 random bytes, base64 encoded; generate/store only in the approved secret workflow.',
    '# iCloud username and app-specific password are entered by each user in the connection UI, never here.',
    '# Follow functions/calendar_sync/SETUP.md for consent, secret binding and real-account tests.',
    '',
  ].join('\n');
  try {
    fs.writeFileSync(path.resolve(destination), template, {flag: 'wx', mode: 0o600});
    process.stdout.write('Created blank calendar-sync configuration template. No credentials read or generated.\n');
  } catch (error) {
    process.stderr.write(error.code === 'EEXIST' ? 'Destination already exists; no file was overwritten.\n' : 'Could not create the template at the supplied path.\n');
    process.exitCode = 1;
  }
}

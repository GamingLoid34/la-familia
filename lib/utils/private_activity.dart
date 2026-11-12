// May be disabled for a diagnostic build. The server capability gate is
// still required before a private write is accepted.
const privateActivityPilot = bool.fromEnvironment(
  'PRIVATE_EVENT_PILOT',
  defaultValue: true,
);
const privateCapabilityDocument = 'privateCalendarPilot20261030';
const privateCapabilityContract = 'private-v1-20261030';
bool privateCapabilityEnabled(Map<String, dynamic>? data) =>
    data?['enabled'] == true && data?['contract'] == privateCapabilityContract;
const _publicFields = {
  'date',
  'time',
  'endTime',
  'timeMode',
  'isRecurring',
  'recurrence',
};
const _detailFields = {'title', 'piktogram', 'checklist', 'lessonPrep'};

Map<String, dynamic> privateMarker(
  Map<String, dynamic> data,
  String uid,
  String name,
) => {
  for (final entry in data.entries)
    if (_publicFields.contains(entry.key)) entry.key: entry.value,
  'familyId': data['familyId'],
  'createdByUid': uid,
  'createdBy': uid,
  'visibility': 'private',
  'privateOwnerUid': uid,
  'title': 'Privat',
  'piktogram': '🔒',
  'type': 'activity',
  'source': 'manual',
  'persons': [name],
  'personUids': [uid],
  'isPending': false,
};

Map<String, dynamic> privateDetail(Map<String, dynamic> data, String uid) => {
  for (final entry in data.entries)
    if (_detailFields.contains(entry.key)) entry.key: entry.value,
  'ownerUid': uid,
  'familyId': data['familyId'],
};

Map<String, dynamic> privateMovedMarker(
  Map<String, dynamic> data,
  String uid,
  String name,
  String seriesId,
  String originalDate,
  String writeId,
) => {
  ...privateMarker(data, uid, name),
  'originalSeriesId': seriesId,
  'originalOccurrenceDate': originalDate,
  'writeId': writeId,
};

Map<String, dynamic> privatePublicChanges(Map<String, dynamic> data) => {
  for (final entry in data.entries)
    if (_publicFields.contains(entry.key)) entry.key: entry.value,
};

Map<String, dynamic> privateDetailChanges(Map<String, dynamic> data) => {
  for (final entry in data.entries)
    if (_detailFields.contains(entry.key)) entry.key: entry.value,
};

Map<String, dynamic> overlayPrivateActivity(
  Map<String, dynamic> marker,
  Map<String, dynamic>? detail,
  String? uid,
) {
  if (uid == null ||
      marker['visibility'] != 'private' ||
      marker['privateOwnerUid'] != uid ||
      detail == null ||
      detail['ownerUid'] != uid ||
      detail['familyId'] != marker['familyId']) {
    return marker;
  }
  return {
    ...marker,
    for (final entry in detail.entries)
      if (_detailFields.contains(entry.key)) entry.key: entry.value,
    '_privateDetailLoaded': true,
  };
}

/// Shared screens and widgets must not use the account-specific overlay.
Map<String, dynamic> publicActivityData(Map<String, dynamic> data) {
  if (data['visibility'] != 'private') return data;
  final names = data['persons'];
  final name = names is List && names.isNotEmpty && names.first is String
      ? names.first as String
      : '';
  return privateMarker(data, data['privateOwnerUid'] as String? ?? '', name);
}

/// Oändrade regler utelämnas ur uppdateringen, inklusive okända fält/undantag.
Map<String, dynamic> recurrenceEditFields({required bool editing,
    required bool changed, required String type, required String start,
    String? end, required List<String> exceptions, required Object deleteValue}) {
  if (editing && !changed) return {};
  if (type == 'none') {
    return editing ? {'recurrence': deleteValue, 'isRecurring': deleteValue} : {};
  }
  return {'isRecurring': true, 'recurrence': {
    'type': type, 'startDate': start, 'endDate': end, 'exceptions': exceptions,
  }};
}

bool supportedRecurrence(String type) =>
    const ['none', 'weekly', 'biweekly', 'monthly'].contains(type);

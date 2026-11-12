/// Vuxnas uppgifter från inkorgen och veckobreven. Samma `tasks` som Android.
class PlanningTask {
  final String id;
  final Map<String, dynamic> data;
  const PlanningTask(this.id, this.data);
  String get title => data['title'] as String? ?? 'Uppgift';
  String? get dueDate => data['dueDate'] as String?;
  bool get done => data['status'] == 'done';
  bool visibleOn(String today, String tomorrow) {
    if (done) return false;
    final showFrom = data['showFromDate'] as String?;
    if (showFrom != null && showFrom.compareTo(today) > 0) return false;
    return dueDate == null ||
        dueDate!.compareTo(tomorrow) <= 0 ||
        showFrom != null;
  }

  static Map<String, dynamic> statusPatch(bool done, Object timestamp) => {
    'status': done ? 'done' : 'open',
    'doneAt': done ? timestamp : null,
  };
}

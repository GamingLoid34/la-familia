import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/task_model.dart';

/// Firestore-åtkomst för fria uppgifter (`tasks`), som Androids
/// `TaskRepositoryImpl`. Anropa bara för förälder/admin — reglerna nekar
/// alla andra, och en nekad fråga ska inte ens ställas från ett barnkonto.
class TaskService {
  TaskService._();

  static CollectionReference<Map<String, dynamic>> get _tasks =>
      FirebaseFirestore.instance.collection('tasks');

  /// Familjens alla uppgifter. Bara likhetsfilter — sorteringen sker lokalt,
  /// så inget sammansatt index behövs.
  static Stream<List<TaskModel>> observe(String familyId) {
    if (familyId.isEmpty) return Stream.value(const []);
    return _tasks.where('familyId', isEqualTo: familyId).snapshots().map(
        (s) => s.docs.map((d) => TaskModel.fromMap(d.id, d.data())).toList());
  }

  static Future<String> add(TaskModel task) async {
    final ref = await _tasks.add(task.toFirestoreMap());
    return ref.id;
  }

  /// Hela dokumentet skrivs, eftersom reglerna validerar alla nycklar. Status
  /// och klartid tas från senaste versionen i en transaktion, så att en
  /// samtidig avbockning av någon annan inte ångras av en redigering.
  static Future<void> update(TaskModel task) =>
      FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = _tasks.doc(task.id);
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw StateError('Uppgiften finns inte längre.');
        }
        final current = TaskModel.fromMap(snap.id, snap.data()!);
        final merged = TaskModel(
          id: task.id,
          familyId: task.familyId,
          title: task.title,
          dueDate: task.dueDate,
          dueTime: task.dueTime,
          hasTime: task.hasTime,
          showFromDate: task.showFromDate,
          assigneeUid: task.assigneeUid,
          aboutUids: task.aboutUids,
          status: current.status,
          sourceNoteId: current.sourceNoteId,
          eventId: current.eventId,
          occurrenceDate: current.occurrenceDate,
          createdByUid: current.createdByUid.isNotEmpty
              ? current.createdByUid
              : task.createdByUid,
          doneAt: current.doneAt,
        );
        tx.set(ref, merged.toFirestoreMap());
      });

  /// Slutför eller återöppna. Läser senaste versionen i en transaktion så att
  /// en samtidig ändring av titel eller datum inte skrivs över.
  static Future<void> setDone(String taskId, bool done) =>
      FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = _tasks.doc(taskId);
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final current = TaskModel.fromMap(snap.id, snap.data()!);
        final next = done
            ? current.copyWith(
                status: TaskModel.statusDone, doneAt: DateTime.now())
            : current.copyWith(status: TaskModel.statusOpen, clearDoneAt: true);
        tx.set(ref, next.toFirestoreMap());
      });

  /// Skjut upp deadline. En uppgift som hunnit bli klar lämnas orörd.
  static Future<void> postpone(String taskId, String newDueDate) =>
      FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = _tasks.doc(taskId);
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final current = TaskModel.fromMap(snap.id, snap.data()!);
        if (current.isDone) return;
        tx.set(ref, current.copyWith(dueDate: newDueDate).toFirestoreMap());
      });

  static Future<void> delete(String taskId) => _tasks.doc(taskId).delete();

  /// Uppgifter som skapats ur en viss anteckning (för "ta bort med det som
  /// skapades").
  static Future<List<TaskModel>> fromNote(String familyId, String noteId) async {
    final snap = await _tasks
        .where('familyId', isEqualTo: familyId)
        .where('sourceNoteId', isEqualTo: noteId)
        .get();
    return snap.docs.map((d) => TaskModel.fromMap(d.id, d.data())).toList();
  }
}

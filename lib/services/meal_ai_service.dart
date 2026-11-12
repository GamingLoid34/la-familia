import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MealIngredient {
  final String namn;
  final String mangd;
  final String enhet;

  const MealIngredient({
    required this.namn,
    this.mangd = '',
    this.enhet = '',
  });

  factory MealIngredient.fromMap(Map<String, dynamic> m) => MealIngredient(
        namn: (m['namn'] as String?)?.trim() ?? '',
        mangd: (m['mangd'] as String?)?.trim() ?? '',
        enhet: (m['enhet'] as String?)?.trim() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'namn': namn,
        'mangd': mangd,
        'enhet': enhet,
      };

  /// Visning / inköpsrad.
  String get shoppingLine {
    final qty = [mangd, enhet].where((s) => s.isNotEmpty).join(' ');
    if (qty.isEmpty) return namn;
    return '$qty $namn';
  }
}

class MealMenuDay {
  final String day;
  final String? dishId;
  final String title;
  final String emoji;
  final List<MealIngredient> ingredients;
  final List<String> steps;
  final int prepMinutes;
  final String? leftoverOfDay;

  const MealMenuDay({
    required this.day,
    this.dishId,
    required this.title,
    required this.emoji,
    this.ingredients = const [],
    this.steps = const [],
    this.prepMinutes = 30,
    this.leftoverOfDay,
  });

  bool get isLeftover => leftoverOfDay != null && leftoverOfDay!.isNotEmpty;

  MealMenuDay copyWith({
    String? day,
    String? dishId,
    bool clearDishId = false,
    String? title,
    String? emoji,
    List<MealIngredient>? ingredients,
    List<String>? steps,
    int? prepMinutes,
    String? leftoverOfDay,
    bool clearLeftover = false,
  }) {
    return MealMenuDay(
      day: day ?? this.day,
      dishId: clearDishId ? null : (dishId ?? this.dishId),
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      ingredients: ingredients ?? this.ingredients,
      steps: steps ?? this.steps,
      prepMinutes: prepMinutes ?? this.prepMinutes,
      leftoverOfDay:
          clearLeftover ? null : (leftoverOfDay ?? this.leftoverOfDay),
    );
  }

  factory MealMenuDay.fromMap(Map<String, dynamic> m) {
    final ings = (m['ingredients'] as List?)
            ?.whereType<Map>()
            .map((e) => MealIngredient.fromMap(Map<String, dynamic>.from(e)))
            .where((i) => i.namn.isNotEmpty)
            .toList() ??
        const <MealIngredient>[];
    final steps = (m['steps'] as List?)
            ?.whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .take(3)
            .toList() ??
        const <String>[];
    return MealMenuDay(
      day: m['day'] as String? ?? '',
      dishId: (m['dishId'] as String?)?.trim().isNotEmpty == true
          ? (m['dishId'] as String).trim()
          : null,
      title: (m['title'] as String?)?.trim() ?? '',
      emoji: (m['emoji'] as String?)?.trim().isNotEmpty == true
          ? (m['emoji'] as String).trim()
          : '🍽️',
      ingredients: ings,
      steps: steps,
      prepMinutes: (m['prepMinutes'] as num?)?.round() ?? 30,
      leftoverOfDay: (m['leftoverOfDay'] as String?)?.trim().isNotEmpty == true
          ? (m['leftoverOfDay'] as String).trim()
          : null,
    );
  }

  Map<String, dynamic> recipeMap() => {
        'ingredients': ingredients.map((i) => i.toMap()).toList(),
        'steps': steps,
        'prepMinutes': prepMinutes,
      };
}

/// Klient för `askMealPlanner`.
class MealAiService {
  static Future<List<MealMenuDay>> askMealPlanner({
    required String startDate,
    required int days,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Inte inloggad');
    }
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('askMealPlanner')
          .call<Map<String, dynamic>>({
        'startDate': startDate,
        'days': days.clamp(1, 7),
      });
      final raw = result.data['menu'] as List<dynamic>? ?? const [];
      return raw
          .map((e) => MealMenuDay.fromMap(Map<String, dynamic>.from(e as Map)))
          .where((d) => d.day.isNotEmpty && d.title.isNotEmpty)
          .toList();
    } catch (e, stack) {
      developer.log('askMealPlanner misslyckades', error: e, stackTrace: stack);
      rethrow;
    }
  }
}

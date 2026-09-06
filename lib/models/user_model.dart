import 'dart:developer' as developer;

import '../app_theme.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String color; // Hex string e.g. 'ff2196f3'
  final String role; // 'parent', 'child', 'youth'
  /// `parent` | `focus` | `youth` | `child` — fokus = avskalad vy för alla roller.
  final String viewMode;
  final int energy; // 1-4
  final String? familyId;
  /// Valfri profilbild (Firebase Storage URL).
  final String? avatarUrl;
  final List<String> fcmTokens;
  final bool pushFamilyEvents;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.color,
    required this.role,
    required this.viewMode,
    required this.energy,
    this.familyId,
    this.avatarUrl,
    this.fcmTokens = const [],
    this.pushFamilyEvents = true,
  });

  static String _defaultViewMode(Map<String, dynamic> data) {
    final v = data['viewMode'] as String?;
    if (v != null && v.isNotEmpty) return v;
    final r = data['role'] as String? ?? 'parent';
    if (r == 'youth') return 'youth';
    if (r == 'child') return 'child';
    return 'parent';
  }

  factory UserModel.fromMap(String uid, Map<String, dynamic> data) {
    return UserModel(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      color: data['color'] ?? AppTheme.memberColorPalette.first,
      role: data['role'] ?? 'parent',
      viewMode: _defaultViewMode(data),
      energy: (data['energy'] as int?) ?? 3,
      familyId: data['familyId'] as String?,
      avatarUrl: data['avatarUrl'] as String?,
      fcmTokens: (data['fcmTokens'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      pushFamilyEvents: data['pushFamilyEvents'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'color': color,
      'role': role,
      'viewMode': viewMode,
      'energy': energy,
      'familyId': familyId,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (fcmTokens.isNotEmpty) 'fcmTokens': fcmTokens,
      'pushFamilyEvents': pushFamilyEvents,
    };
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? color,
    String? role,
    String? viewMode,
    int? energy,
    String? familyId,
    String? avatarUrl,
    List<String>? fcmTokens,
    bool? pushFamilyEvents,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      color: color ?? this.color,
      role: role ?? this.role,
      viewMode: viewMode ?? this.viewMode,
      energy: energy ?? this.energy,
      familyId: familyId ?? this.familyId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      pushFamilyEvents: pushFamilyEvents ?? this.pushFamilyEvents,
    );
  }

  /// Returns the user's color as ARGB int for `Color(...)`.
  int get colorValue {
    try {
      return int.parse(color.startsWith('0x') ? color : '0xFF$color', radix: 16);
    } catch (e, stack) {
      developer.log('UserModel.colorValue parse error for "$color"',
          error: e, stackTrace: stack);
      return int.parse('0xFF${AppTheme.memberColorPalette.first}', radix: 16);
    }
  }

  /// Förälder eller admin — styr import, familjehantering, vyläge m.m.
  bool get isParent => role == 'parent' || role == 'admin';
  bool get isFocusMode => viewMode == 'focus';
  bool get isYouthMode => viewMode == 'youth';
  bool get isChildMode => viewMode == 'child';
}

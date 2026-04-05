class UserModel {
  final String uid;
  final String name;
  final String email;
  final String color; // Hex string e.g. 'ff2196f3'
  final String role; // 'parent', 'child', 'youth'
  final String viewMode; // 'parent', 'focus', 'youth'
  final int energy; // 1-4
  final int weeklyPoints;
  final DateTime? pointsResetDate;
  final String? familyId;
  /// Valfri profilbild (Firebase Storage URL).
  final String? avatarUrl;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.color,
    required this.role,
    required this.viewMode,
    required this.energy,
    required this.weeklyPoints,
    this.pointsResetDate,
    this.familyId,
    this.avatarUrl,
  });

  factory UserModel.fromMap(String uid, Map<String, dynamic> data) {
    return UserModel(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      color: data['color'] ?? 'ff6bae75',
      role: data['role'] ?? 'parent',
      viewMode: data['viewMode'] ?? 'parent',
      energy: (data['energy'] as int?) ?? 3,
      weeklyPoints: (data['weeklyPoints'] as int?) ??
          (data['points'] as int?) ??
          0,
      pointsResetDate: data['pointsResetDate'] != null
          ? (data['pointsResetDate'] as dynamic).toDate()
          : null,
      familyId: data['familyId'] as String?,
      avatarUrl: data['avatarUrl'] as String?,
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
      'weeklyPoints': weeklyPoints,
      'pointsResetDate': pointsResetDate,
      'familyId': familyId,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
    };
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? color,
    String? role,
    String? viewMode,
    int? energy,
    int? weeklyPoints,
    DateTime? pointsResetDate,
    String? familyId,
    String? avatarUrl,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      color: color ?? this.color,
      role: role ?? this.role,
      viewMode: viewMode ?? this.viewMode,
      energy: energy ?? this.energy,
      weeklyPoints: weeklyPoints ?? this.weeklyPoints,
      pointsResetDate: pointsResetDate ?? this.pointsResetDate,
      familyId: familyId ?? this.familyId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  /// Returns the user's color as a Flutter Color object.
  dynamic get colorValue {
    try {
      return int.parse(color.startsWith('0x') ? color : '0xFF$color', radix: 16);
    } catch (_) {
      return 0xFF6BAE75;
    }
  }

  bool get isParent => role == 'parent';
  bool get isFocusMode => viewMode == 'focus';
  bool get isYouthMode => viewMode == 'youth';
}

/// Represents a row in the `profiles` Supabase table.
///
/// The [id] is a UUID that is a foreign key to `auth.users`.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.isAdmin,
  });

  final String id;
  final String username;
  final bool isAdmin;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      isAdmin: json['is_admin'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'is_admin': isAdmin,
    };
  }

  UserProfile copyWith({String? id, String? username, bool? isAdmin}) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'UserProfile(id: $id, username: $username, isAdmin: $isAdmin)';
}

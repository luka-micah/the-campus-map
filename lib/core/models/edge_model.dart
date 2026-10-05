/// Represents a walkable path between two campus locations, stored in the
/// `edges` Supabase table.
class EdgeModel {
  const EdgeModel({
    required this.id,
    required this.fromLocationId,
    required this.toLocationId,
    required this.distanceMeters,
  });

  final String id;
  final String fromLocationId;
  final String toLocationId;
  final double distanceMeters;

  factory EdgeModel.fromJson(Map<String, dynamic> json) {
    return EdgeModel(
      id: json['id'] as String,
      fromLocationId: json['from_location_id'] as String,
      toLocationId: json['to_location_id'] as String,
      distanceMeters: (json['distance_meters'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'from_location_id': fromLocationId,
      'to_location_id': toLocationId,
      'distance_meters': distanceMeters,
    };
  }

  EdgeModel copyWith({
    String? id,
    String? fromLocationId,
    String? toLocationId,
    double? distanceMeters,
  }) {
    return EdgeModel(
      id: id ?? this.id,
      fromLocationId: fromLocationId ?? this.fromLocationId,
      toLocationId: toLocationId ?? this.toLocationId,
      distanceMeters: distanceMeters ?? this.distanceMeters,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgeModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'EdgeModel(id: $id, from: $fromLocationId, to: $toLocationId, '
      'distanceMeters: $distanceMeters)';
}

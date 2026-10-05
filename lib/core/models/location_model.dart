/// Represents a named campus point of interest stored in the `locations` table.
class LocationModel {
  final String id;
  final String name;
  final String department;
  final double lat;
  final double lng;
  final String hours;
  final DateTime createdAt;

  const LocationModel({
    required this.id,
    required this.name,
    required this.department,
    required this.lat,
    required this.lng,
    required this.hours,
    required this.createdAt,
  });

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      id: json['id'] as String,
      name: json['name'] as String,
      department: json['department'] as String? ?? '',
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      hours: json['hours'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'department': department,
      'lat': lat,
      'lng': lng,
      'hours': hours,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

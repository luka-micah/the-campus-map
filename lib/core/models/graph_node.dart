/// Lightweight vertex representation used exclusively by [RoutingService].
///
/// Constructed from [LocationModel] instances. The [id] matches the
/// corresponding [LocationModel.id].
class GraphNode {
  const GraphNode({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String name;
  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphNode && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'GraphNode(id: $id, name: $name, lat: $lat, lng: $lng)';
}

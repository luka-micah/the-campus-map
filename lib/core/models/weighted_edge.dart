/// Internal adjacency-list entry used by [RoutingService].
///
/// Not part of the public API — kept in `core/models` for shared access
/// between [RoutingService] and its tests.
class WeightedEdge {
  const WeightedEdge({required this.targetNodeId, required this.weight});

  /// The ID of the neighbouring [GraphNode].
  final String targetNodeId;

  /// Edge weight in metres (equals the [EdgeModel.distanceMeters] value).
  final double weight;

  @override
  String toString() =>
      'WeightedEdge(targetNodeId: $targetNodeId, weight: $weight)';
}

/// Adjacency-list type alias used throughout [RoutingService].
typedef AdjacencyList = Map<String, List<WeightedEdge>>;

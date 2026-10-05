import 'graph_node.dart';

/// The result of a Dijkstra route computation.
///
/// [nodes] is the ordered list of waypoints from origin to destination.
/// [turnInstructions] has one entry per inter-node step:
///   `turnInstructions[i]` describes the move from `nodes[i]` to `nodes[i+1]`.
/// [totalDistanceMeters] is the sum of all edge weights along the path.
/// [destination] is the final node in [nodes].
class RouteModel {
  const RouteModel({
    required this.nodes,
    required this.turnInstructions,
    required this.totalDistanceMeters,
    required this.destination,
  });

  final List<GraphNode> nodes;
  final List<String> turnInstructions;
  final double totalDistanceMeters;
  final GraphNode destination;

  @override
  String toString() =>
      'RouteModel(nodes: ${nodes.length}, '
      'totalDistanceMeters: $totalDistanceMeters, '
      'destination: ${destination.name})';
}

import 'engine.dart';

// Connections refer to the original cell order in assets/board.json. Nearby
// cells are not necessarily joined by plastic: these are the physical strokes.
const physicalConnections = <String, List<List<int>>>{
  'light green': [
    [0, 1],
    [1, 2],
    [1, 4],
    [2, 3],
    [3, 5],
  ],
  'dark green': [
    [0, 1],
    [1, 2],
    [2, 4],
    [3, 4],
  ],
  'red': [
    [0, 1],
    [1, 2],
    [1, 4],
    [2, 3],
    [4, 5],
  ],
  'dark blue': [
    [0, 1],
    [1, 3],
    [2, 4],
    [3, 5],
    [4, 6],
    [5, 6],
  ],
  'medium blue': [
    [0, 1],
    [1, 3],
    [2, 4],
    [3, 4],
    [4, 5],
  ],
  'light blue': [
    [0, 3],
    [1, 2],
    [2, 3],
    [3, 4],
  ],
  'pink': [
    [0, 2],
    [1, 3],
    [2, 4],
    [3, 5],
    [4, 6],
    [5, 6],
  ],
  'turquoise': [
    [0, 1],
    [0, 2],
    [1, 4],
    [2, 5],
    [3, 5],
  ],
  'brown': [
    [0, 1],
    [0, 4],
    [1, 2],
    [2, 3],
    [3, 5],
  ],
  'purple': [
    [0, 1],
    [0, 3],
    [1, 2],
    [3, 4],
    [4, 5],
  ],
  'orange': [
    [0, 1],
    [0, 3],
    [1, 2],
    [2, 4],
    [3, 5],
  ],
  'yellow': [
    [0, 1],
    [1, 2],
    [2, 5],
    [3, 4],
    [4, 5],
  ],
};

/// Recover the placement's orientation, then transform its physical strokes.
/// Occupancy and solver data stay independent of these visual connections.
List<List<Cell>> pieceStrokes(Board board, Placement placement) {
  final name = board.names[placement.piece];
  final edges = physicalConnections[name];
  if (edges == null) throw StateError('Missing physical strokes for $name');
  final original = (board.data['pieces'][name] as List)
      .map((v) => Cell(v[0] as int, v[1] as int))
      .toList();
  final target = key(normalize(placement.cells));
  for (final flip in [false, true]) {
    for (var rotation = 0; rotation < 6; rotation++) {
      final cells = transformed(original, rotation, flip);
      if (key(normalize(cells)) != target) continue;
      final sourceAnchor = ordered(cells).first;
      final targetAnchor = ordered(placement.cells).first;
      final translation = Cell(
        targetAnchor.q - sourceAnchor.q,
        targetAnchor.r - sourceAnchor.r,
      );
      final placed = cells.map((c) => c.add(translation)).toList();
      return edges.map((e) => [placed[e[0]], placed[e[1]]]).toList();
    }
  }
  throw StateError('Could not orient physical strokes for $name');
}

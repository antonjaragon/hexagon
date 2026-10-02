import 'dart:convert';
import 'dart:io';

import 'package:hexagon_companion/engine.dart';
import 'package:hexagon_companion/piece_strokes.dart';

void require(bool ok, String message) {
  if (!ok) throw StateError(message);
}

void main() {
  final board = Board(
    jsonDecode(File('assets/board.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  for (final p in board.actions) {
    final edges = pieceStrokes(board, p);
    final name = board.names[p.piece];
    require(edges.length == p.cells.length - 1, '$name must not have cycles.');
    final neighbors = {for (final c in p.cells) c: <Cell>{}};
    for (final e in edges) {
      require(
        neighbors.containsKey(e[0]) && neighbors.containsKey(e[1]),
        '$name has a stroke outside its occupied cells.',
      );
      final dq = (e[0].q - e[1].q).abs(), dr = (e[0].r - e[1].r).abs();
      final ds = (e[0].q + e[0].r - e[1].q - e[1].r).abs();
      require(
        dq <= 1 && dr <= 1 && ds <= 1 && dq + dr > 0,
        '$name has an invalid stroke.',
      );
      neighbors[e[0]]!.add(e[1]);
      neighbors[e[1]]!.add(e[0]);
    }
    final seen = <Cell>{};
    void visit(Cell c) {
      if (!seen.add(c)) return;
      for (final n in neighbors[c]!) {
        visit(n);
      }
    }

    visit(p.cells.first);
    require(
      seen.length == p.cells.length,
      '$name must be one connected piece.',
    );
    if (name == 'turquoise') {
      require(
        neighbors.values.where((n) => n.length == 1).length == 2 &&
            neighbors.values.every((n) => n.length <= 2),
        'Turquoise must be a single Z path.',
      );
    }
    if (name == 'red') {
      require(
        neighbors.values.where((n) => n.length == 3).length == 1 &&
            neighbors.values.where((n) => n.length == 1).length == 3,
        'Red must have three branches.',
      );
    }
  }
  print(
    'PASS: physical stroke trees for all ${board.actions.length} legal placements; red branches and turquoise path.',
  );
}

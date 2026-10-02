import 'dart:math' as math;

class Cell {
  final int q, r;
  const Cell(this.q, this.r);
  Cell add(Cell b) => Cell(q + b.q, r + b.r);
  List<int> toJson() => [q, r];
  @override
  bool operator ==(Object other) =>
      other is Cell && q == other.q && r == other.r;
  @override
  int get hashCode => Object.hash(q, r);
}

List<Cell> ordered(Iterable<Cell> cells) =>
    cells.toList()
      ..sort((a, b) => a.q != b.q ? a.q.compareTo(b.q) : a.r.compareTo(b.r));
String key(Iterable<Cell> cells) =>
    ordered(cells).map((c) => '${c.q},${c.r}').join(';');
List<Cell> normalize(Iterable<Cell> cells) {
  final list = ordered(cells);
  final a = list.first;
  return ordered(list.map((c) => Cell(c.q - a.q, c.r - a.r)));
}

List<Cell> transformed(List<Cell> cells, int rotation, bool flip) =>
    cells.map((c) {
      var q = c.q, r = c.r;
      if (flip) {
        final t = q;
        q = r;
        r = t;
      }
      for (var i = 0; i < rotation; i++) {
        final t = q;
        q = -r;
        r = t + r;
      }
      return Cell(q, r);
    }).toList();

class Placement {
  final int piece;
  final List<Cell> cells;
  final BigInt mask;
  Placement(this.piece, this.cells, this.mask);
}

class Board {
  final Map<String, dynamic> data;
  late final int radius;
  late final List<String> names;
  late final Set<Cell> blocked;
  final List<Cell> cells = [], playable = [];
  final List<Placement> actions = [];
  final Map<Cell, int> index = {};
  final Map<String, int> lookup = {};
  late final List<List<int>> byPiece, byCell;
  late final BigInt full;
  Board(this.data) {
    radius = data['grid_radius'] as int;
    names = (data['pieces'] as Map).keys.cast<String>().toList()..sort();
    blocked = (data['blocked'] as List)
        .map((v) => Cell(v[0] as int, v[1] as int))
        .toSet();
    for (var q = -radius; q <= radius; q++) {
      for (var r = -radius; r <= radius; r++) {
        if ([q.abs(), r.abs(), (q + r).abs()].reduce(math.max) <= radius) {
          cells.add(Cell(q, r));
        }
      }
    }
    playable.addAll(cells.where((c) => !blocked.contains(c)));
    for (var i = 0; i < playable.length; i++) {
      index[playable[i]] = i;
    }
    byPiece = List.generate(names.length, (_) => []);
    byCell = List.generate(playable.length, (_) => []);
    full = (BigInt.one << playable.length) - BigInt.one;
    for (var piece = 0; piece < names.length; piece++) {
      final original = (data['pieces'][names[piece]] as List)
          .map((v) => Cell(v[0] as int, v[1] as int))
          .toList();
      final variants = <String, List<Cell>>{};
      for (final flip in [false, true]) {
        for (var rot = 0; rot < 6; rot++) {
          final s = normalize(transformed(original, rot, flip));
          variants[key(s)] = s;
        }
      }
      final variantKeys = variants.keys.toList()..sort();
      final seen = <String>{};
      for (final vk in variantKeys) {
        for (final anchor in playable) {
          final translated = ordered(variants[vk]!.map((c) => c.add(anchor)));
          final k = key(translated);
          if (seen.contains(k) || translated.any((c) => !index.containsKey(c))) {
            continue;
          }
          seen.add(k);
          var mask = BigInt.zero;
          for (final c in translated) {
            mask |= BigInt.one << index[c]!;
          }
          final id = actions.length;
          actions.add(Placement(piece, translated, mask));
          byPiece[piece].add(id);
          lookup['$piece:$k'] = id;
          for (final c in translated) {
            byCell[index[c]!].add(id);
          }
        }
      }
    }
  }
  Map<int, int> parseFixed(Map<String, dynamic> fixed) {
    final result = <int, int>{};
    for (final entry in fixed.entries) {
      final piece = names.indexOf(entry.key);
      final coords = (entry.value as List).map(
        (v) => Cell(v[0] as int, v[1] as int),
      );
      final id = lookup['$piece:${key(coords)}'];
      if (id == null) throw FormatException('Invalid ${entry.key} placement');
      result[piece] = id;
    }
    validate(result);
    return result;
  }

  void validate(Map<int, int> fixed) {
    var occupied = BigInt.zero;
    for (final entry in fixed.entries) {
      if (entry.value < 0 || entry.value >= actions.length) {
        throw const FormatException('Unknown placement');
      }
      final p = actions[entry.value];
      if (entry.key != p.piece || (occupied & p.mask) != BigInt.zero) {
        throw const FormatException('Overlapping pieces');
      }
      occupied |= p.mask;
    }
  }

  Map<String, dynamic> solve(
    Map<int, int> fixed, {
    Duration limit = const Duration(seconds: 20),
  }) {
    validate(fixed);
    var occupied = BigInt.zero;
    var remaining = (1 << names.length) - 1;
    for (final a in fixed.values) {
      occupied |= actions[a].mask;
      remaining &= ~(1 << actions[a].piece);
    }
    final watch = Stopwatch()..start();
    var nodes = 0;
    List<int>? visit(BigInt occ, int rem) {
      nodes++;
      if (watch.elapsed > limit) {
        throw const FormatException(
          'Search timed out. Check recognition and try again.',
        );
      }
      if (rem == 0) return occ == full ? [] : null;
      List<int>? best;
      for (var piece = 0; piece < names.length; piece++) {
        if ((rem & (1 << piece)) == 0) continue;
        final options = byPiece[piece]
            .where((a) => (actions[a].mask & occ) == BigInt.zero)
            .toList();
        if (options.isEmpty) return null;
        if (best == null || options.length < best.length) best = options;
      }
      for (var cell = 0; cell < playable.length; cell++) {
        if ((occ & (BigInt.one << cell)) != BigInt.zero) continue;
        final options = byCell[cell]
            .where(
              (a) =>
                  (rem & (1 << actions[a].piece)) != 0 &&
                  (actions[a].mask & occ) == BigInt.zero,
            )
            .toList();
        if (options.isEmpty) return null;
        if (options.length < best!.length) best = options;
      }
      for (final a in best!) {
        final p = actions[a];
        final tail = visit(occ | p.mask, rem & ~(1 << p.piece));
        if (tail != null) return [a, ...tail];
      }
      return null;
    }

    final answer = visit(occupied, remaining);
    return {
      'solved': answer != null,
      'actions': answer ?? <int>[],
      'nodes': nodes,
      'milliseconds': watch.elapsedMilliseconds,
    };
  }
}

// Isolate entry point keeps search off the phone's UI thread.
Map<String, dynamic> solveWorker(Map<String, dynamic> input) {
  try {
    return Board(input['board'] as Map<String, dynamic>)
        .solve(Map<int, int>.from(input['fixed'] as Map));
  } catch (e) {
    return {'error': e.toString()};
  }
}

class CompanionState {
  Map<int, int> fixed = {};
  List<int> revealed = [];
  final List<List<int>> history = [];
  void show(List<int> actions, {required bool full}) {
    history.add(List.of(revealed));
    revealed = full
        ? [...revealed, ...actions]
        : [...revealed, ...actions.take(1)];
  }

  void hide() {
    history.add(List.of(revealed));
    revealed = [];
  }

  void undo() {
    if (history.isNotEmpty) revealed = history.removeLast();
  }

  void newPhoto(Map<int, int> placements) {
    fixed = Map.of(placements);
    revealed = [];
    history.clear();
  }
}

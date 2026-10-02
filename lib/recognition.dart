import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'engine.dart';

const photoColors = <String, List<int>>{
  'light blue': [0, 161, 224],
  'medium blue': [0, 125, 219],
  'dark blue': [0, 47, 221],
  'turquoise': [0, 203, 152],
  'light green': [127, 231, 0],
  'dark green': [0, 151, 67],
  'yellow': [255, 202, 0],
  'orange': [255, 74, 0],
  'red': [249, 0, 44],
  'pink': [239, 0, 150],
  'purple': [156, 0, 200],
  'brown': [151, 12, 45],
};
List<double> xy(Cell c) => [math.sqrt(3) * (c.q + c.r / 2), -1.5 * c.r];
List<List<double>> canonical(Board b) => [
  Cell(-b.radius, b.radius),
  Cell(0, b.radius),
  Cell(b.radius, 0),
  Cell(b.radius, -b.radius),
  Cell(0, -b.radius),
  Cell(-b.radius, 0),
].map(xy).toList();
List<double> hsv(List<num> rgb) {
  final r = rgb[0] / 255, g = rgb[1] / 255, b = rgb[2] / 255;
  final max = [r, g, b].reduce(math.max), min = [r, g, b].reduce(math.min);
  final d = max - min;
  var h = 0.0;
  if (d > 0) {
    if (max == r) {
      h = 60 * ((g - b) / d % 6);
    } else if (max == g) {
      h = 60 * ((b - r) / d + 2);
    } else {
      h = 60 * ((r - g) / d + 4);
    }
  }
  return [(h % 360) / 2, max == 0 ? 0 : 255 * d / max, max * 255];
}

List<int>? sample(img.Image image, List<double> point, double radius) {
  final x = point[0].round(),
      y = point[1].round(),
      r = math.max(2, radius.round());
  final channels = List.generate(3, (_) => <int>[]);
  var total = 0;
  for (
    var yy = math.max(0, y - r);
    yy <= math.min(image.height - 1, y + r);
    yy += 2
  ) {
    for (
      var xx = math.max(0, x - r);
      xx <= math.min(image.width - 1, x + r);
      xx += 2
    ) {
      total++;
      final p = image.getPixel(xx, yy);
      final rgb = [p.r.toInt(), p.g.toInt(), p.b.toInt()];
      final color = hsv(rgb);
      // Colored plastic is strongly saturated; blue reflections on the black
      // rim should not become additional occupied cells.
      if (color[1] > 145 && color[2] > 55) {
        for (var i = 0; i < 3; i++) {
          channels[i].add(rgb[i]);
        }
      }
    }
  }
  if (total == 0 || channels[0].length / total < .18) return null;
  return channels.map((values) {
    values.sort();
    return values[values.length ~/ 2];
  }).toList();
}

List<double> linearSolve(List<List<double>> a, List<double> y) {
  final n = y.length;
  final m = List.generate(n, (i) => [...a[i], y[i]]);
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var row = col + 1; row < n; row++) {
      if (m[row][col].abs() > m[pivot][col].abs()) pivot = row;
    }
    if (m[pivot][col].abs() < 1e-10) {
      throw const FormatException('Mark six distinct board centers.');
    }
    final tmp = m[col];
    m[col] = m[pivot];
    m[pivot] = tmp;
    final div = m[col][col];
    for (var j = col; j <= n; j++) {
      m[col][j] /= div;
    }
    for (var row = 0; row < n; row++) {
      if (row == col) continue;
      final f = m[row][col];
      for (var j = col; j <= n; j++) {
        m[row][j] -= f * m[col][j];
      }
    }
  }
  return m.map((r) => r.last).toList();
}

List<double> alignment(Board board, List<List<double>> corners) {
  if (corners.length != 6) {
    throw const FormatException('Mark all six outermost cell centers.');
  }
  final source = canonical(board);
  final a = <List<double>>[], y = <double>[];
  for (var i = 0; i < 6; i++) {
    final x = source[i][0],
        v = source[i][1],
        u = corners[i][0],
        w = corners[i][1];
    a.add([x, v, 1, 0, 0, 0, -u * x, -u * v]);
    y.add(u);
    a.add([0, 0, 0, x, v, 1, -w * x, -w * v]);
    y.add(w);
  }
  final normal = List.generate(
    8,
    (i) => List.generate(
      8,
      (j) =>
          List.generate(12, (r) => a[r][i] * a[r][j]).reduce((a, b) => a + b),
    ),
  );
  final rhs = List.generate(
    8,
    (i) => List.generate(12, (r) => a[r][i] * y[r]).reduce((a, b) => a + b),
  );
  return [...linearSolve(normal, rhs), 1];
}

List<double> project(Cell c, List<double> h) {
  final p = xy(c), x = p[0], y = p[1];
  final d = h[6] * x + h[7] * y + 1;
  return [(h[0] * x + h[1] * y + h[2]) / d, (h[3] * x + h[4] * y + h[5]) / d];
}

// Dark-board component -> convex hull -> six-vertex approximation. Suggestions
// always remain editable; low-confidence outlines require manual landmarks.
List<List<double>>? suggestCorners(img.Image original) {
  final small = img.copyResize(original, width: 220);
  final w = small.width, h = small.height;
  final mask = List<bool>.filled(w * h, false);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final p = small.getPixel(x, y);
      mask[y * w + x] = .299 * p.r + .587 * p.g + .114 * p.b < 105;
    }
  }
  // Close tiny gaps using a dilation followed by erosion.
  List<bool> filter(List<bool> source, bool dilate) {
    final result = List<bool>.filled(w * h, false);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        var value = !dilate;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dilate) {
              value = value || source[(y + dy) * w + x + dx];
            } else {
              value = value && source[(y + dy) * w + x + dx];
            }
          }
        }
        result[y * w + x] = value;
      }
    }
    return result;
  }

  final closed = filter(filter(mask, true), false);
  final seen = List<bool>.filled(w * h, false);
  List<List<double>>? componentHull(List<int> component) {
    final pts =
        component.map((i) => [(i % w).toDouble(), (i ~/ w).toDouble()]).toList()
          ..sort(
            (a, b) =>
                a[0] != b[0] ? a[0].compareTo(b[0]) : a[1].compareTo(b[1]),
          );
    double cross(List<double> a, List<double> b, List<double> c) =>
        (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
    final lower = <List<double>>[], upper = <List<double>>[];
    for (final p in pts) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    for (final p in pts.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    final hull = [
      ...lower.take(lower.length - 1),
      ...upper.take(upper.length - 1),
    ];
    if (hull.length < 6) return null;
    while (hull.length > 6) {
      var best = 0, cost = double.infinity;
      for (var i = 0; i < hull.length; i++) {
        final a = hull[(i - 1 + hull.length) % hull.length],
            b = hull[i],
            c = hull[(i + 1) % hull.length];
        final value =
            cross(a, b, c).abs() /
            math.max(
              1,
              math.sqrt(math.pow(c[0] - a[0], 2) + math.pow(c[1] - a[1], 2)),
            );
        if (value < cost) {
          cost = value;
          best = i;
        }
      }
      hull.removeAt(best);
    }
    var area = 0.0;
    for (var i = 0; i < 6; i++) {
      final a = hull[i], b = hull[(i + 1) % 6];
      area += a[0] * b[1] - a[1] * b[0];
    }
    final minX = hull.map((p) => p[0]).reduce(math.min),
        maxX = hull.map((p) => p[0]).reduce(math.max);
    final minY = hull.map((p) => p[1]).reduce(math.min),
        maxY = hull.map((p) => p[1]).reduce(math.max);
    final fill = area.abs() / 2 / ((maxX - minX) * (maxY - minY));
    if (fill < .55 || fill > .91) return null;
    return hull;
  }

  List<List<double>>? bestHull;
  var bestComponentScore = 0.0;
  for (var start = 0; start < closed.length; start++) {
    if (!closed[start] || seen[start]) continue;
    final queue = <int>[start];
    seen[start] = true;
    for (var head = 0; head < queue.length; head++) {
      final i = queue[head], x = i % w, y = i ~/ w;
      for (final d in [
        [1, 0],
        [-1, 0],
        [0, 1],
        [0, -1],
      ]) {
        final nx = x + d[0], ny = y + d[1];
        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
        final n = ny * w + nx;
        if (closed[n] && !seen[n]) {
          seen[n] = true;
          queue.add(n);
        }
      }
    }
    if (queue.length < w * h * .025) continue;
    var left = w, right = 0, top = h, bottom = 0;
    for (final i in queue) {
      left = math.min(left, i % w);
      right = math.max(right, i % w);
      top = math.min(top, i ~/ w);
      bottom = math.max(bottom, i ~/ w);
    }
    final aspect = (right - left + 1) / (bottom - top + 1);
    if (aspect < .65 || aspect > 1.8) continue;
    final dx = ((left + right) / 2 - w / 2) / w,
        dy = ((top + bottom) / 2 - h / 2) / h;
    final touchesEdge =
        left <= 2 || top <= 2 || right >= w - 3 || bottom >= h - 3;
    // Prefer an isolated board to dark background regions at the image edge.
    final candidateHull = componentHull(queue);
    if (candidateHull == null) continue;
    final score =
        (right - left + 1) *
        (bottom - top + 1) *
        math.exp(-3 * (dx * dx + dy * dy)) *
        (touchesEdge ? .04 : 1);
    if (score > bestComponentScore) {
      bestComponentScore = score;
      bestHull = candidateHull;
    }
  }
  final hull = bestHull;
  if (hull == null) return null;
  final cx = hull.map((p) => p[0]).reduce((a, b) => a + b) / 6,
      cy = hull.map((p) => p[1]).reduce((a, b) => a + b) / 6;
  hull.sort(
    (a, b) => math
        .atan2(a[1] - cy, a[0] - cx)
        .compareTo(math.atan2(b[1] - cy, b[0] - cx)),
  );
  var start = 0;
  var distance = double.infinity;
  for (var i = 0; i < 6; i++) {
    final d = (math.atan2(hull[i][1] - cy, hull[i][0] - cx) + 2 * math.pi / 3)
        .abs();
    if (d < distance) {
      distance = d;
      start = i;
    }
  }
  final sx = original.width / w, sy = original.height / h;
  return List.generate(6, (i) {
    final p = hull[(i + start) % 6];
    return [(cx + (p[0] - cx) * .88) * sx, (cy + (p[1] - cy) * .88) * sy];
  });
}

Map<String, dynamic> preparePhoto(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('Use a JPEG or PNG photo.');
  image = img.bakeOrientation(image);
  if (image.width > 1600 || image.height > 1600) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 1600 : null,
      height: image.height > image.width ? 1600 : null,
    );
  }
  return {
    'bytes': Uint8List.fromList(img.encodePng(image)),
    'width': image.width,
    'height': image.height,
    'corners': suggestCorners(image),
  };
}

Map<String, dynamic> recognizeWorker(Map<String, dynamic> input) {
  try {
    final board = Board(input['board'] as Map<String, dynamic>);
    final image = img.decodeImage(input['bytes'] as Uint8List)!;
    final corners = (input['corners'] as List)
        .map((p) => List<double>.from(p as List))
        .toList();
    final h = alignment(board, corners);
    final overrides = Map<String, List<int>>.from(input['colors'] as Map);
    final refs = board.names
        .map((n) => hsv(overrides[n] ?? photoColors[n]!))
        .toList();
    final unit = project(const Cell(0, 0), h),
        next = project(const Cell(1, 0), h);
    final radius =
        math.sqrt(
          math.pow(unit[0] - next[0], 2) + math.pow(unit[1] - next[1], 2),
        ) *
        .24;
    final samples = <Cell, List<double>>{};
    for (final cell in board.playable) {
      final color = sample(image, project(cell, h), radius);
      if (color != null) samples[cell] = hsv(color);
    }
    double hueDelta(List<double> a, List<double> b) {
      final d = (a[0] - b[0]).abs();
      return math.min(d, 180 - d);
    }

    double cost(List<double> a, List<double> b) =>
        hueDelta(a, b) * 5 +
        (a[1] - b[1]).abs() * .08 +
        (a[2] - b[2]).abs() * .12;
    final candidates = <int, double>{};
    final byCell = <Cell, List<int>>{for (final c in samples.keys) c: []};
    var target = BigInt.zero;
    for (final cell in samples.keys) {
      target |= BigInt.one << board.index[cell]!;
    }
    for (var a = 0; a < board.actions.length; a++) {
      final p = board.actions[a];
      if (p.cells.any((c) => !samples.containsKey(c))) continue;
      final costs = p.cells
          .map((c) => cost(samples[c]!, refs[p.piece]))
          .toList();
      if (p.cells.any((c) => hueDelta(samples[c]!, refs[p.piece]) > 18) ||
          costs.reduce((a, b) => a + b) / costs.length > 65) {
        continue;
      }
      candidates[a] = costs.reduce((a, b) => a + b);
      for (final c in p.cells) {
        byCell[c]!.add(a);
      }
    }
    List<int>? best;
    var bestCost = double.infinity;
    final watch = Stopwatch()..start();
    void fit(BigInt occupied, int used, List<int> actions, double current) {
      if (watch.elapsedMilliseconds > 2200 || current >= bestCost) return;
      if (occupied == target) {
        best = List.of(actions);
        bestCost = current;
        return;
      }
      List<int>? options;
      for (final c in samples.keys) {
        if ((occupied & (BigInt.one << board.index[c]!)) != BigInt.zero) {
          continue;
        }
        final legal = byCell[c]!
            .where(
              (a) =>
                  (board.actions[a].mask & occupied) == BigInt.zero &&
                  (used & (1 << board.actions[a].piece)) == 0,
            )
            .toList();
        if (legal.isEmpty) return;
        if (options == null || legal.length < options.length) options = legal;
      }
      options!.sort((a, b) => candidates[a]!.compareTo(candidates[b]!));
      for (final a in options) {
        final p = board.actions[a];
        fit(occupied | p.mask, used | (1 << p.piece), [
          ...actions,
          a,
        ], current + candidates[a]!);
      }
    }

    if (samples.isNotEmpty) fit(BigInt.zero, 0, [], 0);
    final fixed = <int, int>{};
    var uncertain = 0;
    if (best != null) {
      for (final a in best!) {
        final p = board.actions[a];
        fixed[p.piece] = a;
        uncertain += p.cells
            .where((c) => cost(samples[c]!, refs[p.piece]) > 45)
            .length;
      }
    } else {
      final groups = <int, List<Cell>>{};
      for (final entry in samples.entries) {
        var winner = 0, value = double.infinity;
        for (var i = 0; i < refs.length; i++) {
          final v = cost(entry.value, refs[i]);
          if (v < value) {
            value = v;
            winner = i;
          }
        }
        groups.putIfAbsent(winner, () => []).add(entry.key);
      }
      for (final entry in groups.entries) {
        final a = board.lookup['${entry.key}:${key(entry.value)}'];
        if (a != null) {
          fixed[entry.key] = a;
        } else {
          uncertain += entry.value.length;
        }
      }
    }
    board.validate(fixed);
    return {
      'fixed': fixed,
      'uncertain': uncertain,
      'sampled': samples.length,
      'completeFit': best != null,
    };
  } catch (e) {
    return {'error': e.toString()};
  }
}

/// The crop is applied before fresh detection; old landmark coordinates are discarded.
Map<String, dynamic> cropPhoto(Map<String, dynamic> input) {
  final decoded = img.decodeImage(input['bytes'] as Uint8List);
  if (decoded == null) throw const FormatException('Invalid photo.');
  final x = (input['x'] as int).clamp(0, decoded.width - 1).toInt();
  final y = (input['y'] as int).clamp(0, decoded.height - 1).toInt();
  final side = math.min(
    input['side'] as int,
    math.min(decoded.width - x, decoded.height - y),
  );
  if (side < 64) throw const FormatException('Crop is too small.');
  final cropped = img.copyCrop(decoded, x: x, y: y, width: side, height: side);
  // Gentle local sharpness preserves color hues; no aggressive global white balance.
  final processed = img.convolution(
    cropped,
    filter: [0, -.12, 0, -.12, 1.48, -.12, 0, -.12, 0],
  );
  return {
    'bytes': Uint8List.fromList(img.encodePng(processed)),
    'width': processed.width,
    'height': processed.height,
    'corners': suggestCorners(processed),
  };
}

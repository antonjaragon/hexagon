// A standalone Dart regression check. Run from the project root after pub get:
// dart run tool/check_recognition.dart
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

import 'package:hexagon_companion/engine.dart';
import 'package:hexagon_companion/recognition.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final data = jsonDecode(
    File('assets/board.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final board = Board(data);
  Map<String, dynamic> scan(Map<String, dynamic> photo) {
    require(photo['corners'] != null, 'Board outline was not detected.');
    final result = recognizeWorker({
      'board': data,
      'bytes': photo['bytes'],
      'corners': photo['corners'],
      'colors': <String, List<int>>{},
    });
    require(result['error'] == null, 'Recognition error: ${result['error']}');
    return result;
  }

  final original = preparePhoto(
    File('assets/example_photo.jpg').readAsBytesSync(),
  );
  require(
    (scan(original)['fixed'] as Map).length == 12,
    'The original full-board reference must still recognize twelve pieces.',
  );
  final partial = preparePhoto(
    File('test/fixtures/partial_board.jpg').readAsBytesSync(),
  );
  final cropped = cropPhoto({
    'bytes': partial['bytes'],
    'x': 0,
    'y': 200,
    'side': 1200,
  });
  require(cropped['width'] == cropped['height'], 'Output must be square.');
  final result = scan(cropped);
  final fixed = Map<int, int>.from(result['fixed'] as Map);
  final names = fixed.keys.map((p) => board.names[p]).toSet();
  require(
    names.length == 2 &&
        names.contains('light blue') &&
        names.contains('orange'),
    'Expected only the light blue and orange pieces, got $names.',
  );
  require(
    result['completeFit'] == true &&
        result['uncertain'] == 0 &&
        result['sampled'] == 11,
    'Empty rim reflections must not count as colored cells.',
  );
  board.validate(fixed);
  require(
    board.solve(fixed)['actions'] != null,
    'Recognized position must be solvable.',
  );

  // A large dark background patch must not displace the smaller hexagonal board.
  final scene = img.Image(width: 700, height: 700);
  img.fill(scene, color: img.ColorRgb8(220, 210, 190));
  for (var y = 0; y < 700; y++) {
    for (var x = 0; x < 700; x++) {
      final dx = (x - 485).abs().toDouble(), dy = (y - 350).abs().toDouble();
      if (x < 220 || (dx <= 155 && dy <= 180 && dx + dy * .5 <= 155)) {
        scene.setPixelRgb(x, y, 25, 25, 25);
      }
    }
  }
  final outline = suggestCorners(scene);
  require(
    outline != null && outline.every((p) => p[0] > 250),
    'Detector chose the background instead of the hexagonal board.',
  );
  final rectangle = img.Image(width: 400, height: 400);
  img.fill(rectangle, color: img.ColorRgb8(20, 20, 20));
  require(
    suggestCorners(rectangle) == null,
    'A plain dark image needs manual landmarks.',
  );
  print(
    'PASS: full reference, square crop, two-piece recognition, rim reflection rejection, solver validation, distracting background, manual fallback.',
  );
}

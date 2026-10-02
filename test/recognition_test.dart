import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexagon_companion/engine.dart';
import 'package:hexagon_companion/recognition.dart';

void main() {
  test('provided real photo fits twelve whole pieces', () {
    final board = jsonDecode(
      File('assets/board.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final photo = preparePhoto(
      File('assets/example_photo.jpg').readAsBytesSync(),
    );
    expect(photo['corners'], isNotNull);
    final result = recognizeWorker({
      'board': board,
      'bytes': photo['bytes'],
      'corners': photo['corners'],
      'colors': <String, List<int>>{},
    });
    expect(result['error'], isNull);
    final fixed = Map<int, int>.from(result['fixed'] as Map);
    expect(fixed.length, 12);
    expect(Board(board).solve(fixed)['actions'], isEmpty);
  });
  test('degenerate alignment fails clearly', () {
    final board = Board(
      jsonDecode(File('assets/board.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    expect(
      () => alignment(board, List.generate(6, (_) => [0.0, 0.0])),
      throwsFormatException,
    );
  });
  test('invalid image rejected', () {
    expect(
      () => preparePhoto(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}

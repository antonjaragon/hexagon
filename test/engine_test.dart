import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexagon_companion/engine.dart';

void main() {
  late Board board;
  late Map<int, int> reference;
  setUpAll(() {
    board = Board(
      jsonDecode(File('assets/board.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    reference = board.parseFixed(
      Map<String, dynamic>.from(board.data['pieces'] as Map),
    );
  });
  test('catalog and 72-bit masks', () {
    expect(board.playable.length, 72);
    expect(board.actions.length, 1962);
    expect(board.full.bitLength, 72);
    board.validate(reference);
  });
  test('exact cover preserves starting pieces', () {
    final fixed = Map<int, int>.from(reference)..remove(reference.keys.last);
    final result = board.solve(fixed);
    expect(result['solved'], true);
    expect((result['actions'] as List).length, 1);
    final action = board.actions[(result['actions'] as List).first as int];
    expect(action.piece, reference.keys.last);
    expect(fixed.length, 11);
  });
  test('tips accumulate and undo/hide leave photo intact', () {
    final s = CompanionState();
    s.newPhoto(reference);
    s.show([1, 2], full: false);
    s.show([3], full: false);
    expect(s.revealed, [1, 3]);
    s.undo();
    expect(s.revealed, [1]);
    s.hide();
    expect(s.revealed, isEmpty);
    expect(s.fixed, reference);
  });
  test('new photo clears answer history', () {
    final s = CompanionState();
    s.show([1], full: false);
    s.newPhoto({});
    expect(s.revealed, isEmpty);
    expect(s.history, isEmpty);
  });
  test('complete board has no missing actions', () {
    expect(board.solve(reference)['actions'], isEmpty);
  });
}

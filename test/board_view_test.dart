import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexagon_companion/engine.dart';
import 'package:hexagon_companion/board_view.dart';

void main() {
  testWidgets('revealed and photographed pieces render identically', (
    tester,
  ) async {
    final b = Board(
      jsonDecode(File('assets/board.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final a = b.byPiece.first.first;
    final first = GlobalKey(), second = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RepaintBoundary(
                key: first,
                child: SizedBox(
                  width: 280,
                  child: BoardView(board: b, fixed: {b.actions[a].piece: a}),
                ),
              ),
              RepaintBoundary(
                key: second,
                child: SizedBox(
                  width: 280,
                  child: BoardView(board: b, fixed: {}, revealed: [a]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final image1 =
        await (first.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final image2 =
        await (second.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final bytes1 = await image1.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes2 = await image2.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(
      bytes1!.buffer.asUint8List(),
      orderedEquals(bytes2!.buffer.asUint8List()),
    );
    image1.dispose();
    image2.dispose();
  });
}

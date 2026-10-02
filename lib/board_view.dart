import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'engine.dart';
import 'piece_strokes.dart';
import 'recognition.dart' show xy, canonical;

const pieceColors = <String, Color>{
  'light blue': Color(0xff56bce4),
  'medium blue': Color(0xff219bd1),
  'dark blue': Color(0xff3755cf),
  'turquoise': Color(0xff39ccb0),
  'light green': Color(0xffa5d945),
  'dark green': Color(0xff32a468),
  'yellow': Color(0xfff1cb46),
  'orange': Color(0xfff49145),
  'red': Color(0xffeb5369),
  'pink': Color(0xffe776b9),
  'purple': Color(0xffa571d1),
  'brown': Color(0xffb65c70),
};

class BoardView extends StatelessWidget {
  final Board board;
  final Map<int, int> fixed;
  final List<int> revealed;
  final bool landmarks;
  const BoardView({
    super.key,
    required this.board,
    required this.fixed,
    this.revealed = const [],
    this.landmarks = false,
  });
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1.10,
    child: CustomPaint(
      painter: BoardPainter(board, fixed, revealed, landmarks),
    ),
  );
}

class BoardPainter extends CustomPainter {
  final Board board;
  final Map<int, int> fixed;
  final List<int> revealed;
  final bool landmarks;
  BoardPainter(this.board, this.fixed, this.revealed, this.landmarks);
  Offset point(Cell c) {
    final p = xy(c);
    return Offset(p[0], p[1]);
  }

  Path rounded(List<Offset> points, double radius) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = points[i],
          prev = points[(i - 1 + points.length) % points.length],
          next = points[(i + 1) % points.length];
      final before = p + (prev - p) / ((prev - p).distance) * radius,
          after = p + (next - p) / ((next - p).distance) * radius;
      if (i == 0) {
        path.moveTo(before.dx, before.dy);
      } else {
        path.lineTo(before.dx, before.dy);
      }
      path.quadraticBezierTo(p.dx, p.dy, after.dx, after.dy);
    }
    return path..close();
  }

  void piece(Canvas canvas, Placement p) {
    final color = pieceColors[board.names[p.piece]]!;
    final pairs = pieceStrokes(board, p);
    void layer(Color c, double y, double width) {
      final pen = Paint()
        ..color = c
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      for (final pair in pairs) {
        canvas.drawLine(
          point(pair[0]) + Offset(0, y),
          point(pair[1]) + Offset(0, y),
          pen,
        );
      }
      for (final cell in p.cells) {
        canvas.drawCircle(
          point(cell) + Offset(0, y),
          width / 2,
          Paint()..color = c,
        );
      }
    }

    layer(const Color(0x55203131), .10, 1.28);
    layer(color, 0, 1.20);
    final line = Paint()
      ..color = Color.lerp(color, Colors.white, .22)!
      ..strokeWidth = .12
      ..strokeCap = StrokeCap.round;
    for (final pair in pairs) {
      canvas.drawLine(
        point(pair[0]) + const Offset(0, -.23),
        point(pair[1]) + const Offset(0, -.23),
        line,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      (size.width - 18) / (math.sqrt(3) * board.radius * 2 + 3),
      (size.height - 18) / (3 * board.radius + 3),
    );
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    final corners = canonical(board)
        .map((p) => Offset(p[0] * 1.10, p[1] * 1.12))
        .toList();
    final path = rounded(corners, .8);
    canvas.save();
    canvas.translate(0, .15);
    canvas.drawPath(path, Paint()..color = const Color(0xffd9e0db));
    canvas.restore();
    canvas.drawPath(path, Paint()..color = const Color(0xff3e504b));
    for (final cell in board.cells) {
      final center = point(cell);
      if (board.blocked.contains(cell)) {
        final peg = rounded(
          List.generate(
            6,
            (i) =>
                center +
                Offset(
                  .54 * math.cos((60 * i - 30) * math.pi / 180),
                  .54 * math.sin((60 * i - 30) * math.pi / 180),
                ),
          ),
          .12,
        );
        canvas.drawPath(peg, Paint()..color = const Color(0xffbecbc0));
        canvas.save();
        canvas.clipPath(peg);
        final hatch = Paint()
          ..color = const Color(0xff94aa99)
          ..strokeWidth = .045;
        for (var d = -1.0; d < 1; d += .23) {
          canvas.drawLine(
            center + Offset(d - .6, -.6),
            center + Offset(d + .6, .6),
            hatch,
          );
        }
        canvas.restore();
      } else {
        canvas.drawCircle(
          center,
          .49,
          Paint()..color = const Color(0xff293a34),
        );
        canvas.drawCircle(
          center,
          .49,
          Paint()
            ..color = const Color(0xff61736a)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .025,
        );
      }
    }
    // One renderer for photographed and revealed pieces: no circles or ghost styling.
    for (final a in {...fixed.values, ...revealed}) {
      piece(canvas, board.actions[a]);
    }
    canvas.restore();
    if (landmarks) {
      final pts = canonical(board);
      for (var i = 0; i < pts.length; i++) {
        final center = Offset(
          size.width / 2 + pts[i][0] * scale,
          size.height / 2 + pts[i][1] * scale,
        );
        canvas.drawCircle(center, 10, Paint()..color = Colors.white);
        final text = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: const TextStyle(
              color: Color(0xff24463a),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) => true;
}

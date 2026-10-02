import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'recognition.dart';

/// Keeps the whole captured image available until the user confirms the crop.
class SquareCropPage extends StatefulWidget {
  final Map<String, dynamic> photo;
  const SquareCropPage({super.key, required this.photo});
  @override
  State<SquareCropPage> createState() => _SquareCropPageState();
}

class _SquareCropPageState extends State<SquareCropPage> {
  double cx = .5, cy = .5, fraction = 1;
  bool busy = false;
  late final int width = widget.photo['width'] as int;
  late final int height = widget.photo['height'] as int;
  @override
  void initState() {
    super.initState();
    final corners = widget.photo['corners'] as List?;
    if (corners != null && corners.length == 6) {
      final xs = corners.map((p) => (p[0] as num).toDouble()).toList();
      final ys = corners.map((p) => (p[1] as num).toDouble()).toList();
      final left = xs.reduce(math.min), right = xs.reduce(math.max);
      final top = ys.reduce(math.min), bottom = ys.reduce(math.max);
      cx = (left + right) / (2 * width);
      cy = (top + bottom) / (2 * height);
      // Suggestions mark extreme cell centers, inward from the outside rim.
      fraction =
          (math.max(right - left, bottom - top) /
                  .88 *
                  1.08 /
                  math.min(width, height))
              .clamp(.35, 1)
              .toDouble();
    }
  }

  double get side => math.min(width, height) * fraction;
  Rect get crop => Rect.fromLTWH(
    (cx * width - side / 2).clamp(0, width - side).toDouble(),
    (cy * height - side / 2).clamp(0, height - side).toDouble(),
    side,
    side,
  );
  Future<void> confirm() async {
    setState(() => busy = true);
    try {
      final r = crop;
      final result = await compute(cropPhoto, {
        'bytes': widget.photo['bytes'],
        'x': r.left.round(),
        'y': r.top.round(),
        'side': r.width.floor(),
      });
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not crop: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Crop around the board')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Drag the square over the puzzle. Keep the entire rim inside, with a small margin. Remove as much table as possible.',
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = math.min(
                    constraints.maxWidth / width,
                    constraints.maxHeight / height,
                  );
                  return Center(
                    child: SizedBox(
                      width: width * scale,
                      height: height * scale,
                      child: GestureDetector(
                        onPanUpdate: busy
                            ? null
                            : (d) => setState(() {
                                cx = (cx + d.delta.dx / (width * scale))
                                    .clamp(
                                      side / (2 * width),
                                      1 - side / (2 * width),
                                    )
                                    .toDouble();
                                cy = (cy + d.delta.dy / (height * scale))
                                    .clamp(
                                      side / (2 * height),
                                      1 - side / (2 * height),
                                    )
                                    .toDouble();
                              }),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              widget.photo['bytes'] as Uint8List,
                              fit: BoxFit.fill,
                            ),
                            CustomPaint(painter: _CropPainter(crop, scale)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                const Text('Crop size'),
                Expanded(
                  child: Slider(
                    value: fraction,
                    min: .35,
                    max: 1,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => fraction = v),
                  ),
                ),
              ],
            ),
            if (busy) const LinearProgressIndicator(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : confirm,
                child: const Text('Use square crop'),
              ),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => Navigator.pop(context, widget.photo),
              child: const Text('Use full photo if the board will not fit'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  final Rect crop;
  final double scale;
  _CropPainter(this.crop, this.scale);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      crop.left * scale,
      crop.top * scale,
      crop.width * scale,
      crop.height * scale,
    );
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = const Color(0x99000000));
    canvas.drawRect(
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final grid = Paint()
      ..color = const Color(0x77ffffff)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(r.left + r.width * i / 3, r.top),
        Offset(r.left + r.width * i / 3, r.bottom),
        grid,
      );
      canvas.drawLine(
        Offset(r.left, r.top + r.height * i / 3),
        Offset(r.right, r.top + r.height * i / 3),
        grid,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) =>
      old.crop != crop || old.scale != scale;
}

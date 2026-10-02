import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import 'engine.dart';
import 'crop.dart';
import 'recognition.dart';
import 'board_view.dart';

void main() => runApp(const CompanionApp());

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Hexagon companion',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff317565)),
      scaffoldBackgroundColor: const Color(0xfff7f6f2),
    ),
    home: const CompanionScreen(),
  );
}

class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key});
  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen> {
  Board? board;
  final session = CompanionState();
  final picker = ImagePicker();
  bool busy = false, hasPhoto = false;
  String status = 'Take a photo of your starting board.';
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      final data = jsonDecode(
        await rootBundle.loadString('assets/board.json'),
      ) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => board = Board(data));
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
      final lost = await picker.retrieveLostData();
      if (!mounted) return;
      if (!lost.isEmpty && lost.files?.isNotEmpty == true) {
        await review(await lost.files!.first.readAsBytes());
      } else if (lost.exception != null) {
        setState(
          () => status = 'Camera recovery failed. Please take another photo.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Could not initialize: $e');
    }
  }

  Future<void> capture() async {
    if (busy || board == null) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take one photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Use an existing photo'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final file = await picker.pickImage(
        source: source,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 95,
        requestFullMetadata: false,
      );
      if (file != null) {
        await review(await file.readAsBytes());
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => status =
              'Camera/photo permission unavailable: ${e.message ?? e.code}',
        );
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Could not read photo: $e');
    }
  }

  Future<void> review(Uint8List bytes) async {
    if (!mounted || board == null) return;
    setState(() => busy = true);
    try {
      final prepared = await compute(preparePhoto, bytes);
      if (!mounted) return;
      final cropped = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(builder: (_) => SquareCropPage(photo: prepared)),
      );
      if (!mounted || cropped == null) return;
      final fixed = await Navigator.push<Map<int, int>>(
        context,
        MaterialPageRoute(
          builder: (_) => PhotoReview(board: board!, photo: cropped),
        ),
      );
      if (!mounted) return;
      if (fixed != null) {
        setState(() {
          session.newPhoto(fixed);
          hasPhoto = true;
          status =
              '${fixed.length} pieces recognized. Choose one tip or the full solution.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Photo import failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reveal(bool full) async {
    if (busy || board == null || !hasPhoto) return;
    setState(() => busy = true);
    try {
      final placements = Map<int, int>.of(session.fixed);
      for (final a in session.revealed) {
        placements[board!.actions[a].piece] = a;
      }
      final result = await compute(solveWorker, {
        'board': board!.data,
        'fixed': placements,
      });
      if (!mounted) return;
      if (result['error'] != null) {
        setState(() => status = result['error'] as String);
        return;
      }
      if (result['solved'] != true) {
        setState(
          () => status =
              'No completion fits this photo. Retake it or adjust recognition.',
        );
        return;
      }
      final actions = List<int>.from(result['actions'] as List);
      if (actions.isEmpty) {
        setState(() => status = 'The displayed board is complete.');
        return;
      }
      setState(() {
        session.show(actions, full: full);
        status = full
            ? 'Complete solution shown. Hide answer returns to your photo.'
            : 'Tip: place the ${board!.names[board!.actions[actions.first].piece]} piece as shown. Tap One tip for another.';
      });
    } catch (e) {
      if (mounted) setState(() => status = 'Could not solve: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = board;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hexagon companion'),
        actions: [
          IconButton(
            onPressed: busy ? null : capture,
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'Take a new photo',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Your puzzle, a little help.',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(status, style: const TextStyle(color: Color(0xff526b5d))),
              const SizedBox(height: 8),
              if (busy) const LinearProgressIndicator(),
              Expanded(
                child: Center(
                  child: b == null
                      ? const CircularProgressIndicator()
                      : BoardView(
                          board: b,
                          fixed: session.fixed,
                          revealed: session.revealed,
                        ),
                ),
              ),
              if (!hasPhoto)
                FilledButton.icon(
                  onPressed: busy ? null : capture,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Take a photo'),
                ),
              if (hasPhoto) ...[
                const Text(
                  'Pale textured cells are blocked.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xff718176)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ? null : () => reveal(true),
                        child: const Text('Solve'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: busy ? null : () => reveal(false),
                        child: const Text('One tip'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy || session.history.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  session.undo();
                                  status = 'Previous view restored.';
                                });
                              },
                        child: const Text('Undo'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy || session.revealed.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  session.hide();
                                  status = 'Answer hidden. Photographed pieces are unchanged.';
                                });
                              },
                        child: const Text('Hide answer'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PhotoReview extends StatefulWidget {
  final Board board;
  final Map<String, dynamic> photo;
  const PhotoReview({super.key, required this.board, required this.photo});
  @override
  State<PhotoReview> createState() => _PhotoReviewState();
}

class _PhotoReviewState extends State<PhotoReview> {
  late Uint8List bytes;
  late int width, height;
  late List<List<double>> corners;
  bool marking = false, busy = false, calibrating = false;
  Map<int, int>? fixed;
  String message = 'Check the suggested markers, then recognize.';
  String selected = 'light blue';
  final colors = <String, List<int>>{};
  @override
  void initState() {
    super.initState();
    bytes = widget.photo['bytes'] as Uint8List;
    width = widget.photo['width'] as int;
    height = widget.photo['height'] as int;
    corners =
        (widget.photo['corners'] as List?)
            ?.map((c) => List<double>.from(c as List))
            .toList() ??
        [];
    if (corners.isEmpty) {
      marking = true;
      message = 'Tap center 1: top left extreme cell.';
    }
  }

  Future<void> scan() async {
    if (corners.length != 6) return;
    setState(() => busy = true);
    final result = await compute(recognizeWorker, {
      'board': widget.board.data,
      'bytes': bytes,
      'corners': corners,
      'colors': colors,
    });
    if (!mounted) return;
    setState(() {
      busy = false;
      if (result['error'] != null) {
        message = result['error'] as String;
        fixed = null;
      } else {
        fixed = Map<int, int>.from(result['fixed'] as Map);
        message =
            '${fixed!.length}/12 whole pieces recognized; ${result['uncertain']} cells need review. Check the preview before using it.';
      }
    });
  }

  void tap(Offset point, double displayWidth) {
    if (busy) return;
    final coords = [
      point.dx * width / displayWidth,
      point.dy * width / displayWidth,
    ];
    if (calibrating) {
      final decoded = img.decodeImage(bytes)!;
      final color = sample(decoded, coords, width / 110);
      setState(() {
        if (color == null) {
          message = 'Choose a clearly colored area, avoiding glare.';
        } else {
          colors[selected] = color;
          calibrating = false;
          fixed = null;
          message = 'Color updated. Recognize again.';
        }
      });
    } else if (marking) {
      setState(() {
        corners.add(coords);
        fixed = null;
        if (corners.length == 6) {
          marking = false;
          message = 'Six centers marked. Recognize pieces.';
        } else {
          message =
              'Tap center ${corners.length + 1}: ${['top left', 'top right', 'right', 'bottom right', 'bottom left', 'left'][corners.length]}.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recognize your board')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Mark the six OUTERMOST CELL CENTERS clockwise from top left—not the plastic rim.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return GestureDetector(
                onTapUp: (d) => tap(d.localPosition, w),
                child: AspectRatio(
                  aspectRatio: width / height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(bytes, fit: BoxFit.fill),
                      CustomPaint(
                        painter: LandmarkPainter(corners, width, height),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Text(message),
          if (busy) const LinearProgressIndicator(),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () {
                        setState(() {
                          corners = [];
                          marking = true;
                          calibrating = false;
                          fixed = null;
                          message = 'Tap center 1: top left extreme cell.';
                        });
                      },
                child: const Text('Mark 6 centers'),
              ),
              FilledButton(
                onPressed: busy || corners.length != 6 ? null : scan,
                child: const Text('Recognize'),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: selected,
                  isExpanded: true,
                  items: widget.board.names
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: busy ? null : (v) => setState(() => selected = v!),
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        setState(() {
                          calibrating = true;
                          marking = false;
                          message =
                              'Tap a colorful area of the $selected piece in the photo.';
                        });
                      },
                child: const Text('Sample color'),
              ),
            ],
          ),
          BoardView(
            board: widget.board,
            fixed: fixed ?? {},
            landmarks: fixed == null,
          ),
          if (fixed != null)
            FilledButton(
              onPressed: busy ? null : () => Navigator.pop(context, fixed),
              child: const Text('Use this recognized board'),
            ),
          const SizedBox(height: 10),
          const Text(
            'Missing or incorrect pieces? Adjust the centers or sample their colors and recognize again. Photos stay on your device.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class LandmarkPainter extends CustomPainter {
  final List<List<double>> corners;
  final int width, height;
  LandmarkPainter(this.corners, this.width, this.height);
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < corners.length; i++) {
      final p = Offset(
        corners[i][0] * size.width / width,
        corners[i][1] * size.height / height,
      );
      canvas.drawCircle(p, 11, Paint()..color = const Color(0xff317565));
      canvas.drawCircle(
        p,
        11,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, p - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant LandmarkPainter old) => true;
}

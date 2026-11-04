import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/scratchpad_storage.dart';

/// Pencil-first, per-question working on a scrollable fixed-aspect page.
class OqbScratchpad extends StatefulWidget {
  const OqbScratchpad({
    super.key,
    required this.paperId,
    required this.questionId,
    this.storage,
  });

  final int paperId;
  final int questionId;
  final ScratchpadStorage? storage;

  @override
  State<OqbScratchpad> createState() => _OqbScratchpadState();
}

enum _Tool { pen, eraser }
enum _Paper { plain, grid, ruled }

class _Stroke {
  _Stroke(this.color, this.width, this.points);
  final Color color;
  final double width;
  final List<Offset> points;

  Map<String, Object> toJson() => {
        'color': color.toARGB32(),
        'width': width,
        'points': [for (final p in points) [p.dx, p.dy]],
      };

  factory _Stroke.parse(dynamic raw) {
    if (raw is! Map || raw['points'] is! List ||
        raw['color'] is! num || raw['width'] is! num) {
      throw const FormatException('Invalid stroke');
    }
    final points = <Offset>[];
    for (final value in raw['points'] as List) {
      if (value is! List || value.length != 2 ||
          value[0] is! num || value[1] is! num) {
        throw const FormatException('Invalid point');
      }
      final x = (value[0] as num).toDouble();
      final y = (value[1] as num).toDouble();
      if (!x.isFinite || !y.isFinite) {
        throw const FormatException('Non-finite point');
      }
      points.add(Offset(x, y));
    }
    final width = (raw['width'] as num).toDouble();
    if (!width.isFinite || width <= 0) {
      throw const FormatException('Invalid width');
    }
    return _Stroke(Color((raw['color'] as num).toInt()), width, points);
  }
}

class _OqbScratchpadState extends State<OqbScratchpad>
    with WidgetsBindingObserver {
  static const _pageWidth = 800.0;
  static const _pageHeight = 1800.0;
  static const _colors = <Color>[
    Color(0xFF263341), Color(0xFF3E69AB),
    Color(0xFFC34C45), Color(0xFF398068),
  ];

  final _scroll = ScrollController();
  final _undo = <List<_Stroke>>[];
  final _redo = <List<_Stroke>>[];
  List<_Stroke> _strokes = [];
  late ScratchpadStorage _storage;
  late String _documentKey;
  _Tool _tool = _Tool.pen;
  _Tool _activeTool = _Tool.pen;
  _Paper _paper = _Paper.grid;
  Color _ink = _colors.first;
  double _width = 3.5;
  bool _fingerDrawing = false;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saveFailed = false;
  bool _dirty = false;
  bool _disposed = false;
  int _generation = 0;
  int _saveSerial = 0;
  int? _pointer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _storage = widget.storage ?? FileScratchpadStorage.instance;
    _documentKey = '${widget.paperId}_${widget.questionId}';
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant OqbScratchpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paperId != widget.paperId ||
        oldWidget.questionId != widget.questionId ||
        oldWidget.storage != widget.storage) {
      unawaited(_save());
      _generation++;
      _storage = widget.storage ?? FileScratchpadStorage.instance;
      _documentKey = '${widget.paperId}_${widget.questionId}';
      _pointer = null;
      _strokes = [];
      _undo.clear();
      _redo.clear();
      _loading = true;
      _loadFailed = false;
      _saveFailed = false;
      _dirty = false;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = _generation;
    try {
      final text = await _storage.read(_documentKey);
      final strokes = <_Stroke>[];
      var paper = _Paper.grid;
      var finger = false;
      if (text != null) {
        final data = jsonDecode(text);
        if (data is! Map || data['version'] != 1 || data['strokes'] is! List) {
          throw const FormatException('Invalid working document');
        }
        for (final raw in data['strokes'] as List) {
          strokes.add(_Stroke.parse(raw));
        }
        for (final candidate in _Paper.values) {
          if (candidate.name == data['paper']) paper = candidate;
        }
        finger = data['finger'] == true;
      }
      if (!mounted || _disposed || generation != _generation) return;
      setState(() {
        _strokes = strokes;
        _paper = paper;
        _fingerDrawing = finger;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted && !_disposed && generation == _generation) {
        setState(() { _loading = false; _loadFailed = true; });
      }
    }
  }

  Future<void> _save() async {
    if (_loading || _loadFailed || !_dirty) return;
    final key = _documentKey;
    final storage = _storage;
    final generation = _generation;
    final serial = ++_saveSerial;
    final text = jsonEncode({
      'version': 1,
      'strokes': [for (final stroke in _strokes) stroke.toJson()],
      'paper': _paper.name,
      'finger': _fingerDrawing,
    });
    _dirty = false;
    try {
      await storage.write(key, text);
      if (mounted && !_disposed && generation == _generation && serial == _saveSerial) {
        setState(() => _saveFailed = false);
      }
    } catch (_) {
      if (mounted && !_disposed && generation == _generation && serial == _saveSerial) {
        setState(() { _saveFailed = true; _dirty = true; });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_save());
  }

  @override
  void deactivate() {
    // Includes closing working or changing question while the Pencil is down.
    unawaited(_save());
    super.deactivate();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_save());
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  void _remember() {
    _undo.add(List<_Stroke>.from(_strokes));
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
    _dirty = true;
  }

  void _undoStroke() {
    if (_undo.isEmpty || _pointer != null) return;
    setState(() {
      _redo.add(List<_Stroke>.from(_strokes));
      _strokes = _undo.removeLast();
      _dirty = true;
    });
    unawaited(_save());
  }

  void _redoStroke() {
    if (_redo.isEmpty || _pointer != null) return;
    setState(() {
      _undo.add(List<_Stroke>.from(_strokes));
      _strokes = _redo.removeLast();
      _dirty = true;
    });
    unawaited(_save());
  }

  void _clear() {
    if (_strokes.isEmpty || _pointer != null) return;
    _remember();
    setState(() => _strokes = []);
    unawaited(_save());
  }

  bool _accept(PointerEvent event) => !_loading && !_loadFailed &&
      (event.kind == PointerDeviceKind.stylus ||
       event.kind == PointerDeviceKind.invertedStylus ||
       event.kind == PointerDeviceKind.mouse ||
       (_fingerDrawing && event.kind == PointerDeviceKind.touch));

  Offset _point(Offset local, double scale) => Offset(
        (local.dx / scale).clamp(0.0, _pageWidth).toDouble(),
        (local.dy / scale).clamp(0.0, _pageHeight).toDouble(),
      );

  void _down(PointerDownEvent event, double scale) {
    if (_pointer != null || !_accept(event)) return;
    _pointer = event.pointer;
    _activeTool = event.kind == PointerDeviceKind.invertedStylus ? _Tool.eraser : _tool;
    _remember();
    final p = _point(event.localPosition, scale);
    setState(() {
      if (_activeTool == _Tool.pen) {
        _strokes.add(_Stroke(_ink, _width, [p]));
      } else {
        _erase(p, 14 / scale);
      }
    });
  }

  void _move(PointerMoveEvent event, double scale) {
    if (event.pointer != _pointer) return;
    final p = _point(event.localPosition, scale);
    setState(() {
      _dirty = true;
      if (_activeTool == _Tool.eraser) {
        _erase(p, 14 / scale);
      } else if (_strokes.isNotEmpty) {
        _strokes.last.points.add(p);
      }
    });
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    setState(() => _pointer = null);
    unawaited(_save());
  }

  void _erase(Offset at, double radius) {
    for (var i = _strokes.length - 1; i >= 0; i--) {
      final points = _strokes[i].points;
      var hit = points.any((p) => (p - at).distance <= radius);
      for (var j = 1; j < points.length && !hit; j++) {
        final a = points[j - 1];
        final d = points[j] - a;
        final length = d.dx * d.dx + d.dy * d.dy;
        final t = length == 0 ? 0.0 :
            (((at - a).dx * d.dx + (at - a).dy * d.dy) / length)
                .clamp(0.0, 1.0).toDouble();
        hit = (a + d * t - at).distance <= radius;
      }
      if (hit) { _strokes.removeAt(i); break; }
    }
  }

  Widget _button(String label, IconData icon, VoidCallback? action,
      {bool selected = false}) => IconButton(
        tooltip: label,
        onPressed: _loading || _loadFailed || _pointer != null ? null : action,
        isSelected: selected,
        icon: Icon(icon),
        selectedIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
      );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                _button('Pen', Icons.edit_outlined,
                    () => setState(() => _tool = _Tool.pen), selected: _tool == _Tool.pen),
                _button('Erase strokes', Icons.backspace_outlined,
                    () => setState(() => _tool = _Tool.eraser), selected: _tool == _Tool.eraser),
                _button('Undo', Icons.undo, _undo.isEmpty ? null : _undoStroke),
                _button('Redo', Icons.redo, _redo.isEmpty ? null : _redoStroke),
                for (var i = 0; i < _colors.length; i++)
                  IconButton(
                    tooltip: 'Ink colour ${i + 1}',
                    onPressed: _pointer != null ? null : () => setState(() {
                      _ink = _colors[i];
                      _tool = _Tool.pen;
                    }),
                    icon: Icon(_ink == _colors[i] && _tool == _Tool.pen
                        ? Icons.check_circle : Icons.circle, color: _colors[i]),
                  ),
                PopupMenuButton<double>(
                  tooltip: 'Pen thickness',
                  enabled: _pointer == null,
                  onSelected: (value) => setState(() => _width = value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 2.0, child: Text('Fine')),
                    PopupMenuItem(value: 3.5, child: Text('Medium')),
                    PopupMenuItem(value: 6.0, child: Text('Thick')),
                  ],
                  icon: const Icon(Icons.line_weight),
                ),
                PopupMenuButton<_Paper>(
                  tooltip: 'Paper style',
                  enabled: !_loading && !_loadFailed && _pointer == null,
                  onSelected: (value) {
                    setState(() { _paper = value; _dirty = true; });
                    unawaited(_save());
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: _Paper.plain, child: Text('Plain paper')),
                    PopupMenuItem(value: _Paper.grid, child: Text('Grid paper')),
                    PopupMenuItem(value: _Paper.ruled, child: Text('Ruled paper')),
                  ],
                  icon: const Icon(Icons.grid_on_outlined),
                ),
                FilterChip(
                  label: const Text('Finger drawing'),
                  selected: _fingerDrawing,
                  onSelected: _loading || _loadFailed || _pointer != null ? null : (value) {
                    setState(() { _fingerDrawing = value; _dirty = true; });
                    unawaited(_save());
                  },
                ),
                const SizedBox(width: 8),
                _button('Clear working', Icons.delete_outline,
                    _strokes.isEmpty ? null : _clear),
              ]),
            ),
          ),
          if (_saveFailed)
            MaterialBanner(
              content: const Text('Working is not saved to disk. Keep this session open and retry.'),
              actions: [TextButton(onPressed: () => unawaited(_save()), child: const Text('Retry'))],
            ),
          const Divider(height: 1),
          Expanded(
            child: _loading ? const Center(child: CircularProgressIndicator())
                : _loadFailed ? Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load working. Existing data was not changed.'),
                      TextButton(onPressed: () {
                        setState(() => _loading = true);
                        unawaited(_load());
                      }, child: const Text('Retry')),
                    ],
                  ))
                : LayoutBuilder(builder: (context, constraints) {
                    final scale = constraints.maxWidth / _pageWidth;
                    return ScrollConfiguration(
                      behavior: const MaterialScrollBehavior().copyWith(
                        dragDevices: {
                          if (!_fingerDrawing) PointerDeviceKind.touch,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      child: SingleChildScrollView(
                        controller: _scroll,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: _pageHeight * scale,
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (event) => _down(event, scale),
                            onPointerMove: (event) => _move(event, scale),
                            onPointerUp: _up,
                            onPointerCancel: _up,
                            child: RepaintBoundary(child: CustomPaint(
                              key: const Key('scratchpad-canvas'),
                              painter: _InkPainter(_strokes, _paper, scale),
                              child: const SizedBox.expand(),
                            )),
                          ),
                        ),
                      ),
                    );
                  }),
          ),
        ],
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  const _InkPainter(this.strokes, this.paper, this.scale);
  final List<_Stroke> strokes;
  final _Paper paper;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.save();
    canvas.scale(scale);
    final guide = Paint()..color = const Color(0xFFDCE5E7)..strokeWidth = 1;
    if (paper == _Paper.grid) {
      for (var x = 32.0; x < 800; x += 32) {
        canvas.drawLine(Offset(x, 0), Offset(x, 1800), guide);
      }
    }
    if (paper != _Paper.plain) {
      for (var y = 32.0; y < 1800; y += 32) {
        canvas.drawLine(Offset(0, y), Offset(800, y), guide);
      }
    }
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.width / 2,
            Paint()..color = stroke.color);
      } else {
        final first = stroke.points.first;
        final path = Path()..moveTo(first.dx, first.dy);
        for (final point in stroke.points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) => true;
}

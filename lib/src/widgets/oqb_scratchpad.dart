import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/scratchpad_storage.dart';
import '../services/performance_metrics.dart';
import '../services/pencil_interactions.dart';
import 'scratchpad/ink_controller.dart';
import 'scratchpad/ink_model.dart';
import 'scratchpad/ink_painter.dart';
import 'scratchpad/ink_storage.dart';
import 'scratchpad/ink_gesture_detector.dart';

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

enum _Tool { pen, eraser, segmentEraser, lasso }

class _OqbScratchpadState extends State<OqbScratchpad>
    with WidgetsBindingObserver {
  static const _pageWidth = 800.0;
  static const _pageHeight = 1800.0;
  static const _colors = <Color>[
    Color(0xFF263341),
    Color(0xFF3E69AB),
    Color(0xFFC34C45),
    Color(0xFF398068),
  ];

  StreamSubscription<String>? _pencilSubscription;
  final _scroll = ScrollController();
  final _inkController = InkController();
  Timer? _saveTimer;
  Offset? _hover;
  List<Offset> _lasso = [];
  Rect? _selection;
  Set<InkStroke> _selected = {};
  Offset? _dragStart;
  Offset? _lastErase;
  double _inputScale = 1;
  bool _transformSelection = false;
  late ScratchpadStorage _storage;
  late String _documentKey;
  _Tool _tool = _Tool.pen;
  _Tool _activeTool = _Tool.pen;
  InkPaper _paper = InkPaper.grid;
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
    _inkController.addListener(_inkChanged);
    _pencilSubscription = PencilInteractions.listen((event) {
      if (!mounted || _disposed || _pointer != null) return;
      if (event == 'toggleEraser') {
        setState(() => _tool = _tool == _Tool.pen ? _Tool.eraser : _Tool.pen);
      }
      if (event == 'palette') _showPalette();
    });
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
      _finishInput();
      unawaited(_save());
      _generation++;
      _storage = widget.storage ?? FileScratchpadStorage.instance;
      _documentKey = '${widget.paperId}_${widget.questionId}';
      _pointer = null;
      _inkController.load([]);
      _selection = null;
      _selected = {};
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
      final text = await InkDocumentStorage.read(_storage, _documentKey);
      final strokes = <InkStroke>[];
      var paper = InkPaper.grid;
      var finger = false;
      if (text != null) {
        final data = jsonDecode(text);
        if (data is! Map ||
            (data['version'] != 1 && data['version'] != 2) ||
            data['strokes'] is! List) {
          throw const FormatException('Invalid working document');
        }
        for (final raw in data['strokes'] as List) {
          strokes.add(InkStroke.parse(raw));
        }
        for (final candidate in InkPaper.values) {
          if (candidate.name == data['paper']) paper = candidate;
        }
        finger = data['finger'] == true;
        if (generation == _generation) {
          _inkController.holdToSnap = data['holdToSnap'] != false;
          _inkController.scratchToErase = data['scratchToErase'] != false;
          _inkController.sensitivity = InkPressure.values.firstWhere(
              (v) => v.name == data['pressure'],
              orElse: () => InkPressure.low);
        }
      }
      if (!mounted || _disposed || generation != _generation) return;
      setState(() {
        _inkController.load(strokes);
        _paper = paper;
        _fingerDrawing = finger;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted && !_disposed && generation == _generation) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    if (_loading || _loadFailed || !_dirty) return;
    final key = _documentKey;
    final storage = _storage;
    final generation = _generation;
    final serial = ++_saveSerial;
    final document = <String, dynamic>{
      'version': 2,
      'strokes': [for (final stroke in _inkController.strokes) stroke.toJson()],
      'paper': _paper.name,
      'finger': _fingerDrawing,
      'pressure': _inkController.sensitivity.name,
      'holdToSnap': _inkController.holdToSnap,
      'scratchToErase': _inkController.scratchToErase,
    };
    _dirty = false;
    try {
      await PerformanceMetrics.instance.measure(
          'Ink save', () => InkDocumentStorage.write(storage, key, document));
      if (mounted &&
          !_disposed &&
          generation == _generation &&
          serial == _saveSerial) {
        setState(() => _saveFailed = false);
      }
    } catch (_) {
      if (mounted &&
          !_disposed &&
          generation == _generation &&
          serial == _saveSerial) {
        setState(() {
          _saveFailed = true;
          _dirty = true;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _finishInput();
      unawaited(_save());
    }
  }

  @override
  void deactivate() {
    // Includes closing working or changing question while the Pencil is down.
    _finishInput();
    unawaited(_save());
    super.deactivate();
  }

  @override
  void dispose() {
    _finishInput();
    _disposed = true;
    unawaited(_save());
    _saveTimer?.cancel();
    _inkController.removeListener(_inkChanged);
    _inkController.dispose();
    if (_pencilSubscription != null) {
      unawaited(PencilInteractions.release(_pencilSubscription!));
    }
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  void _inkChanged() {
    if (_loading || _disposed) return;
    if (_selected.isNotEmpty) {
      _selected = _selected.intersection(_inkController.strokes.toSet());
    }
    if (_selected.isEmpty && _tool != _Tool.lasso) _selection = null;
    _dirty = true;
    PerformanceMetrics.instance.count('Strokes', _inkController.strokes.length);
    if (_pointer == null) _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 650),
      () => unawaited(_save()),
    );
  }

  void _undoStroke() {
    _inkController.undo();
    setState(() {});
    _scheduleSave();
  }

  void _redoStroke() {
    _inkController.redo();
    setState(() {});
    _scheduleSave();
  }

  void _clear() {
    if (_pointer != null) return;
    _inkController.replace(_inkController.strokes.toSet(), []);
    setState(() {});
    _scheduleSave();
  }

  void _finishInput() {
    if (_pointer == null) return;
    if (_activeTool == _Tool.pen) {
      _inkController.finish(allowScratch: false);
    }
    if (_activeTool == _Tool.eraser || _activeTool == _Tool.segmentEraser) {
      _inkController.endErase();
    }
    _pointer = null;
  }

  bool _accept(PointerEvent event) =>
      !_loading &&
      !_loadFailed &&
      (event.kind == PointerDeviceKind.stylus ||
          event.kind == PointerDeviceKind.invertedStylus ||
          event.kind == PointerDeviceKind.mouse ||
          (_fingerDrawing && event.kind == PointerDeviceKind.touch));

  Offset _point(Offset local, double scale) => Offset(
        (local.dx / scale).clamp(0.0, _pageWidth).toDouble(),
        (local.dy / scale).clamp(0.0, _pageHeight).toDouble(),
      );

  double _pressure(PointerEvent event) =>
      event.kind == PointerDeviceKind.mouse ||
              event.pressureMax <= event.pressureMin
          ? .5
          : ((event.pressure - event.pressureMin) /
                  (event.pressureMax - event.pressureMin))
              .clamp(0.0, 1.0);

  void _down(PointerDownEvent event, double scale) {
    if (!mounted || _disposed || _pointer != null || !_accept(event)) return;
    _pointer = event.pointer;
    _inputScale = scale;
    _activeTool =
        event.kind == PointerDeviceKind.invertedStylus ? _Tool.eraser : _tool;
    final p = _point(event.localPosition, scale);
    _hover = null;
    if (_activeTool == _Tool.pen) {
      _inkController.color = _ink;
      _inkController.width = _width;
      _inkController.reducedMotion = MediaQuery.disableAnimationsOf(context);
      _inkController.begin(p, pressure: _pressure(event));
    } else if (_activeTool == _Tool.lasso) {
      _dragStart = p;
      _transformSelection =
          _selection?.contains(p) == true && _selected.isNotEmpty;
      if (!_transformSelection) {
        _lasso = [p];
        _selection = Rect.fromPoints(p, p);
        _selected = {};
      }
    } else {
      _inkController.startErase();
      _lastErase = p;
      _inkController.erase(
        p,
        14 / scale,
        segment: _activeTool == _Tool.segmentEraser,
      );
    }
    setState(() {});
  }

  void _move(PointerMoveEvent event, double scale) {
    if (!mounted || _disposed || event.pointer != _pointer) return;
    final p = _point(event.localPosition, scale);
    PerformanceMetrics.instance.count(
      'Active points',
      _inkController.active.length,
    );
    if (_activeTool == _Tool.pen) {
      _inkController.move(p, pressure: _pressure(event));
    } else if (_activeTool == _Tool.lasso) {
      if (!_transformSelection) {
        setState(() {
          if (_lasso.isEmpty || (p - _lasso.last).distance > 2) _lasso.add(p);
          _selection = InkStroke(_ink, 1, _lasso).bounds;
        });
      }
    } else {
      final from = _lastErase ?? p;
      final steps = ((p - from).distance / (7 / scale)).ceil().clamp(1, 1000);
      for (var i = 1; i <= steps; i++) {
        _inkController.erase(
          Offset.lerp(from, p, i / steps)!,
          14 / scale,
          segment: _activeTool == _Tool.segmentEraser,
        );
      }
      _lastErase = p;
    }
  }

  void _up(PointerEvent event) {
    if (!mounted || _disposed || event.pointer != _pointer) return;
    if (_activeTool == _Tool.lasso) {
      if (_transformSelection && _dragStart != null) {
        // Local position has the same scale as the original down event.
        final delta = _point(event.localPosition, _inputScale) - _dragStart!;
        _transformSelected(1, delta);
      } else if (_selection != null) {
        _selected = _inkController.index
            .query(_selection!)
            .where((s) => inkPolygonContains(_lasso, s.bounds.center))
            .toSet();
      }
    } else if (_activeTool == _Tool.pen) {
      _inkController.finish(allowScratch: event is! PointerCancelEvent);
    } else {
      _inkController.endErase();
    }
    setState(() {
      _pointer = null;
      _lasso = [];
    });
    _scheduleSave();
  }

  void _transformSelected(double factor, Offset delta) {
    if (_selected.isEmpty || _selection == null) return;
    final center = _selection!.center;
    final replacements = [
      for (final s in _selected)
        InkStroke(
          s.color,
          s.width * factor,
          s.points.map((p) => center + (p - center) * factor + delta),
          pressures: s.pressures,
          smooth: s.smooth,
        ),
    ];
    _inkController.replace(_selected, replacements);
    _selected = replacements.toSet();
    _selection = Rect.fromCenter(
      center: center + delta,
      width: _selection!.width * factor,
      height: _selection!.height * factor,
    );
    setState(() {});
    _scheduleSave();
  }

  void _showPalette() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            children: [
              for (final color in _colors)
                IconButton(
                  tooltip: 'Select ink',
                  icon: Icon(Icons.circle, color: color),
                  onPressed: () {
                    setState(() {
                      _ink = color;
                      _tool = _Tool.pen;
                    });
                    Navigator.pop(context);
                  },
                ),
              IconButton(
                tooltip: 'Eraser',
                icon: const Icon(Icons.backspace_outlined),
                onPressed: () {
                  setState(() => _tool = _Tool.eraser);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(
    String label,
    IconData icon,
    VoidCallback? action, {
    bool selected = false,
  }) =>
      IconButton(
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
              child: Row(
                children: [
                  _button(
                    'Pen',
                    Icons.edit_outlined,
                    () => setState(() => _tool = _Tool.pen),
                    selected: _tool == _Tool.pen,
                  ),
                  _button(
                    'Erase strokes',
                    Icons.backspace_outlined,
                    () => setState(() => _tool = _Tool.eraser),
                    selected: _tool == _Tool.eraser,
                  ),
                  _button(
                    'Undo',
                    Icons.undo,
                    !_inkController.canUndo ? null : _undoStroke,
                  ),
                  _button(
                    'Redo',
                    Icons.redo,
                    !_inkController.canRedo ? null : _redoStroke,
                  ),
                  _button(
                    'Erase segments',
                    Icons.auto_fix_normal,
                    () => setState(() => _tool = _Tool.segmentEraser),
                    selected: _tool == _Tool.segmentEraser,
                  ),
                  _button(
                    'Select and move ink',
                    Icons.select_all,
                    () => setState(() => _tool = _Tool.lasso),
                    selected: _tool == _Tool.lasso,
                  ),
                  if (_selected.isNotEmpty) ...[
                    _button(
                      'Shrink selection',
                      Icons.zoom_out,
                      () => _transformSelected(.9, Offset.zero),
                    ),
                    _button(
                      'Grow selection',
                      Icons.zoom_in,
                      () => _transformSelected(1.1, Offset.zero),
                    ),
                  ],
                  PopupMenuButton<InkPressure>(
                    tooltip: 'Pressure sensitivity',
                    initialValue: _inkController.sensitivity,
                    onSelected: (value) => setState(() {
                      _inkController.sensitivity = value;
                      _dirty = true;
                      _scheduleSave();
                    }),
                    itemBuilder: (_) => [
                      for (final value in InkPressure.values)
                        PopupMenuItem(value: value, child: Text(value.name)),
                    ],
                    icon: const Icon(Icons.gesture),
                  ),
                  FilterChip(
                    label: const Text('Hold to snap'),
                    selected: _inkController.holdToSnap,
                    onSelected: (v) => setState(() {
                      _inkController.holdToSnap = v;
                      _dirty = true;
                      _scheduleSave();
                    }),
                  ),
                  FilterChip(
                    label: const Text('Scratch to erase'),
                    selected: _inkController.scratchToErase,
                    onSelected: (v) => setState(() {
                      _inkController.scratchToErase = v;
                      _dirty = true;
                      _scheduleSave();
                    }),
                  ),
                  for (var i = 0; i < _colors.length; i++)
                    IconButton(
                      tooltip: 'Ink colour ${i + 1}',
                      onPressed: _pointer != null
                          ? null
                          : () => setState(() {
                                _ink = _colors[i];
                                _tool = _Tool.pen;
                              }),
                      icon: Icon(
                        _ink == _colors[i] && _tool == _Tool.pen
                            ? Icons.check_circle
                            : Icons.circle,
                        color: _colors[i],
                      ),
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
                  PopupMenuButton<InkPaper>(
                    tooltip: 'Paper style',
                    enabled: !_loading && !_loadFailed && _pointer == null,
                    onSelected: (value) {
                      setState(() {
                        _paper = value;
                        _dirty = true;
                      });
                      _scheduleSave();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: InkPaper.plain,
                        child: Text('Plain paper'),
                      ),
                      PopupMenuItem(
                        value: InkPaper.grid,
                        child: Text('Grid paper'),
                      ),
                      PopupMenuItem(
                        value: InkPaper.ruled,
                        child: Text('Ruled paper'),
                      ),
                    ],
                    icon: const Icon(Icons.grid_on_outlined),
                  ),
                  FilterChip(
                    label: const Text('Finger drawing'),
                    selected: _fingerDrawing,
                    onSelected: _loading || _loadFailed || _pointer != null
                        ? null
                        : (value) {
                            setState(() {
                              _fingerDrawing = value;
                              _dirty = true;
                            });
                            _scheduleSave();
                          },
                  ),
                  const SizedBox(width: 8),
                  _button(
                    'Clear working',
                    Icons.delete_outline,
                    _inkController.strokes.isEmpty ? null : _clear,
                  ),
                ],
              ),
            ),
          ),
          if (_saveFailed)
            MaterialBanner(
              content: const Text(
                'Working is not saved to disk. Keep this session open and retry.',
              ),
              actions: [
                TextButton(
                  onPressed: () => unawaited(_save()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadFailed
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Could not load working. Existing data was not changed.',
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() => _loading = true);
                                unawaited(_load());
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
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
                                  onPointerHover: (event) => setState(
                                    () => _hover =
                                        _point(event.localPosition, scale),
                                  ),
                                  onPointerDown: (event) => _down(event, scale),
                                  onPointerMove: (event) => _move(event, scale),
                                  onPointerUp: _up,
                                  onPointerCancel: _up,
                                  child: Stack(
                                    key: const Key('scratchpad-canvas'),
                                    fit: StackFit.expand,
                                    children: [
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          painter: PaperPainter(_paper, scale),
                                        ),
                                      ),
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          painter: CommittedInkPainter(
                                            _inkController,
                                            scale,
                                          ),
                                        ),
                                      ),
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          painter: ActiveInkPainter(
                                            _inkController,
                                            scale,
                                          ),
                                        ),
                                      ),
                                      if (_hover != null || _selection != null)
                                        IgnorePointer(
                                          child: CustomPaint(
                                            painter: _OverlayPainter(
                                              _hover,
                                              _selection,
                                              scale,
                                              _lasso,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.hover, this.selection, this.scale, List<Offset> lasso)
      : lasso = List.of(lasso);
  final List<Offset> lasso;
  final Offset? hover;
  final Rect? selection;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / scale;
    if (hover != null) canvas.drawCircle(hover!, 5 / scale, paint);
    if (lasso.isNotEmpty) {
      final path = Path()..moveTo(lasso.first.dx, lasso.first.dy);
      for (final p in lasso.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path..close(), paint);
    } else if (selection != null) {
      canvas.drawRect(selection!, paint);
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.hover != hover ||
      old.selection != selection ||
      old.scale != scale ||
      old.lasso.length != lasso.length;
}

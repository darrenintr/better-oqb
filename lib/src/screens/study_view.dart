import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/study_controller.dart';
import '../models/oqb_meta.dart';
import '../models/oqb_review.dart';
import '../services/ask_ai.dart';
import '../widgets/oqb_scratchpad.dart';
import '../widgets/oqb_html.dart';
import '../services/local_preferences.dart';
import '../services/scratchpad_storage.dart';
import '../services/mistake_history.dart';
import 'mistake_analytics_view.dart';
import 'study_reader_view.dart' as reader;

export 'study_reader_view.dart'
    show kStudyPanelBreakpoint, kStudyTwoColumnBreakpoint;

/// Keeps the established reader intact while adding independent handwritten
/// working beside it in landscape and below it in portrait.
class StudyView extends StatefulWidget {
  const StudyView({
    super.key,
    required this.controller,
    required this.meta,
    required this.onExit,
    required this.onOpenOriginal,
    this.onSubmit,
    this.review,
    this.onOpenInspector,
    this.onAskAi,
    this.scratchpadStorage,
  });

  final ScratchpadStorage? scratchpadStorage;
  final StudyController controller;
  final OqbMeta meta;
  final VoidCallback onExit;
  final VoidCallback onOpenOriginal;
  final VoidCallback? onOpenInspector;
  final Future<void> Function()? onSubmit;
  final OqbReview? review;
  final Future<bool> Function(AskAiPrompt prompt)? onAskAi;

  @override
  State<StudyView> createState() => _StudyWorkspaceState();
}

class _StudyWorkspaceState extends State<StudyView> {
  bool _working = false;
  double _split = .52;
  bool _preloading = false;
  int? _preloadedId;
  @override
  void initState() {
    super.initState();
    unawaited(_restoreLayout());
  }

  Future<void> _restoreLayout() async {
    try {
      final saved = await LocalPreferences.instance.read('workspace');
      final ratio = saved?['split'];
      if (mounted && ratio is num && ratio.isFinite) {
        setState(() => _split = ratio.toDouble().clamp(.3, .7));
      }
    } catch (_) {}
  }

  void _persistLayout() {
    unawaited(
      LocalPreferences.instance
          .write('workspace', {'split': _split}).catchError((Object _) {}),
    );
  }

  void _preload() {
    final controller = widget.controller;
    final current = controller.current;
    if (_preloading || current == null || _preloadedId == current.id) return;
    _preloadedId = current.id;
    _preloading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        final next = controller.index + 1;
        final questions = controller.session?.questions;
        if (questions != null && next < questions.length) {
          await preloadQuestion(
            context,
            questions[next],
            OqbAssetScope.of(context),
          );
        }
      } finally {
        _preloading = false;
        if (mounted && _preloadedId != widget.controller.current?.id) {
          _preload();
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant StudyView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) _preloadedId = null;
  }

  void _analytics() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MistakeAnalyticsView(
          history: MistakeHistory.instance,
          meta: widget.meta,
          onRetry: (paperId, questionId) {
            final session = widget.controller.session;
            if (session?.paper.id != paperId) return false;
            final at = session!.questions.indexWhere(
              (q) => q.questionId == questionId,
            );
            if (at < 0) return false;
            widget.controller.goTo(at);
            return true;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller.structure,
      builder: (context, _) {
        _preload();
        final session = widget.controller.session;
        final question = widget.controller.current;
        final study = reader.StudyView(
          controller: widget.controller,
          meta: widget.meta,
          onExit: widget.onExit,
          onOpenOriginal: widget.onOpenOriginal,
          onSubmit: widget.onSubmit,
          review: widget.review,
          onOpenInspector: widget.onOpenInspector,
          onAskAi: widget.onAskAi,
        );
        if (session == null || question == null) return study;
        final questionId =
            question.questionId > 0 ? question.questionId : question.id;
        return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _working
                              ? 'Working · question ${widget.controller.questionNumber}'
                              : 'Handwritten working',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Mistake analytics',
                        onPressed: _analytics,
                        icon: const Icon(Icons.insights_outlined),
                      ),
                      IconButton(
                        key: const Key('toggle-working'),
                        tooltip: _working ? 'Close working' : 'Open working',
                        isSelected: _working,
                        onPressed: () => setState(() => _working = !_working),
                        icon: const Icon(Icons.draw_outlined),
                        selectedIcon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!_working) return study;
                  final horizontal = constraints.maxWidth >= 900 &&
                      constraints.maxWidth > constraints.maxHeight;
                  final working = OqbScratchpad(
                    key: ValueKey('working-${session.paper.id}-$questionId'),
                    storage: widget.scratchpadStorage,
                    paperId: session.paper.id,
                    questionId: questionId,
                  );
                  if (!horizontal) return working;
                  return Row(
                    children: [
                      SizedBox(
                        width: (constraints.maxWidth - 24) * _split,
                        child: study,
                      ),
                      Semantics(
                        label: 'Workspace divider',
                        value: '${(_split * 100).round()} percent question',
                        increasedValue:
                            '${(((_split + .1).clamp(.3, .7)) * 100).round()} percent question',
                        decreasedValue:
                            '${(((_split - .1).clamp(.3, .7)) * 100).round()} percent question',
                        onIncrease: () {
                          setState(() => _split = (_split + .1).clamp(.3, .7));
                          _persistLayout();
                        },
                        onDecrease: () {
                          setState(() => _split = (_split - .1).clamp(.3, .7));
                          _persistLayout();
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            key: const Key('workspace-divider'),
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (event) => setState(
                              () => _split = (_split +
                                      event.delta.dx /
                                          (constraints.maxWidth - 24))
                                  .clamp(.3, .7),
                            ),
                            onHorizontalDragEnd: (_) => _persistLayout(),
                            child: const SizedBox(
                              width: 24,
                              child: Center(
                                child: Icon(Icons.drag_indicator, size: 18),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: working),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

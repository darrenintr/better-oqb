import 'package:flutter/material.dart';

import '../controllers/study_controller.dart';
import '../models/oqb_meta.dart';
import '../models/oqb_review.dart';
import '../services/ask_ai.dart';
import '../widgets/oqb_scratchpad.dart';
import 'study_reader_view.dart' as reader;

export 'study_reader_view.dart' show kStudyPanelBreakpoint, kStudyTwoColumnBreakpoint;

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
  });

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
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
        final questionId = question.questionId > 0 ? question.questionId : question.id;
        return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Expanded(child: Text(
                      _working ? 'Working · question ${widget.controller.questionNumber}'
                          : 'Handwritten working',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    )),
                    IconButton(
                      key: const Key('toggle-working'),
                      tooltip: _working ? 'Close working' : 'Open working',
                      isSelected: _working,
                      onPressed: () => setState(() => _working = !_working),
                      icon: const Icon(Icons.draw_outlined),
                      selectedIcon: const Icon(Icons.close),
                    ),
                  ]),
                ),
              ),
            ),
            Expanded(child: LayoutBuilder(builder: (context, constraints) {
              if (!_working) return study;
              final horizontal = constraints.maxWidth >= 900 &&
                  constraints.maxWidth > constraints.maxHeight;
              final working = OqbScratchpad(
                key: ValueKey('working-${session.paper.id}-$questionId'),
                paperId: session.paper.id,
                questionId: questionId,
              );
              return Flex(
                direction: horizontal ? Axis.horizontal : Axis.vertical,
                children: [
                  Expanded(flex: 11, child: study),
                  if (horizontal) const VerticalDivider(width: 1)
                  else const Divider(height: 1),
                  Expanded(flex: 10, child: working),
                ],
              );
            })),
          ],
        );
      },
    );
  }
}

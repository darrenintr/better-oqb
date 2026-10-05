import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/study_controller.dart';
import '../models/oqb_meta.dart';
import '../models/oqb_review.dart';
import '../models/oqb_trial.dart';
import '../widgets/oqb_html.dart';
import '../widgets/question_navigator.dart';

/// Width at which the question navigator becomes a permanent side panel.
const double kStudyPanelBreakpoint = 1000;

/// Content width at which question and answers sit side by side.
const double kStudyTwoColumnBreakpoint = 1100;

/// API-backed study (and review) screen. Renders the current trial question
/// directly from start_trial data; it never reads the OQB page.
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
  });

  final StudyController controller;
  final OqbMeta meta;
  final VoidCallback onExit;
  final VoidCallback onOpenOriginal;
  final VoidCallback? onOpenInspector;

  /// Called after the learner confirmed submission. Null in review mode.
  final Future<void> Function()? onSubmit;

  /// Present in review mode; drives the score summary.
  final OqbReview? review;

  @override
  State<StudyView> createState() => _StudyViewState();
}

class _StudyViewState extends State<StudyView> {
  final FocusNode _focus = FocusNode(debugLabel: 'study');

  StudyController get _controller => widget.controller;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.pageDown) {
      _controller.next();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.pageUp) {
      _controller.previous();
      return KeyEventResult.handled;
    }
    final label = key.keyLabel.toUpperCase();
    if (label.length == 1) {
      final code = label.codeUnitAt(0);
      int? choice;
      if (code >= 65 && code <= 72) choice = code - 65; // A-H
      if (code >= 49 && code <= 56) choice = code - 49; // 1-8
      if (choice != null && !_controller.isReadOnly) {
        _controller.selectChoice(choice);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _confirmSubmit() async {
    final onSubmit = widget.onSubmit;
    if (onSubmit == null) return;
    final controller = _controller;
    final unanswered = controller.total - controller.answeredCount;
    final unsaved = controller.unsavedCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.assignment_turned_in_outlined),
        title: const Text('Submit this paper?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${controller.answeredCount} of ${controller.total} questions answered.'),
            if (unanswered > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$unanswered question${unanswered == 1 ? '' : 's'} unanswered.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (unsaved > 0) ...[
              const SizedBox(height: 8),
              Text('$unsaved answer${unsaved == 1 ? '' : 's'} will be saved first.'),
            ],
            const SizedBox(height: 12),
            const Text('After submitting you cannot change your answers.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit paper'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await onSubmit();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Not submitted: $error')),
      );
    }
  }

  void _openNavigatorSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.review != null) ...[
                  _ReviewSummary(review: widget.review!, meta: widget.meta),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: QuestionNavigator(
                    controller: _controller,
                    onSelected: (_) => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final question = _controller.current;
          if (question == null) {
            return _EmptyTrial(onExit: widget.onExit, onOpenOriginal: widget.onOpenOriginal);
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final showPanel = constraints.maxWidth >= kStudyPanelBreakpoint;
              final contentWidth = constraints.maxWidth - (showPanel ? 300 : 0);
              final twoColumns = contentWidth >= kStudyTwoColumnBreakpoint;
              final compact = constraints.maxWidth < 600;

              final body = _QuestionBody(
                key: ValueKey(question.id),
                controller: _controller,
                question: question,
                meta: widget.meta,
                twoColumns: twoColumns,
                compact: compact,
                onOpenOriginal: widget.onOpenOriginal,
              );

              return Column(
                children: [
                  _StudyHeader(
                    controller: _controller,
                    review: widget.review,
                    compact: compact,
                    onExit: widget.onExit,
                    onSubmit: widget.onSubmit == null ? null : _confirmSubmit,
                    onOpenOriginal: widget.onOpenOriginal,
                    onOpenInspector: widget.onOpenInspector,
                  ),
                  if (_controller.saveState == OqbSaveState.failed)
                    _SaveFailedBanner(controller: _controller),
                  if (_controller.submitError != null && !_controller.isSubmitting)
                    _ErrorBanner(text: 'Submission failed: ${_controller.submitError}'),
                  Expanded(
                    child: showPanel
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 300,
                                child: _SidePanel(
                                  controller: _controller,
                                  review: widget.review,
                                  meta: widget.meta,
                                ),
                              ),
                              const VerticalDivider(width: 1),
                              Expanded(child: body),
                            ],
                          )
                        : body,
                  ),
                  _BottomBar(
                    controller: _controller,
                    compact: compact,
                    showNavigatorButton: !showPanel,
                    onOpenNavigator: _openNavigatorSheet,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _StudyHeader extends StatelessWidget {
  const _StudyHeader({
    required this.controller,
    required this.review,
    required this.compact,
    required this.onExit,
    required this.onSubmit,
    required this.onOpenOriginal,
    this.onOpenInspector,
  });

  final StudyController controller;
  final OqbReview? review;
  final bool compact;
  final VoidCallback onExit;
  final VoidCallback? onSubmit;
  final VoidCallback onOpenOriginal;
  final VoidCallback? onOpenInspector;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = controller.session!;
    final total = controller.total;
    final title = session.paper.title.isNotEmpty ? session.paper.title : 'Paper ${session.paper.id}';
    final progress = total == 0 ? 0.0 : controller.answeredCount / total;

    final subtitle = review != null
        ? _scoreText(review!)
        : '${controller.answeredCount}/$total answered';

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(4, 6, compact ? 4 : 16, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to papers',
                  onPressed: onExit,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (!controller.isReadOnly) _SaveIndicator(controller: controller, compact: compact),
                if (review != null) const _Pill(icon: Icons.fact_check_outlined, label: 'Review'),
                if (controller.isSubmitted && review == null)
                  const _Pill(icon: Icons.check_circle_outline, label: 'Submitted'),
                if (onSubmit != null && !controller.isReadOnly) ...[
                  const SizedBox(width: 8),
                  controller.isSubmitting
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : compact
                          ? IconButton.filledTonal(
                              tooltip: 'Submit paper',
                              onPressed: onSubmit,
                              icon: const Icon(Icons.assignment_turned_in_outlined),
                            )
                          : FilledButton.tonalIcon(
                              onPressed: onSubmit,
                              icon: const Icon(Icons.assignment_turned_in_outlined),
                              label: const Text('Submit'),
                            ),
                ],
                PopupMenuButton<VoidCallback>(
                  tooltip: 'More',
                  onSelected: (action) => action(),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: onOpenOriginal,
                      child: const ListTile(
                        leading: Icon(Icons.open_in_browser),
                        title: Text('Original OQB page'),
                      ),
                    ),
                    if (onOpenInspector != null)
                      PopupMenuItem(
                        value: onOpenInspector!,
                        child: const ListTile(
                          leading: Icon(Icons.monitor_heart_outlined),
                          title: Text('API inspector'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          LinearProgressIndicator(value: progress, minHeight: 3),
        ],
      ),
    );
  }

  static String _scoreText(OqbReview review) {
    final score = review.score;
    final full = review.scoreFull;
    final parts = <String>[
      if (score != null) 'Score ${_fmt(score)}${full != null ? '/${_fmt(full)}' : ''}',
      if (review.hasCorrectness) '${review.correct}/${review.total} correct',
    ];
    return parts.isEmpty ? 'Submitted attempt' : parts.join(' · ');
  }
}

String _fmt(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);

class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.controller, required this.compact});

  final StudyController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, String label, Color color) = switch (controller.saveState) {
      OqbSaveState.saved => (
          Icons.cloud_done_outlined,
          controller.lastSavedAt == null ? 'Synced' : 'Saved',
          scheme.primary,
        ),
      OqbSaveState.pending => (Icons.cloud_queue, 'Unsaved', scheme.tertiary),
      OqbSaveState.saving => (Icons.cloud_upload_outlined, 'Saving…', scheme.tertiary),
      OqbSaveState.failed => (Icons.cloud_off_outlined, 'Not saved', scheme.error),
    };
    return Tooltip(
      message: switch (controller.saveState) {
        OqbSaveState.saved => 'All answers are saved to OQB',
        OqbSaveState.pending => 'Answers will be saved to OQB shortly',
        OqbSaveState.saving => 'Saving answers to OQB',
        OqbSaveState.failed => 'Saving failed: ${controller.saveError}',
      },
      child: Semantics(
        liveRegion: true,
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: color)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: scheme.onSecondaryContainer)),
        ],
      ),
    );
  }
}

class _SaveFailedBanner extends StatelessWidget {
  const _SaveFailedBanner({required this.controller});

  final StudyController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${controller.unsavedCount} answer(s) not saved yet. They are kept '
                'here until OQB accepts them. (${controller.saveError})',
                style: TextStyle(color: scheme.onErrorContainer),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: controller.retryNow,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.controller, required this.review, required this.meta});

  final StudyController controller;
  final OqbReview? review;
  final OqbMeta meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = controller.session!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (review != null) ...[
            _ReviewSummary(review: review!, meta: meta),
            const SizedBox(height: 16),
          ] else ...[
            Text('Questions', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '${controller.answeredCount} answered · '
              '${controller.total - controller.answeredCount} to do'
              '${session.paper.subjectCode.isEmpty ? '' : ' · ${meta.label(session.paper.subjectCode)}'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
          ],
          Expanded(child: QuestionNavigator(controller: controller)),
        ],
      ),
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.review, required this.meta});

  final OqbReview review;
  final OqbMeta meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = review.score;
    final full = review.scoreFull;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Result', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (score != null)
                  _Stat(
                    label: 'Score',
                    value: '${_fmt(score)}${full != null ? ' / ${_fmt(full)}' : ''}',
                  ),
                if (review.hasCorrectness)
                  _Stat(label: 'Correct', value: '${review.correct} / ${review.total}'),
                _Stat(label: 'Answered', value: '${review.answered} / ${review.total}'),
                if (review.session.trial.timeSpent > 0)
                  _Stat(label: 'Time', value: _duration(review.session.trial.timeSpent)),
              ],
            ),
            if (review.hasCorrectness && review.byTopic.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('By topic', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              for (final row in review.byTopic)
                _BreakdownBar(label: meta.label(row.key), row: row),
            ],
            if (review.hasCorrectness && review.byDifficulty.length > 1) ...[
              const SizedBox(height: 10),
              Text('By difficulty', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              for (final row in review.byDifficulty)
                _BreakdownBar(label: meta.difficulty(int.tryParse(row.key) ?? 0), row: row),
            ],
          ],
        ),
      ),
    );
  }

  static String _duration(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes == 0) return '${seconds}s';
    final hours = minutes ~/ 60;
    return hours > 0 ? '${hours}h ${minutes % 60}m' : '${minutes}m ${seconds % 60}s';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _BreakdownBar extends StatelessWidget {
  const _BreakdownBar({required this.label, required this.row});

  final String label;
  final OqbBreakdownRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ),
              Text('${row.correct}/${row.total}', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 2),
          LinearProgressIndicator(
            value: row.ratio,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }
}

class _QuestionBody extends StatelessWidget {
  const _QuestionBody({
    super.key,
    required this.controller,
    required this.question,
    required this.meta,
    required this.twoColumns,
    required this.compact,
    required this.onOpenOriginal,
  });

  final StudyController controller;
  final OqbTrialQuestion question;
  final OqbMeta meta;
  final bool twoColumns;
  final bool compact;
  final VoidCallback onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    final padding = compact ? 12.0 : 24.0;
    final stem = _QuestionStem(
      controller: controller,
      question: question,
      meta: meta,
      onOpenOriginal: onOpenOriginal,
    );
    final answers = _AnswerSection(controller: controller, question: question);

    if (twoColumns) {
      return SelectionArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 6,
              child: ListView(
                padding: EdgeInsets.all(padding),
                children: [stem],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 5,
              child: ListView(
                padding: EdgeInsets.all(padding),
                children: [answers],
              ),
            ),
          ],
        ),
      );
    }

    return SelectionArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(padding, padding, padding, padding + 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  stem,
                  SizedBox(height: compact ? 16 : 24),
                  answers,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionStem extends StatelessWidget {
  const _QuestionStem({
    required this.controller,
    required this.question,
    required this.meta,
    required this.onOpenOriginal,
  });

  final StudyController controller;
  final OqbTrialQuestion question;
  final OqbMeta meta;
  final VoidCallback onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = question.question;
    final tags = <String>[
      if (content != null && content.year.isNotEmpty)
        content.questionNo.isNotEmpty ? '${content.year} Q${content.questionNo}' : content.year,
      if (content != null)
        for (final topic in content.topicCodes.take(2)) meta.label(topic),
      if (content != null && content.difficultyCode > 0) meta.difficulty(content.difficultyCode),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Question ${controller.questionNumber} of ${controller.total}',
              style: theme.textTheme.titleLarge,
            ),
            for (final tag in tags)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(tag, style: theme.textTheme.labelMedium),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (content == null)
          _Notice(
            text: 'OQB did not include this question\'s content.',
            onOpenOriginal: onOpenOriginal,
          )
        else ...[
          OqbHtml(
            content.content,
            textStyle: theme.textTheme.bodyLarge?.copyWith(height: 1.5, fontSize: 17),
          ),
          if (content.url.isNotEmpty) ...[
            const SizedBox(height: 12),
            content.urlLooksLikeImage
                ? OqbImage(url: resolveOqbUrl(content.url))
                : Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: onOpenOriginal,
                      icon: const Icon(Icons.attachment),
                      label: const Text('View attachment in original OQB'),
                    ),
                  ),
          ],
          if (content.content.trim().isEmpty && content.url.isEmpty)
            _Notice(text: 'This question has no text content.', onOpenOriginal: onOpenOriginal),
        ],
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.onOpenOriginal});

  final String text;
  final VoidCallback onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(text),
        trailing: TextButton(onPressed: onOpenOriginal, child: const Text('Original OQB')),
      ),
    );
  }
}

class _AnswerSection extends StatelessWidget {
  const _AnswerSection({required this.controller, required this.question});

  final StudyController controller;
  final OqbTrialQuestion question;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = question.question;
    final answer = controller.answerFor(question);
    final suggested = content?.suggestedAnswer;
    final review = controller.isReadOnly;

    if (content == null || !content.isMultipleChoice) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Answer', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                answer.isNotEmpty
                    ? 'Your answer: ${answer.raw ?? answer.serialize()}'
                    : 'This question type is answered in the original OQB page.',
              ),
              if (review) ..._reviewExtras(context, content),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final choice in content.choices) ...[
          _AnswerCard(
            choice: choice,
            selected: answer.choices.contains(choice.index),
            correct: review && suggested != null ? suggested.choices.contains(choice.index) : null,
            enabled: !review && !controller.isSubmitting,
            onTap: () => controller.selectChoice(choice.index),
          ),
          const SizedBox(height: 10),
        ],
        if (review) ..._reviewExtras(context, content),
      ],
    );
  }

  List<Widget> _reviewExtras(BuildContext context, OqbQuestionContent? content) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    final verdict = question.isCorrect;
    if (verdict != null) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              verdict ? Icons.check_circle : Icons.cancel,
              color: verdict ? Colors.green.shade700 : theme.colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text(
              controller.isAnswered(question)
                  ? (verdict ? 'Correct' : 'Incorrect')
                  : 'Not answered',
              style: theme.textTheme.titleMedium,
            ),
            if (question.score != null) ...[
              const Spacer(),
              Text('Score ${_fmt(question.score!)}'),
            ],
          ],
        ),
      ));
    }
    for (final (title, html) in [
      ('Model answer', content?.modelAnswer ?? ''),
      ('Feedback', content?.feedback ?? ''),
    ]) {
      if (html.trim().isEmpty) continue;
      widgets.add(Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              OqbHtml(html, textStyle: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
            ],
          ),
        ),
      ));
    }
    return widgets;
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.choice,
    required this.selected,
    required this.correct,
    required this.enabled,
    required this.onTap,
  });

  final OqbChoice choice;
  final bool selected;

  /// Review only: whether this is the suggested (correct) choice.
  final bool? correct;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    var background = scheme.surfaceContainerLow;
    var badge = scheme.surfaceContainerHighest;
    var badgeText = scheme.onSurface;
    Color? border;
    IconData? trailing;
    var semantics = 'Choice ${choice.label}';

    if (selected) {
      background = scheme.primaryContainer;
      badge = scheme.primary;
      badgeText = scheme.onPrimary;
      semantics += ', selected';
    }
    if (correct == true) {
      border = Colors.green.shade600;
      trailing = Icons.check_circle;
      if (!selected) background = Colors.green.withValues(alpha: 0.08);
      semantics += ', correct answer';
    } else if (correct == false && selected) {
      background = scheme.errorContainer;
      badge = scheme.error;
      badgeText = scheme.onError;
      trailing = Icons.cancel;
    }

    return Semantics(
      button: enabled,
      selected: selected,
      label: semantics,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: border ?? (selected ? scheme.primary : scheme.outlineVariant),
            width: border != null || selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: badge),
                  alignment: Alignment.center,
                  child: Text(choice.label, style: theme.textTheme.titleMedium?.copyWith(color: badgeText)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OqbHtml(
                          choice.html,
                          textStyle: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
                        ),
                        if (choice.imageUrl.isNotEmpty) ...[
                          if (choice.html.trim().isNotEmpty) const SizedBox(height: 8),
                          OqbImage(url: resolveOqbUrl(choice.imageUrl)),
                        ],
                      ],
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  Icon(trailing, color: correct == true ? Colors.green.shade700 : scheme.error),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controller,
    required this.compact,
    required this.showNavigatorButton,
    required this.onOpenNavigator,
  });

  final StudyController controller;
  final bool compact;
  final bool showNavigatorButton;
  final VoidCallback onOpenNavigator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position = '${controller.questionNumber} / ${controller.total}';

    return Material(
      elevation: 6,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16, vertical: 8),
          child: Row(
            children: [
              compact
                  ? IconButton.outlined(
                      tooltip: 'Previous question',
                      onPressed: controller.hasPrevious ? controller.previous : null,
                      icon: const Icon(Icons.chevron_left),
                    )
                  : OutlinedButton.icon(
                      onPressed: controller.hasPrevious ? controller.previous : null,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Previous'),
                    ),
              Expanded(
                child: Center(
                  child: showNavigatorButton
                      ? TextButton.icon(
                          onPressed: onOpenNavigator,
                          icon: const Icon(Icons.grid_view_rounded),
                          label: Text(position),
                        )
                      : Text(position, style: theme.textTheme.titleSmall),
                ),
              ),
              compact
                  ? IconButton.filled(
                      tooltip: 'Next question',
                      onPressed: controller.hasNext ? controller.next : null,
                      icon: const Icon(Icons.chevron_right),
                    )
                  : FilledButton.icon(
                      onPressed: controller.hasNext ? controller.next : null,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Next'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTrial extends StatelessWidget {
  const _EmptyTrial({required this.onExit, required this.onOpenOriginal});

  final VoidCallback onExit;
  final VoidCallback onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.help_outline, size: 48),
            const SizedBox(height: 12),
            const Text('OQB returned this attempt without any questions.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(onPressed: onExit, child: const Text('Back to papers')),
                FilledButton(onPressed: onOpenOriginal, child: const Text('Open original OQB')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

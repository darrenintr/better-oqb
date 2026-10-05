import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/study_controller.dart';
import '../models/oqb_meta.dart';
import '../models/oqb_review.dart';
import '../models/oqb_trial.dart';
import '../theme/kiln_theme.dart';
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
                style: TextStyle(color: context.kiln.dangerText),
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
          OutlinedButton(
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

              return ColoredBox(
                color: context.kiln.bg,
                child: Column(
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
                ),
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
    final k = context.kiln;
    final text = context.kilnText;
    final session = controller.session!;
    final total = controller.total;
    final title = session.paper.title.isNotEmpty ? session.paper.title : 'Paper ${session.paper.id}';
    final progress = total == 0 ? 0.0 : controller.answeredCount / total;

    final subtitle = review != null
        ? _scoreText(review!)
        : '${controller.answeredCount}/$total answered';

    return Material(
      color: k.bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 4 : 12, 8, compact ? 4 : 16, 8),
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
                        style: text.title.copyWith(
                          fontSize: compact ? 17 : 20,
                          height: compact ? 22 / 17 : 26 / 20,
                          fontWeight: FontWeight.w400,
                          fontVariations: KilnFonts.weight(FontWeight.w400),
                        ),
                      ),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!controller.isReadOnly) _SaveIndicator(controller: controller, compact: compact),
                if (review != null)
                  KilnPill(icon: Icons.fact_check_outlined, label: 'Review', background: k.oat, showLabel: !compact),
                if (controller.isSubmitted && review == null)
                  KilnPill(icon: Icons.check_circle_outline, label: 'Submitted', background: k.oat, showLabel: !compact),
                if (onSubmit != null && !controller.isReadOnly) ...[
                  const SizedBox(width: 8),
                  controller.isSubmitting
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : FilledButton(
                          onPressed: onSubmit,
                          style: compact
                              ? FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14))
                              : null,
                          child: const Text('Submit'),
                        ),
                ],
                PopupMenuButton<VoidCallback>(
                  tooltip: 'More',
                  onSelected: (action) => action(),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: onOpenOriginal,
                      child: const ListTile(
                        leading: Icon(Icons.open_in_new),
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
          // Doubles as the header's bottom hairline.
          Semantics(
            label: 'Progress',
            value: '${controller.answeredCount} of $total answered',
            child: LinearProgressIndicator(value: progress, minHeight: 2),
          ),
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
    final k = context.kiln;
    final (IconData icon, String label, Color color) = switch (controller.saveState) {
      OqbSaveState.saved => (
          Icons.cloud_done_outlined,
          controller.lastSavedAt == null ? 'Synced' : 'Saved',
          k.successText,
        ),
      OqbSaveState.pending => (Icons.cloud_queue, 'Unsaved', k.inkMuted),
      OqbSaveState.saving => (Icons.cloud_upload_outlined, 'Saving…', k.inkMuted),
      OqbSaveState.failed => (Icons.cloud_off_outlined, 'Not saved', k.dangerText),
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
        child: KilnPill(icon: icon, label: label, color: color, showLabel: !compact),
      ),
    );
  }
}

class _SaveFailedBanner extends StatelessWidget {
  const _SaveFailedBanner({required this.controller});

  final StudyController controller;

  @override
  Widget build(BuildContext context) {
    return KilnBanner(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      danger: true,
      icon: Icons.cloud_off_outlined,
      title: '${controller.unsavedCount} answer(s) not saved yet',
      message: 'They are kept here until OQB accepts them. (${controller.saveError})',
      action: OutlinedButton(
        onPressed: controller.retryNow,
        child: const Text('Retry'),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return KilnBanner(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      danger: true,
      icon: Icons.error_outline,
      title: text,
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
    final k = context.kiln;
    final text = context.kilnText;
    final session = controller.session!;
    return ColoredBox(
      color: k.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (review != null) ...[
              _ReviewSummary(review: review!, meta: meta),
              const SizedBox(height: 16),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text('Questions', style: text.label)),
                  Text('${controller.answeredCount} of ${controller.total} answered', style: text.caption),
                ],
              ),
              if (session.paper.subjectCode.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(meta.label(session.paper.subjectCode), style: text.caption),
              ],
              const SizedBox(height: 16),
            ],
            Expanded(child: QuestionNavigator(controller: controller)),
          ],
        ),
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
    final k = context.kiln;
    final text = context.kilnText;
    final score = review.score;
    final full = review.scoreFull;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('RESULT', style: text.eyebrow.copyWith(color: k.clayText)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
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
              const SizedBox(height: 18),
              Text('By topic', style: text.label),
              const SizedBox(height: 8),
              for (final row in review.byTopic)
                _BreakdownBar(label: meta.label(row.key), row: row, color: k.olive),
            ],
            if (review.hasCorrectness && review.byDifficulty.length > 1) ...[
              const SizedBox(height: 10),
              Text('By difficulty', style: text.label),
              const SizedBox(height: 8),
              for (final row in review.byDifficulty)
                _BreakdownBar(label: meta.difficulty(int.tryParse(row.key) ?? 0), row: row, color: k.sky),
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
    final k = context.kiln;
    final text = context.kilnText;
    return Container(
      constraints: const BoxConstraints(minWidth: 116),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: k.bg,
        border: Border.all(color: k.hairline),
        borderRadius: BorderRadius.circular(KilnRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: text.caption),
          Text(
            value,
            style: text.title.copyWith(
              fontSize: 24,
              height: 30 / 24,
              fontWeight: FontWeight.w400,
              fontVariations: KilnFonts.weight(FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownBar extends StatelessWidget {
  const _BreakdownBar({required this.label, required this.row, required this.color});

  final String label;
  final OqbBreakdownRow row;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = context.kilnText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.caption.copyWith(color: context.kiln.ink)),
              ),
              Text('${row.correct}/${row.total}', style: text.caption),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: row.ratio,
            minHeight: 8,
            color: color,
            borderRadius: BorderRadius.circular(999),
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
    final padding = compact ? 16.0 : 32.0;
    final stem = _QuestionStem(
      controller: controller,
      question: question,
      meta: meta,
      compact: compact,
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
    required this.compact,
    required this.onOpenOriginal,
  });

  final StudyController controller;
  final OqbTrialQuestion question;
  final OqbMeta meta;
  final bool compact;
  final VoidCallback onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    final k = context.kiln;
    final text = context.kilnText;
    final content = question.question;
    final year = content != null && content.year.isNotEmpty
        ? (content.questionNo.isNotEmpty ? '${content.year} Q${content.questionNo}' : content.year)
        : null;

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
              style: text.label.copyWith(color: k.clayText),
            ),
            if (year != null) KilnTag(year),
            if (content != null)
              for (final topic in content.topicCodes.take(2)) KilnTag(meta.label(topic), outlined: true),
            if (content != null && content.difficultyCode > 0) KilnTag(meta.difficulty(content.difficultyCode)),
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
            content.displayContent,
            textStyle: text.prose.copyWith(
              fontSize: compact ? 19 : 21,
              height: compact ? 30 / 19 : 33 / 21,
            ),
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
          if (content.displayContent.trim().isEmpty && content.url.isEmpty)
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
    return KilnBanner(
      icon: Icons.info_outline,
      title: text,
      action: TextButton(onPressed: onOpenOriginal, child: const Text('Original OQB')),
    );
  }
}

class _AnswerSection extends StatelessWidget {
  const _AnswerSection({required this.controller, required this.question});

  final StudyController controller;
  final OqbTrialQuestion question;

  @override
  Widget build(BuildContext context) {
    final k = context.kiln;
    final text = context.kilnText;
    final content = question.question;
    final answer = controller.answerFor(question);
    final review = controller.isReadOnly;
    final shown = !review && controller.isAnswerShown(question);
    final key = review ? content?.suggestedAnswer : (shown ? controller.answerKeyFor(question) : null);

    if (content == null || !content.isMultipleChoice) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: k.surface,
          border: Border.all(color: k.hairline),
          borderRadius: BorderRadius.circular(KilnRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Answer', style: text.label),
            const SizedBox(height: 8),
            Text(
              answer.isNotEmpty
                  ? 'Your answer: ${answer.raw ?? answer.serialize()}'
                  : 'This question type is answered in the original OQB page.',
              style: text.body,
            ),
            if (review) ..._reviewExtras(context, content),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Answer', style: text.label),
        const SizedBox(height: 12),
        for (final choice in content.choices) ...[
          _AnswerCard(
            choice: choice,
            selected: answer.choices.contains(choice.index),
            correct: key?.choices.contains(choice.index),
            enabled: !review && !controller.isSubmitting && !controller.isChecked(question),
            onTap: () => controller.selectChoice(choice.index),
          ),
          const SizedBox(height: 10),
        ],
        if (shown)
          _verdict(
            context,
            answer.isEmpty ? 'Not answered' : (answer.sameAs(key!) ? 'Correct' : 'Incorrect'),
            answer.isNotEmpty && answer.sameAs(key!),
          ),
        if (controller.canShowAnswer(question)) _showAnswerButton(context),
        if (review) ..._reviewExtras(context, content),
      ],
    );
  }

  Widget _verdict(BuildContext context, String label, bool correct, {num? score}) {
    final k = context.kiln;
    final text = context.kilnText;
    final color = correct ? k.successText : k.dangerText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(correct ? Icons.check_circle : Icons.cancel, color: color, size: 22),
          const SizedBox(width: 8),
          Text(label, style: text.label.copyWith(fontSize: 17, color: color)),
          if (score != null) ...[
            const Spacer(),
            Text('Score ${_fmt(score)}', style: text.caption),
          ],
        ],
      ),
    );
  }

  Widget _showAnswerButton(BuildContext context) {
    final checking = controller.isChecked(question);
    final failed = checking && controller.saveStateFor(question) == OqbSaveState.failed;
    final busy = checking && !failed && controller.saveStateFor(question) != OqbSaveState.saved;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : controller.showAnswer,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.visibility_outlined),
              label: Text(busy ? 'Checking…' : 'Show answer'),
            ),
            // Checked and saved, but OQB sent no answer key for it.
            if (checking && !busy && !failed)
              Text(
                'OQB has not sent this answer yet.',
                style: context.kilnText.caption,
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _reviewExtras(BuildContext context, OqbQuestionContent? content) {
    final k = context.kiln;
    final text = context.kilnText;
    final widgets = <Widget>[];
    final verdict = question.isCorrect;
    if (verdict != null) {
      widgets.add(_verdict(
        context,
        controller.isAnswered(question) ? (verdict ? 'Correct' : 'Incorrect') : 'Not answered',
        verdict,
        score: question.score,
      ));
    }
    for (final (title, html) in [
      ('Model answer', content?.modelAnswer ?? ''),
      ('Feedback', content?.feedback ?? ''),
    ]) {
      if (html.trim().isEmpty) continue;
      widgets.add(Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: k.surface,
          borderRadius: BorderRadius.circular(KilnRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: text.label),
            const SizedBox(height: 8),
            OqbHtml(html, textStyle: text.prose),
          ],
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
    final k = context.kiln;
    final text = context.kilnText;

    var background = k.surfaceRaised;
    var badge = k.surface;
    var badgeText = k.ink;
    var border = BorderSide(color: k.borderControl);
    // Correctness is always an icon and a word, not colour alone.
    (IconData, String, Color)? verdict;
    var semantics = 'Choice ${choice.label}';

    if (selected) {
      background = k.oat;
      badge = k.ink;
      badgeText = k.onInk;
      border = BorderSide(color: k.ink, width: 2);
      semantics += ', selected';
    }
    if (correct == true) {
      background = k.surfaceRaised;
      badge = k.successText;
      badgeText = k.bg;
      border = BorderSide(color: k.successText, width: 2);
      verdict = (Icons.check_circle, selected ? 'Your answer' : 'Answer', k.successText);
      semantics += ', correct answer';
    } else if (correct == false && selected) {
      background = k.surfaceRaised;
      badge = k.dangerText;
      badgeText = k.bg;
      border = BorderSide(color: k.dangerText, width: 2);
      verdict = (Icons.cancel, 'Your answer', k.dangerText);
    }

    return Semantics(
      button: enabled,
      selected: selected,
      label: semantics,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KilnRadius.md),
          side: border,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: badge,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      choice.label,
                      style: text.label.copyWith(
                        color: badgeText,
                        fontWeight: FontWeight.w600,
                        fontVariations: KilnFonts.weight(FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OqbHtml(
                            choice.displayHtml,
                            textStyle: text.prose.copyWith(height: 26 / 18),
                          ),
                          if (choice.imageUrl.isNotEmpty) ...[
                            if (choice.displayHtml.trim().isNotEmpty) const SizedBox(height: 8),
                            OqbImage(url: resolveOqbUrl(choice.imageUrl)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (verdict != null) ...[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(verdict.$1, size: 18, color: verdict.$3),
                          const SizedBox(width: 4),
                          Text(verdict.$2, style: text.label.copyWith(fontSize: 13, color: verdict.$3)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
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
    final k = context.kiln;
    final text = context.kilnText;
    final position = '${controller.questionNumber} / ${controller.total}';
    final accent = kilnAccentButtonStyle(k);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: k.bg,
        border: Border(top: BorderSide(color: k.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24, vertical: 10),
          child: Row(
            children: [
              compact
                  ? IconButton.outlined(
                      tooltip: 'Previous question',
                      onPressed: controller.hasPrevious ? controller.previous : null,
                      style: IconButton.styleFrom(side: BorderSide(color: k.borderControl)),
                      icon: const Icon(Icons.chevron_left),
                    )
                  : OutlinedButton.icon(
                      onPressed: controller.hasPrevious ? controller.previous : null,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Previous'),
                    ),
              const SizedBox(width: 8),
              Expanded(
                child: Center(
                  child: showNavigatorButton
                      ? TextButton.icon(
                          onPressed: onOpenNavigator,
                          style: TextButton.styleFrom(
                            backgroundColor: k.surface,
                            foregroundColor: k.ink,
                            minimumSize: const Size(120, 44),
                          ),
                          icon: const Icon(Icons.grid_view_rounded, size: 18),
                          label: Text(position),
                        )
                      : Text(position, style: text.body.copyWith(color: k.inkMuted)),
                ),
              ),
              const SizedBox(width: 8),
              compact
                  ? IconButton.filled(
                      tooltip: 'Next question',
                      onPressed: controller.hasNext ? controller.next : null,
                      style: accent,
                      icon: const Icon(Icons.chevron_right),
                    )
                  : FilledButton.icon(
                      onPressed: controller.hasNext ? controller.next : null,
                      style: accent,
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
    final text = context.kilnText;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline, size: 40, color: context.kiln.inkMuted),
            const SizedBox(height: 12),
            Text(
              'OQB returned this attempt without any questions.',
              textAlign: TextAlign.center,
              style: text.title.copyWith(fontSize: 20, height: 28 / 20),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
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

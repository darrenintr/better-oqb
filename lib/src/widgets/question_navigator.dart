import 'package:flutter/material.dart';

import '../controllers/study_controller.dart';
import '../models/oqb_trial.dart';
import '../theme/kiln_theme.dart';

enum _NavigatorFilter { all, unanswered, answered, flagged }

/// Grid of question numbers for jumping around a trial. Handles very large
/// papers (500+ questions) with a lazily built grid.
class QuestionNavigator extends StatefulWidget {
  const QuestionNavigator({
    super.key,
    required this.controller,
    this.onSelected,
    this.shrinkWrap = false,
  });

  final StudyController controller;
  final ValueChanged<int>? onSelected;
  final bool shrinkWrap;

  @override
  State<QuestionNavigator> createState() => _QuestionNavigatorState();
}

class _QuestionNavigatorState extends State<QuestionNavigator> {
  static const double _tile = 46;
  static const double _gap = 8;

  _NavigatorFilter _filter = _NavigatorFilter.all;
  final ScrollController _scroll = ScrollController();
  int _lastScrolledIndex = -1;
  double _width = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _matches(OqbTrialQuestion question) {
    final controller = widget.controller;
    switch (_filter) {
      case _NavigatorFilter.all:
        return true;
      case _NavigatorFilter.unanswered:
        return !controller.isAnswered(question);
      case _NavigatorFilter.answered:
        return controller.isAnswered(question);
      case _NavigatorFilter.flagged:
        if (controller.isReadOnly) return question.isCorrect == false;
        final state = controller.saveStateFor(question);
        return state == OqbSaveState.failed || state == OqbSaveState.pending;
    }
  }

  void _ensureCurrentVisible(List<int> indexes) {
    final current = widget.controller.index;
    if (current == _lastScrolledIndex || _width <= 0) return;
    _lastScrolledIndex = current;
    final position = indexes.indexOf(current);
    if (position < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final perRow = ((_width + _gap) / (_tile + _gap)).floor().clamp(1, 1000);
      final row = position ~/ perRow;
      final target = (row * (_tile + _gap) - _tile * 2)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      final viewport = _scroll.position.viewportDimension;
      final offset = _scroll.offset;
      final rowTop = row * (_tile + _gap);
      if (rowTop < offset || rowTop + _tile > offset + viewport) {
        _scroll.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final session = controller.session;
    if (session == null) return const SizedBox.shrink();
    final questions = session.questions;
    final indexes = [
      for (var i = 0; i < questions.length; i++)
        if (_matches(questions[i])) i,
    ];

    final filterLabels = {
      _NavigatorFilter.all: 'All',
      _NavigatorFilter.unanswered: 'To do',
      _NavigatorFilter.answered: 'Done',
      _NavigatorFilter.flagged: controller.isReadOnly ? 'Wrong' : 'Pending',
    };

    final grid = LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        _ensureCurrentVisible(indexes);
        if (indexes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No questions in this filter.', style: theme.textTheme.bodySmall),
          );
        }
        return GridView.builder(
          controller: widget.shrinkWrap ? null : _scroll,
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.only(bottom: 12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _tile,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
          ),
          itemCount: indexes.length,
          itemBuilder: (context, position) {
            final index = indexes[position];
            return _QuestionTile(
              number: index + 1,
              question: questions[index],
              controller: controller,
              isCurrent: index == controller.index,
              onTap: () {
                controller.goTo(index);
                widget.onSelected?.call(index);
              },
            );
          },
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        _FilterControl(
          labels: filterLabels,
          selected: _filter,
          onSelected: (filter) => setState(() {
            _filter = filter;
            _lastScrolledIndex = -1;
          }),
        ),
        const SizedBox(height: 16),
        if (widget.shrinkWrap) grid else Expanded(child: grid),
      ],
    );
  }
}

/// Segmented filter: All / To do / Done / Pending (Wrong in review).
class _FilterControl extends StatelessWidget {
  const _FilterControl({required this.labels, required this.selected, required this.onSelected});

  final Map<_NavigatorFilter, String> labels;
  final _NavigatorFilter selected;
  final ValueChanged<_NavigatorFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final k = context.kiln;
    final style = context.kilnText.label.copyWith(fontSize: 13, height: 18 / 13);
    return Semantics(
      container: true,
      label: 'Filter questions',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: k.oat, borderRadius: BorderRadius.circular(KilnRadius.md)),
        child: Row(
          children: [
            for (final entry in labels.entries)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: entry.key == selected,
                  child: Material(
                    color: entry.key == selected ? k.surfaceRaised : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onSelected(entry.key),
                      child: SizedBox(
                        height: 36,
                        child: Center(
                          child: Text(
                            entry.value,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: style.copyWith(color: entry.key == selected ? k.ink : k.inkMuted),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({
    required this.number,
    required this.question,
    required this.controller,
    required this.isCurrent,
    required this.onTap,
  });

  final int number;
  final OqbTrialQuestion question;
  final StudyController controller;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.kiln;
    final answered = controller.isAnswered(question);
    final saveState = controller.isReadOnly ? OqbSaveState.saved : controller.saveStateFor(question);

    var background = k.surfaceRaised;
    var foreground = k.ink;
    BorderSide border = BorderSide(color: k.borderControl);
    IconData? mark;
    var pendingDot = false;
    var semantics = 'Question $number';

    if (controller.isReadOnly && question.isCorrect != null) {
      final correct = question.isCorrect!;
      background = correct ? k.successText : k.dangerText;
      foreground = k.bg;
      border = BorderSide.none;
      mark = correct ? Icons.check_rounded : Icons.close_rounded;
      semantics += correct ? ', correct' : ', incorrect';
    } else if (answered) {
      background = k.oat;
      border = BorderSide.none;
      semantics += ', answered';
    }
    if (saveState == OqbSaveState.failed) {
      background = k.surfaceRaised;
      foreground = k.dangerText;
      border = BorderSide(color: k.dangerText, width: 1.5);
      semantics += ', not saved';
    } else if (saveState == OqbSaveState.pending || saveState == OqbSaveState.saving) {
      pendingDot = true;
      semantics += saveState == OqbSaveState.saving ? ', saving' : ', unsaved';
    }
    if (isCurrent) {
      background = k.ink;
      foreground = k.onInk;
      border = BorderSide.none;
      semantics += ', current';
    }

    final label = Text(
      '$number',
      style: context.kilnText.label.copyWith(
        fontSize: 13,
        height: 1.1,
        color: foreground,
        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
        fontVariations: KilnFonts.weight(isCurrent ? FontWeight.w600 : FontWeight.w500),
      ),
    );

    return Semantics(
      button: true,
      selected: isCurrent,
      label: semantics,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Material(
              color: background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KilnRadius.sm),
                side: border,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Center(
                  child: FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: mark == null
                          ? label
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [label, Icon(mark, size: 12, color: foreground)],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (pendingDot)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: k.sky,
                  shape: BoxShape.circle,
                  border: Border.all(color: k.surface, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

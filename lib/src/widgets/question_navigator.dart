import 'package:flutter/material.dart';

import '../controllers/study_controller.dart';
import '../models/oqb_trial.dart';

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
  static const double _gap = 6;

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
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in filterLabels.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _filter == entry.key,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() {
                  _filter = entry.key;
                  _lastScrolledIndex = -1;
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.shrinkWrap) grid else Expanded(child: grid),
      ],
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
    final scheme = Theme.of(context).colorScheme;
    final answered = controller.isAnswered(question);
    final saveState = controller.isReadOnly ? OqbSaveState.saved : controller.saveStateFor(question);

    Color background = scheme.surfaceContainerHighest;
    Color foreground = scheme.onSurface;
    Color? border;
    var semantics = 'Question $number';

    if (controller.isReadOnly && question.isCorrect != null) {
      background = question.isCorrect! ? Colors.green.shade100 : scheme.errorContainer;
      foreground = question.isCorrect! ? Colors.green.shade900 : scheme.onErrorContainer;
      semantics += question.isCorrect! ? ', correct' : ', incorrect';
    } else if (answered) {
      background = scheme.secondaryContainer;
      foreground = scheme.onSecondaryContainer;
      semantics += ', answered';
    }
    if (saveState == OqbSaveState.failed) {
      border = scheme.error;
      semantics += ', not saved';
    } else if (saveState == OqbSaveState.pending || saveState == OqbSaveState.saving) {
      border = scheme.tertiary;
    }
    if (isCurrent) {
      background = scheme.primary;
      foreground = scheme.onPrimary;
      semantics += ', current';
    }

    return Semantics(
      button: true,
      selected: isCurrent,
      label: semantics,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: border == null ? BorderSide.none : BorderSide(color: border, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Text(
                  '$number',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

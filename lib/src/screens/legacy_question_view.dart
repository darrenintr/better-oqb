import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../models/oqb_page_state.dart';
import '../widgets/oqb_browser.dart';

// Compatibility fallback only.
//
// This view renders a question scraped from the visible OQB page
// (assets/oqb_bridge.js) and drives OQB by clicking its own controls. The
// primary study experience is the API-backed StudyView; this is shown only
// when the API path cannot load the paper OQB is currently displaying.

class LegacyQuestionView extends StatelessWidget {
  const LegacyQuestionView({
    super.key,
    required this.state,
    required this.controller,
    required this.onOpenOriginal,
    this.apiError,
    this.onRetryApi,
  });

  final OqbPageState state;
  final OqbBrowserController controller;
  final VoidCallback onOpenOriginal;
  final Object? apiError;
  final VoidCallback? onRetryApi;

  Future<void> _confirmSubmit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit this paper?'),
        content: const Text(
          'This presses Submit on the original OQB page. After submitting you '
          'cannot change your answers.',
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
    if (confirmed == true) await controller.submit();
  }

  @override
  Widget build(BuildContext context) {
    final question = state.question!;
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width >= 900 ? 40.0 : 16.0;

    return Column(
      children: [
        MaterialBanner(
          leading: const Icon(Icons.warning_amber_rounded),
          content: Text(
            apiError == null
                ? 'Compatibility mode: this question was read from the OQB page.'
                : 'Compatibility mode: the OQB API could not load this paper '
                    '($apiError). Showing the question read from the OQB page.',
          ),
          actions: [
            if (onRetryApi != null)
              TextButton(onPressed: onRetryApi, child: const Text('Retry API')),
            TextButton(onPressed: onOpenOriginal, child: const Text('Original page')),
          ],
        ),
        Material(
          color: theme.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              12,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous question',
                  onPressed: question.current > 1 ? controller.previous : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        question.total > 0
                            ? 'Question ${question.current} of ${question.total}'
                            : 'Question ${question.current}',
                        style: theme.textTheme.titleMedium,
                      ),
                      if (question.total > 0) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: question.current / question.total,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Next question',
                  onPressed: question.total == 0 ||
                          question.current < question.total
                      ? controller.next
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SelectionArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                120,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          elevation: 0,
                          color: theme.colorScheme.surfaceContainerLowest,
                          child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: HtmlWidget(
                              question.html,
                              textStyle: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        for (final option in question.options) ...[
                          _AnswerCard(
                            option: option,
                            onTap: () => controller.answer(option.key),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Material(
            elevation: 8,
            color: theme.colorScheme.surface,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                10,
                horizontalPadding,
                10,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: controller.previous,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Previous'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: controller.next,
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Next'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: onOpenOriginal,
                        child: const Text('Original page'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () => _confirmSubmit(context),
                        icon: const Icon(Icons.check),
                        label: const Text('Submit'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.option,
    required this.onTap,
  });

  final OqbOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: option.selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: option.selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                ),
                alignment: Alignment.center,
                child: Text(
                  option.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: option.selected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: HtmlWidget(
                  option.html,
                  textStyle: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

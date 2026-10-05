import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../models/oqb_page_state.dart';
import '../services/oqb_bridge.dart';
import '../widgets/oqb_browser.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final OqbBrowserController _browserController = OqbBrowserController();

  OqbPageState _page = const OqbPageState();
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final browser = OqbBrowser(
      controller: _browserController,
      bridge: OqbBridge(
        onPageState: (state) {
          if (!mounted) return;
          setState(() {
            _page = state;
            if (state.hasQuestion) {
              _showOriginal = false;
            }
          });
        },
      ),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('Better OQB'),
        actions: [
          if (_page.question case final question?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  question.total > 0
                      ? '${question.current}/${question.total}'
                      : 'Q${question.current}',
                ),
              ),
            ),
          IconButton(
            tooltip: _showOriginal ? 'Use Better OQB view' : 'Open original OQB',
            onPressed: () => setState(() => _showOriginal = !_showOriginal),
            icon: Icon(
              _showOriginal ? Icons.auto_awesome_mosaic : Icons.open_in_browser,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_showOriginal,
              child: browser,
            ),
          ),
          if (!_showOriginal)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: _page.hasQuestion
                    ? _QuestionView(
                        state: _page,
                        controller: _browserController,
                        onOpenOriginal: () =>
                            setState(() => _showOriginal = true),
                      )
                    : _ConnectView(
                        state: _page,
                        onOpenOriginal: () =>
                            setState(() => _showOriginal = true),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConnectView extends StatelessWidget {
  const _ConnectView({
    required this.state,
    required this.onOpenOriginal,
  });

  final OqbPageState state;
  final VoidCallback onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    state.isLoggedIn == true
                        ? Icons.school_outlined
                        : Icons.language,
                    size: 52,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    state.isLoggedIn == true
                        ? 'Choose a paper in OQB'
                        : 'Connect to OQB',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    state.isLoggedIn == true
                        ? 'The real OQB browser is running behind this interface. Open it only to choose a subject or paper. When a question opens, Better OQB will switch back to the redesigned view automatically.'
                        : 'Sign in through the real OQB page. Your login remains inside the embedded browser; Better OQB only reads the page state needed to render the study interface.',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onOpenOriginal,
                    icon: const Icon(Icons.open_in_browser),
                    label: Text(
                      state.isLoggedIn == true
                          ? 'Open OQB to choose a paper'
                          : 'Open OQB sign in',
                    ),
                  ),
                  if (state.url.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      state.url,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
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

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.state,
    required this.controller,
    required this.onOpenOriginal,
  });

  final OqbPageState state;
  final OqbBrowserController controller;
  final VoidCallback onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    final question = state.question!;
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width >= 900 ? 40.0 : 16.0;

    return Column(
      children: [
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
                        onPressed: controller.submit,
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

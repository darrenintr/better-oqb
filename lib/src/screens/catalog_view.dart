import 'package:flutter/material.dart';

import '../controllers/catalog_controller.dart';
import '../models/oqb_api_data.dart';
import '../models/oqb_meta.dart';

/// Better OQB home: resumable papers, subjects, banks, topic/difficulty
/// availability and submitted attempts — all from the authenticated API.
class CatalogView extends StatefulWidget {
  const CatalogView({
    super.key,
    required this.controller,
    required this.onStartPaper,
    required this.onReviewPaper,
    required this.onOpenOriginal,
    required this.onCreatePaper,
  });

  final CatalogController controller;
  final ValueChanged<OqbPaperSummary> onStartPaper;
  final ValueChanged<OqbPaperSummary> onReviewPaper;
  final VoidCallback onOpenOriginal;

  /// Paper composition (save_paper) stays in the original OQB UI for now.
  final VoidCallback onCreatePaper;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  String? _subject;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final subjects = controller.data.subjects;
        final selected = _subject != null && subjects.contains(_subject) ? _subject : null;

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final overview = _Overview(
              controller: controller,
              selectedSubject: wide ? (selected ?? (subjects.isEmpty ? null : subjects.first)) : selected,
              onSelectSubject: (subject) => setState(() => _subject = subject),
              onStartPaper: widget.onStartPaper,
              onCreatePaper: widget.onCreatePaper,
              compact: !wide,
            );

            if (wide) {
              final subject = selected ?? (subjects.isEmpty ? null : subjects.first);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: constraints.maxWidth >= 1300 ? 440 : 380, child: overview),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: subject == null
                        ? const Center(child: Text('No question banks are available to this account.'))
                        : _SubjectDetail(
                            key: ValueKey(subject),
                            controller: controller,
                            subject: subject,
                            onStartPaper: widget.onStartPaper,
                            onReviewPaper: widget.onReviewPaper,
                            onOpenOriginal: widget.onOpenOriginal,
                          ),
                  ),
                ],
              );
            }

            if (selected != null) {
              return PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) setState(() => _subject = null);
                },
                child: _SubjectDetail(
                  key: ValueKey(selected),
                  controller: controller,
                  subject: selected,
                  onBack: () => setState(() => _subject = null),
                  onStartPaper: widget.onStartPaper,
                  onReviewPaper: widget.onReviewPaper,
                  onOpenOriginal: widget.onOpenOriginal,
                ),
              );
            }
            return overview;
          },
        );
      },
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.controller,
    required this.selectedSubject,
    required this.onSelectSubject,
    required this.onStartPaper,
    required this.onCreatePaper,
    required this.compact,
  });

  final CatalogController controller;
  final String? selectedSubject;
  final ValueChanged<String> onSelectSubject;
  final ValueChanged<OqbPaperSummary> onStartPaper;
  final VoidCallback onCreatePaper;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = controller.data;
    final meta = controller.meta;
    final papers = data.availablePapers;

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Row(
            children: [
              Expanded(child: Text('Study', style: theme.textTheme.headlineSmall)),
              if (controller.isLoading)
                const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: controller.refresh,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          if (controller.error != null) ...[
            const SizedBox(height: 8),
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Some OQB data could not be loaded'),
                subtitle: Text('${controller.error}'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _SectionTitle(
            title: 'Continue',
            trailing: TextButton.icon(
              onPressed: onCreatePaper,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New paper'),
            ),
          ),
          if (papers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                controller.hasLoaded
                    ? 'No papers waiting. Create one or pick a preset paper from a subject.'
                    : 'Loading papers…',
                style: theme.textTheme.bodyMedium,
              ),
            )
          else
            for (final paper in papers)
              _PaperCard(
                paper: paper,
                subtitle: [
                  if (paper.subjectCode.isNotEmpty) meta.label(paper.subjectCode),
                  if (paper.numQuestions > 0) '${paper.numQuestions} questions',
                  if (paper.isTeacher) 'From teacher',
                ].join(' · '),
                actionLabel: 'Start / resume',
                icon: Icons.play_arrow_rounded,
                onAction: () => onStartPaper(paper),
              ),
          const SizedBox(height: 24),
          const _SectionTitle(title: 'Subjects'),
          for (final subject in data.subjects)
            _SubjectTile(
              subject: subject,
              meta: meta,
              packages: data.packagesFor(subject),
              submitted: data.submittedPapersBySubject[subject] ?? const [],
              selected: !compact && subject == selectedSubject,
              onTap: () => onSelectSubject(subject),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _PaperCard extends StatelessWidget {
  const _PaperCard({
    required this.paper,
    required this.subtitle,
    required this.actionLabel,
    required this.icon,
    required this.onAction,
    this.trailingText,
  });

  final OqbPaperSummary paper;
  final String subtitle;
  final String actionLabel;
  final IconData icon;
  final VoidCallback? onAction;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAction,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paper.title.isEmpty ? 'Paper ${paper.id}' : paper.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              if (trailingText != null) ...[
                const SizedBox(width: 8),
                Text(trailingText!, style: theme.textTheme.titleMedium),
              ],
              const SizedBox(width: 4),
              IconButton(
                tooltip: actionLabel,
                onPressed: onAction,
                icon: Icon(icon),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectTile extends StatelessWidget {
  const _SubjectTile({
    required this.subject,
    required this.meta,
    required this.packages,
    required this.submitted,
    required this.selected,
    required this.onTap,
  });

  final String subject;
  final OqbMeta meta;
  final List<OqbPackageSummary> packages;
  final List<OqbPaperSummary> submitted;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final questions = packages.fold<int>(0, (sum, item) => sum + item.questionCount);
    final label = meta.label(subject);
    final publishers = packages.map((item) => meta.label(item.publisherCode)).where((p) => p.isNotEmpty).toSet();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? theme.colorScheme.secondaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Text(label.isEmpty ? '?' : label.characters.first.toUpperCase()),
        ),
        title: Text(label == subject ? subject.toUpperCase() : label),
        subtitle: Text(
          [
            '${packages.length} bank${packages.length == 1 ? '' : 's'}',
            if (questions > 0) '$questions questions',
            if (submitted.isNotEmpty) '${submitted.length} submitted',
            if (publishers.isNotEmpty) publishers.take(3).join(', '),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _SubjectDetail extends StatelessWidget {
  const _SubjectDetail({
    super.key,
    required this.controller,
    required this.subject,
    required this.onStartPaper,
    required this.onReviewPaper,
    required this.onOpenOriginal,
    this.onBack,
  });

  final CatalogController controller;
  final String subject;
  final ValueChanged<OqbPaperSummary> onStartPaper;
  final ValueChanged<OqbPaperSummary> onReviewPaper;
  final VoidCallback onOpenOriginal;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = controller.data;
    final meta = controller.meta;
    final packages = data.packagesFor(subject);
    final submitted = data.submittedPapersBySubject[subject];
    final preset = data.presetPapersBySubject[subject];
    final loading = controller.isSubjectLoading(subject);
    final error = controller.subjectError(subject);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (onBack != null)
                      IconButton(
                        tooltip: 'All subjects',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    Expanded(
                      child: Text(
                        meta.label(subject) == subject ? subject.toUpperCase() : meta.label(subject),
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    if (loading)
                      const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      IconButton(
                        tooltip: 'Refresh subject',
                        onPressed: () => controller.loadSubject(subject),
                        icon: const Icon(Icons.refresh),
                      ),
                  ],
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Could not load papers: $error', style: TextStyle(color: theme.colorScheme.error)),
                  ),
                const SizedBox(height: 20),
                const _SectionTitle(title: 'Submitted attempts'),
                if (submitted == null)
                  Text(loading ? 'Loading…' : 'Not loaded yet.', style: theme.textTheme.bodySmall)
                else if (submitted.isEmpty)
                  Text('No submitted attempts yet.', style: theme.textTheme.bodySmall)
                else
                  for (final paper in submitted)
                    _PaperCard(
                      paper: paper,
                      subtitle: [
                        if (paper.numQuestions > 0) '${paper.numQuestions} questions',
                        if (paper.marked == false) 'Awaiting marking',
                        if (!paper.isReviewable) 'Review not available',
                      ].join(' · '),
                      trailingText: paper.score == null
                          ? null
                          : '${_fmt(paper.score!)}${paper.scoreFull == null ? '' : '/${_fmt(paper.scoreFull!)}'}',
                      actionLabel: 'Review',
                      icon: Icons.fact_check_outlined,
                      onAction: paper.isReviewable ? () => onReviewPaper(paper) : null,
                    ),
                const SizedBox(height: 24),
                _SectionTitle(
                  title: 'Preset papers',
                  trailing: TextButton(onPressed: onOpenOriginal, child: const Text('Open in OQB')),
                ),
                if (preset == null)
                  Text(loading ? 'Loading…' : 'Not loaded yet.', style: theme.textTheme.bodySmall)
                else if (preset.isEmpty)
                  Text('No preset papers for this subject.', style: theme.textTheme.bodySmall)
                else ...[
                  Text(
                    'Preset papers are started from the original OQB page, which creates your copy.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (final paper in preset)
                    _PaperCard(
                      paper: paper,
                      subtitle: [
                        if (paper.numQuestions > 0) '${paper.numQuestions} questions',
                        if (paper.isTeacher) 'Teacher',
                      ].join(' · '),
                      actionLabel: 'Open in original OQB',
                      icon: Icons.open_in_browser,
                      onAction: onOpenOriginal,
                    ),
                ],
                const SizedBox(height: 24),
                const _SectionTitle(title: 'Question banks'),
                for (final package in packages)
                  _PackageCard(package: package, meta: meta),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _fmt(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.package, required this.meta});

  final OqbPackageSummary package;
  final OqbMeta meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topics = package.topicCounts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final difficulties = <int>{
      for (final counts in package.topicDifficultyCounts.values) ...counts.keys,
    }.toList()
      ..sort();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(package.displayTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (package.publisherCode.isNotEmpty) Chip(label: Text(meta.label(package.publisherCode))),
                if (package.questionCount > 0) Chip(label: Text('${package.questionCount} questions')),
                for (final access in package.accessType) Chip(label: Text(access)),
              ],
            ),
            if (topics.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (difficulties.isNotEmpty) _DifficultyLegend(difficulties: difficulties, meta: meta),
              for (final topic in topics)
                _TopicRow(
                  label: meta.label(topic.key),
                  count: topic.value,
                  perDifficulty: package.topicDifficultyCounts[topic.key] ?? const {},
                  difficulties: difficulties,
                ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Topic statistics not provided for this bank.', style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

Color _difficultyColor(BuildContext context, int index, int count) {
  final scheme = Theme.of(context).colorScheme;
  final palette = [scheme.primary, scheme.tertiary, scheme.error, scheme.secondary];
  return palette[index % palette.length].withValues(alpha: 0.85);
}

class _DifficultyLegend extends StatelessWidget {
  const _DifficultyLegend({required this.difficulties, required this.meta});

  final List<int> difficulties;
  final OqbMeta meta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (var i = 0; i < difficulties.length; i++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _difficultyColor(context, i, difficulties.length),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(meta.difficulty(difficulties[i]), style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({
    required this.label,
    required this.count,
    required this.perDifficulty,
    required this.difficulties,
  });

  final String label;
  final int count;
  final Map<int, int> perDifficulty;
  final List<int> difficulties;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = perDifficulty.values.fold<int>(0, (sum, value) => sum + value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(width: 8),
              Text('$count', style: theme.textTheme.labelLarge),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: [
                    for (var i = 0; i < difficulties.length; i++)
                      if ((perDifficulty[difficulties[i]] ?? 0) > 0)
                        Expanded(
                          flex: perDifficulty[difficulties[i]]!,
                          child: Tooltip(
                            message: '${perDifficulty[difficulties[i]]} questions',
                            child: ColoredBox(
                            color: _difficultyColor(context, i, difficulties.length),
                            child: const SizedBox.expand(),
                          ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../controllers/catalog_controller.dart';
import '../models/oqb_api_data.dart';
import '../models/oqb_meta.dart';
import '../theme/kiln_theme.dart';

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
    final k = context.kiln;
    final text = context.kilnText;
    final data = controller.data;
    final meta = controller.meta;
    final papers = data.availablePapers;

    return RefreshIndicator(
      onRefresh: controller.refresh,
      color: k.ink,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          Row(
            children: [
              Expanded(child: Text('Study', style: text.title)),
              if (controller.isLoading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: controller.refresh,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          if (controller.error != null)
            KilnBanner(
              margin: const EdgeInsets.only(top: 12),
              danger: true,
              icon: Icons.error_outline,
              title: 'Some OQB data could not be loaded',
              message: '${controller.error}',
              action: OutlinedButton(onPressed: controller.refresh, child: const Text('Retry')),
            ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Continue',
            trailing: FilledButton.icon(
              onPressed: onCreatePaper,
              style: kilnAccentButtonStyle(k),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New paper'),
            ),
          ),
          if (papers.isEmpty)
            _EmptyNote(
              controller.hasLoaded
                  ? 'No papers waiting. Create one or pick a preset paper from a subject.'
                  : 'Loading papers…',
            )
          else
            _RowGroup(
              children: [
                for (final paper in papers)
                  _PaperRow(
                    paper: paper,
                    subtitle: [
                      if (paper.subjectCode.isNotEmpty) meta.label(paper.subjectCode),
                      if (paper.numQuestions > 0) '${paper.numQuestions} questions',
                      if (paper.isTeacher) 'From teacher',
                    ].join(' · '),
                    actionLabel: 'Start / resume',
                    onAction: () => onStartPaper(paper),
                  ),
              ],
            ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text('SUBJECTS', style: text.eyebrow),
          ),
          for (final subject in data.subjects)
            _SubjectTile(
              subject: subject,
              meta: meta,
              packages: data.packagesFor(subject),
              submitted: data.submittedPapersBySubject[subject] ?? const [],
              selected: !compact && subject == selectedSubject,
              showChevron: compact,
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: context.kilnText.title.copyWith(fontSize: 22, height: 28 / 22)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: context.kilnText.caption),
    );
  }
}

/// List rows separated by hairlines, with a hairline above the first.
class _RowGroup extends StatelessWidget {
  const _RowGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final hairline = BorderSide(color: context.kiln.hairline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: i == 0 ? hairline : BorderSide.none, bottom: hairline),
            ),
            child: children[i],
          ),
      ],
    );
  }
}

class _PaperRow extends StatelessWidget {
  const _PaperRow({
    required this.paper,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.trailingText,
  });

  final OqbPaperSummary paper;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onAction;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final k = context.kiln;
    final text = context.kilnText;
    return Semantics(
      button: onAction != null,
      child: InkWell(
        onTap: onAction,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
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
                        style: text.label,
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle, style: text.caption),
                      ],
                    ],
                  ),
                ),
                if (trailingText != null) ...[
                  const SizedBox(width: 12),
                  Text(trailingText!, style: text.title.copyWith(fontSize: 20, height: 26 / 20)),
                ],
                const SizedBox(width: 12),
                Text(
                  actionLabel,
                  style: text.label.copyWith(color: onAction == null ? k.inkMuted : k.clayText),
                ),
              ],
            ),
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
    required this.showChevron,
    required this.onTap,
  });

  final String subject;
  final OqbMeta meta;
  final List<OqbPackageSummary> packages;
  final List<OqbPaperSummary> submitted;
  final bool selected;
  final bool showChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.kiln;
    final text = context.kilnText;
    final questions = packages.fold<int>(0, (sum, item) => sum + item.questionCount);
    final label = meta.label(subject);
    final publishers = packages.map((item) => meta.label(item.publisherCode)).where((p) => p.isNotEmpty).toSet();

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? k.oat : Colors.transparent,
          borderRadius: BorderRadius.circular(KilnRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(KilnRadius.md),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label == subject ? subject.toUpperCase() : label, style: text.label),
                        const SizedBox(height: 2),
                        Text(
                          [
                            '${packages.length} bank${packages.length == 1 ? '' : 's'}',
                            if (questions > 0) '$questions questions',
                            if (submitted.isNotEmpty) '${submitted.length} submitted',
                            if (publishers.isNotEmpty) publishers.take(3).join(', '),
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.caption,
                        ),
                      ],
                    ),
                  ),
                  if (showChevron) Icon(Icons.chevron_right, color: k.inkMuted),
                ],
              ),
            ),
          ),
        ),
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
    final k = context.kiln;
    final text = context.kilnText;
    final data = controller.data;
    final meta = controller.meta;
    final packages = data.packagesFor(subject);
    final submitted = data.submittedPapersBySubject[subject];
    final preset = data.presetPapersBySubject[subject];
    final loading = controller.isSubjectLoading(subject);
    final error = controller.subjectError(subject);
    final compact = onBack != null;

    return ListView(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 32, compact ? 16 : 40, compact ? 16 : 32, 48),
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
                        style: compact ? text.title : text.headline,
                      ),
                    ),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else
                      IconButton(
                        tooltip: 'Refresh subject',
                        onPressed: () => controller.loadSubject(subject),
                        icon: const Icon(Icons.refresh),
                      ),
                  ],
                ),
                if (error != null)
                  KilnBanner(
                    margin: const EdgeInsets.only(top: 12),
                    danger: true,
                    icon: Icons.error_outline,
                    title: 'Could not load papers',
                    message: '$error',
                    action: OutlinedButton(
                      onPressed: () => controller.loadSubject(subject),
                      child: const Text('Retry'),
                    ),
                  ),
                const SizedBox(height: 32),
                const _SectionTitle(title: 'Submitted attempts'),
                if (submitted == null)
                  _EmptyNote(loading ? 'Loading…' : 'Not loaded yet.')
                else if (submitted.isEmpty)
                  const _EmptyNote('No submitted attempts yet.')
                else
                  _RowGroup(
                    children: [
                      for (final paper in submitted)
                        _PaperRow(
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
                          onAction: paper.isReviewable ? () => onReviewPaper(paper) : null,
                        ),
                    ],
                  ),
                const SizedBox(height: 40),
                _SectionTitle(
                  title: 'Preset papers',
                  trailing: TextButton(onPressed: onOpenOriginal, child: const Text('Open in OQB')),
                ),
                if (preset == null)
                  _EmptyNote(loading ? 'Loading…' : 'Not loaded yet.')
                else if (preset.isEmpty)
                  const _EmptyNote('No preset papers for this subject.')
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Preset papers are started from the original OQB page, which creates your copy.',
                      style: text.caption,
                    ),
                  ),
                  _RowGroup(
                    children: [
                      for (final paper in preset)
                        _PaperRow(
                          paper: paper,
                          subtitle: [
                            if (paper.numQuestions > 0) '${paper.numQuestions} questions',
                            if (paper.isTeacher) 'Teacher',
                          ].join(' · '),
                          actionLabel: 'Open in OQB',
                          onAction: onOpenOriginal,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 40),
                const _SectionTitle(title: 'Question banks'),
                _RowGroup(
                  children: [
                    for (final package in packages) _PackageCard(package: package, meta: meta),
                  ],
                ),
                if (packages.isEmpty)
                  Text('No question banks for this subject.', style: text.caption.copyWith(color: k.inkMuted)),
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
    final text = context.kilnText;
    final topics = package.topicCounts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final difficulties = <int>{
      for (final counts in package.topicDifficultyCounts.values) ...counts.keys,
    }.toList()
      ..sort();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(package.displayTitle, style: text.label.copyWith(fontSize: 17, height: 24 / 17)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (package.publisherCode.isNotEmpty) KilnTag(meta.label(package.publisherCode)),
              if (package.questionCount > 0) KilnTag('${package.questionCount} questions'),
              for (final access in package.accessType) KilnTag(access, outlined: true),
            ],
          ),
          if (topics.isNotEmpty) ...[
            const SizedBox(height: 16),
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
              child: Text('Topic statistics not provided for this bank.', style: text.caption),
            ),
        ],
      ),
    );
  }
}

/// Difficulty levels step from light to dark so they differ in lightness,
/// not only hue, and stay readable in greyscale.
Color _difficultyColor(BuildContext context, int index, int count) {
  final k = context.kiln;
  final t = count <= 1 ? 0.0 : index / (count - 1);
  return Color.lerp(k.sky, k.ink, 0.1 + t * 0.6)!;
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
        spacing: 14,
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
                const SizedBox(width: 6),
                Text(meta.difficulty(difficulties[i]), style: context.kilnText.caption),
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
    final k = context.kiln;
    final text = context.kilnText;
    final total = perDifficulty.values.fold<int>(0, (sum, value) => sum + value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.body),
              ),
              const SizedBox(width: 8),
              Text('$count', style: text.caption),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 6,
                child: ColoredBox(
                  color: k.hairline,
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
            ),
          ],
        ],
      ),
    );
  }
}

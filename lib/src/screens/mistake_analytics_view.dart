import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/mistake_history.dart';
import '../models/oqb_meta.dart';

class MistakeAnalyticsView extends StatefulWidget {
  const MistakeAnalyticsView({
    super.key,
    required this.history,
    required this.meta,
    this.onRetry,
  });
  final MistakeHistory history;
  final OqbMeta meta;
  final bool Function(int paper, int question)? onRetry;
  @override
  State<MistakeAnalyticsView> createState() => _MistakeAnalyticsState();
}

class _MistakeAnalyticsState extends State<MistakeAnalyticsView> {
  @override
  void initState() {
    super.initState();
    widget.history.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Practice insights')),
        body: ListenableBuilder(
          listenable: widget.history,
          builder: (context, _) {
            final h = widget.history;
            final all = h.attempts;
            final recent = all.reversed.take(20).toList();
            final previous = all.reversed.skip(20).take(20).toList();
            String accuracy(List<StudyAttempt> a) => a.isEmpty
                ? 'No results'
                : '${(a.where((e) => e.correct).length / a.length * 100).round()}% (${a.length} attempts)';
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (h.error != null)
                  ListTile(
                    title: const Text('History could not be saved or loaded'),
                    trailing: TextButton(
                      onPressed: h.persist,
                      child: const Text('Retry'),
                    ),
                  ),
                if (all.isEmpty)
                  const Text(
                    'Check an answer or review a paper to start your history.',
                  ),
                Text('Accuracy: ${accuracy(all)}'),
                const SizedBox(height: 8),
                Text('Recent 20: ${accuracy(recent)}'),
                Text('Previous 20: ${accuracy(previous)}'),
                const SizedBox(height: 20),
                Text(
                  'Topics to practise',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final row in h.topics)
                  ListTile(
                    title: Text(
                      '${widget.meta.label(row.subject)} · ${widget.meta.label(row.topic)}',
                    ),
                    subtitle: LinearProgressIndicator(value: row.accuracy),
                    trailing: Text('${row.correct}/${row.total}'),
                  ),
                OutlinedButton.icon(
                  onPressed: h.topics.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: h.weaknessPrompt),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Revision prompt copied. Paste it into your AI chat.',
                                ),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Copy AI revision prompt'),
                ),
                const SizedBox(height: 20),
                Text(
                  'Questions to retry',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final a in h.retryQueue)
                  ListTile(
                    title: Text(
                      '${widget.meta.label(a.subject)} · Question ${a.question}',
                    ),
                    subtitle: Text(
                      'Paper ${a.paper} · ${a.timestamp.toLocal().toString().split('.').first}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      if (widget.onRetry?.call(a.paper, a.question) == true) {
                        Navigator.pop(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Open paper ${a.paper} from your papers to retry this question.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
              ],
            );
          },
        ),
      );
}

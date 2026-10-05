import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/oqb_network_event.dart';

class OqbNetworkInspector extends StatelessWidget {
  const OqbNetworkInspector({
    super.key,
    required this.events,
    required this.onClear,
    this.clientLog = const <String>[],
  });

  final List<OqbNetworkEvent> events;
  final VoidCallback onClear;

  /// Non-sensitive Better OQB API client diagnostics (commands, outcomes and
  /// payload shapes; never tokens, sesskeys or field values).
  final List<String> clientLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final latestBySignature = <String, OqbNetworkEvent>{};
    for (final event in events) {
      if (!event.looksLikeApi || event.url.isEmpty) continue;
      latestBySignature[event.signature] = event;
    }
    final candidates = latestBySignature.values.toList().reversed.toList();

    Future<void> copyCapture() async {
      final payload = {
        'capturedAt': DateTime.now().toIso8601String(),
        'eventCount': events.length,
        'apiCandidates': candidates.map((event) => event.toJson()).toList(),
        'events': events.map((event) => event.toJson()).toList(),
      };
      await Clipboard.setData(
        ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert(payload),
        ),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API capture copied to clipboard')),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('OQB API inspector', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        '${events.length} network events • ${candidates.length} API candidates',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy capture as JSON',
                  onPressed: events.isEmpty ? null : copyCapture,
                  icon: const Icon(Icons.copy_all_outlined),
                ),
                IconButton(
                  tooltip: 'Clear capture',
                  onPressed: events.isEmpty ? null : onClear,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (clientLog.isNotEmpty)
            ExpansionTile(
              leading: const Icon(Icons.terminal),
              title: Text('Better OQB API client (${clientLog.length})'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView(
                    shrinkWrap: true,
                    reverse: true,
                    children: [
                      for (final line in clientLog.reversed)
                        SelectableText(line, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          Expanded(
            child: candidates.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No fetch/XHR/JSON endpoints captured yet.\n\n'
                        'Open the original OQB page, enter a paper, change a question, '
                        'select an answer and submit once. Then reopen this inspector.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final event = candidates[index];
                      final uri = Uri.tryParse(event.url);
                      final displayPath = uri == null
                          ? event.url
                          : '${uri.host}${uri.path}'
                              '${uri.hasQuery ? '?${uri.query}' : ''}';

                      return Card(
                        child: ExpansionTile(
                          leading: _MethodBadge(method: event.method),
                          title: Text(
                            displayPath,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              event.kind,
                              if (event.status != null) 'HTTP ${event.status}',
                              if (event.contentType.isNotEmpty) event.contentType,
                              if (event.durationMs != null)
                                '${event.durationMs!.toStringAsFixed(0)} ms',
                            ].join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: [
                            SelectableText(
                              event.url,
                              style: theme.textTheme.bodySmall,
                            ),
                            if (event.requestBody.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Request body',
                                  style: theme.textTheme.labelLarge,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(event.requestBody),
                            ],
                            if (event.responsePreview.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Response preview',
                                  style: theme.textTheme.labelLarge,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(event.responsePreview),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 46),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        method,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

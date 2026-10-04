import 'package:flutter/material.dart';

import '../models/oqb_page_state.dart';
import '../services/oqb_bridge.dart';
import '../widgets/oqb_browser.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  OqbPageState _page = const OqbPageState();
  bool _showInspector = false;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;

    final browser = OqbBrowser(
      bridge: OqbBridge(
        onPageState: (state) {
          if (mounted) setState(() => _page = state);
        },
      ),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('Better OQB'),
        actions: [
          IconButton(
            tooltip: 'Toggle OQB inspector',
            onPressed: () => setState(() => _showInspector = !_showInspector),
            icon: Icon(_showInspector ? Icons.data_object : Icons.data_object_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(
              children: [
                if (_showInspector)
                  SizedBox(width: 300, child: _Inspector(state: _page)),
                Expanded(child: browser),
              ],
            )
          : Column(
              children: [
                if (_showInspector)
                  SizedBox(height: 180, child: _Inspector(state: _page)),
                Expanded(child: browser),
              ],
            ),
    );
  }
}

class _Inspector extends StatelessWidget {
  const _Inspector({required this.state});

  final OqbPageState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headings = state.headings.take(8).toList();
    final actions = state.actions.take(12).toList();

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(
                state.isLoggedIn == true ? Icons.verified_user : Icons.language,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.title.isEmpty ? 'Waiting for OQB…' : state.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (state.url.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              state.url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (headings.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Detected sections', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            ...headings.map(
              (text) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $text', maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Detected actions', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: actions
                  .map((text) => Chip(label: Text(text, overflow: TextOverflow.ellipsis)))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

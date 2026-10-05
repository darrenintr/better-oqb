import 'package:flutter/material.dart';

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown while start_trial is loading a paper (or when it failed).
class PaperLoadingView extends StatelessWidget {
  const PaperLoadingView({
    super.key,
    required this.onOpenOriginal,
    this.questionNumber = 0,
    this.waitingForSession = false,
    this.error,
    this.onRetry,
    this.onBack,
  });

  final int questionNumber;
  final bool waitingForSession;
  final Object? error;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  final VoidCallback onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = error != null;
    return _StatusCard(
      children: [
        if (failed)
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error)
        else
          const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(
          failed
              ? 'Could not load this paper'
              : questionNumber > 0
                  ? 'Opening question $questionNumber'
                  : 'Opening paper',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          failed
              ? '$error'
              : waitingForSession
                  ? 'Waiting for the OQB session in the embedded browser…'
                  : 'Loading the attempt from OQB.',
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (onBack != null) TextButton(onPressed: onBack, child: const Text('Back')),
            if (onRetry != null) FilledButton(onPressed: onRetry, child: const Text('Retry')),
            OutlinedButton.icon(
              onPressed: onOpenOriginal,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Original OQB page'),
            ),
          ],
        ),
      ],
    );
  }
}

class BusyView extends StatelessWidget {
  const BusyView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _StatusCard(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

/// Before an authenticated OQB session is available.
class ConnectView extends StatelessWidget {
  const ConnectView({
    super.key,
    required this.isLoggedIn,
    required this.onOpenOriginal,
    this.url = '',
  });

  final bool? isLoggedIn;
  final String url;
  final VoidCallback onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loggedIn = isLoggedIn == true;
    return _StatusCard(
      children: [
        Icon(loggedIn ? Icons.hourglass_top : Icons.lock_open_outlined, size: 52, color: theme.colorScheme.primary),
        const SizedBox(height: 20),
        Text(
          loggedIn ? 'Connecting to OQB' : 'Sign in to OQB',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          loggedIn
              ? 'Better OQB is waiting for the OQB page to finish loading your '
                  'session. If this takes long, open OQB and go to the home page.'
              : 'Sign in on the real OQB page. Your login stays inside the embedded '
                  'browser; Better OQB never sees or stores your password or token.',
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onOpenOriginal,
          icon: const Icon(Icons.open_in_browser),
          label: Text(loggedIn ? 'Open OQB' : 'Open OQB sign in'),
        ),
        if (url.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            url,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

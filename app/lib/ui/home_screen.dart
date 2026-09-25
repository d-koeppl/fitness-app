import 'package:flutter/material.dart';

import '../api/meta_api.dart';

/// Phase 1's signed-in screen: proves the API accepts this account.
/// Replaced by the real shell in phase 4.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.signedInEmail, required this.signOut});

  final Future<String> Function() signedInEmail;
  final Future<void> Function() signOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<String> _email = widget.signedInEmail();

  void _retry() {
    // Start the request outside setState: an arrow closure there would
    // return the assigned Future, which setState rejects.
    final next = widget.signedInEmail();
    setState(() {
      _email = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fitness'),
        actions: [
          IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: widget.signOut),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<String>(
            future: _email,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }
              final (IconData icon, String label, Color color, bool canRetry) = switch (snapshot) {
                AsyncSnapshot(hasError: true, :final error) => switch (classifyApiError(error!)) {
                    ApiFailure.notAllowed =>
                      (Icons.block, 'This Google account is not allowed.', theme.colorScheme.error, false),
                    ApiFailure.notSignedIn =>
                      (Icons.lock_clock, 'Your session was not accepted. Sign in again.', theme.colorScheme.error, false),
                    ApiFailure.unreachable => (Icons.cloud_off, 'API unreachable', theme.colorScheme.error, true),
                  },
                AsyncSnapshot(:final data) => (Icons.verified_user, 'Signed in as $data', theme.colorScheme.primary, false),
              };
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 48, color: color),
                  const SizedBox(height: 12),
                  Text(label, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                  if (canRetry) ...[
                    const SizedBox(height: 16),
                    FilledButton.tonal(onPressed: _retry, child: const Text('Retry')),
                  ],
                  if (snapshot.hasError && !canRetry) ...[
                    const SizedBox(height: 16),
                    FilledButton.tonal(onPressed: widget.signOut, child: const Text('Sign out')),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
